// VN Studio · 服务层：AI 剧本生成 + 项目导出（agent 可加工格式）
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'storage.dart';

// ---------------- AI 设置 ----------------
class AiSettings {
  String endpoint;
  String apiKey;
  String model;

  AiSettings({
    this.endpoint = 'https://api.deepseek.com/v1/chat/completions',
    this.apiKey = '',
    this.model = 'deepseek-v4-flash',
  });

  factory AiSettings.fromJson(Map<String, dynamic> j) => AiSettings(
        endpoint: (j['endpoint'] as String?) ??
            'https://api.deepseek.com/v1/chat/completions',
        apiKey: (j['api_key'] as String?) ?? '',
        model: (j['model'] as String?) ?? 'deepseek-v4-flash',
      );

  Map<String, dynamic> toJson() =>
      {'endpoint': endpoint, 'api_key': apiKey, 'model': model};
}

// ---------------- AI 服务 ----------------
class AiService {
  static Future<AiSettings> loadSettings() async {
    final f = File('${(await Storage.root()).path}/settings.json');
    if (!await f.exists()) return AiSettings();
    try {
      return AiSettings.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return AiSettings();
    }
  }

  static Future<void> saveSettings(AiSettings s) async {
    await File('${(await Storage.root()).path}/settings.json')
        .writeAsString(jsonEncode(s.toJson()));
  }

  static const String systemPrompt = '''
你是一位专业的视觉小说（Visual Novel）剧本作家，擅长创作有分支的互动剧情。
请根据用户的设定生成完整的剧本，并输出为严格的 JSON 对象，格式如下：
{
  "title": "作品标题",
  "summary": "一句话简介",
  "start_scene": "s1",
  "scenes": [
    {
      "id": "s1",
      "name": "场景名称",
      "bg_hint": "此场景的背景画面描述（用于之后配背景图/CG）",
      "bgm_hint": "此场景的BGM风格提示（如：轻快钢琴 / 悬疑低音 / 温柔弦乐）",
      "dialogue": [
        {"speaker": "角色名（旁白则留空字符串）", "text": "台词内容", "cg_hint": "这一句可搭配的画面描述（没有则空字符串）"}
      ],
      "choices": [
        {"text": "选项文字", "next": "s2"}
      ],
      "next": "s3"
    }
  ]
}
硬性要求：
1. 场景数量符合用户要求的篇幅；id 用 s1、s2… 命名；scenes 数组按剧情顺序排列
2. 至少有一个场景包含 choices 分支；choices 的 next 必须指向存在的场景 id
3. 剧情要有分支并且最终能汇合；最终场景没有 choices 也没有 next
4. 每个场景 2~6 句台词，台词自然、口语化、有画面感，符合视觉小说文风
5. bg_hint / bgm_hint / cg_hint 用简短中文描述，方便后续配图配乐
6. 只输出 JSON 本身，不要输出任何其他文字，不要用 markdown 代码块''';

  /// 有密钥→调真实 AI；无密钥→返回内置示例剧本（demo=true 由调用方提示）
  static Future<({Script script, bool demo})> generate({
    required String premise,
    String genre = '日常',
    String length = '中',
    String tone = '轻松温暖',
  }) async {
    final s = await loadSettings();
    if (s.apiKey.isEmpty) {
      return (script: demoScript(premise), demo: true);
    }
    final sceneCount = length == '短'
        ? '3~5'
        : (length == '长' ? '8~12' : '5~8');
    final user =
        '请创作一部视觉小说剧本。\n主题/背景设定：${premise.trim().isEmpty ? '（未指定，请自由发挥一个温馨的日常主题）' : premise.trim()}\n类型：$genre\n篇幅：约 $sceneCount 个场景\n氛围/文风：$tone\n标题由你决定。';
    final body = jsonEncode({
      'model': s.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.95,
      'stream': false,
    });
    final resp = await http
        .post(
          Uri.parse(s.endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${s.apiKey}',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 180));
    if (resp.statusCode != 200) {
      throw Exception(
          'AI 接口错误 HTTP ${resp.statusCode}: ${utf8.decode(resp.bodyBytes)}');
    }
    final map =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = map['choices'] as List;
    if (choices.isEmpty) throw Exception('AI 返回为空');
    final content = (choices.first['message'] as Map)['content'] as String;
    final j = extractJsonObject(content);
    var script = Script.fromJson(j);
    script = normalize(script);
    return (script: script, demo: false);
  }

  /// 把 AI 结果规整成可用状态：start 兜底、场景 id 兜底、空台词补位
  static Script normalize(Script script) {
    if (script.scenes.isEmpty) {
      return emptyScript();
    }
    final seen = <String>{};
    for (var i = 0; i < script.scenes.length; i++) {
      final sc = script.scenes[i];
      var id = sc.id.trim();
      if (id.isEmpty || seen.contains(id)) {
        id = 's${i + 1}';
        var n = i + 1;
        while (seen.contains(id)) {
          n++;
          id = 's$n';
        }
        sc.id = id;
      }
      seen.add(id);
      if (sc.dialogue.isEmpty) sc.dialogue.add(Line());
      if (sc.name.trim().isEmpty) sc.name = '场景 ${i + 1}';
    }
    if (script.start.isEmpty || !seen.contains(script.start)) {
      script.start = script.scenes.first.id;
    }
    return script;
  }

  static Map<String, dynamic> extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw Exception('AI 输出中没有可解析的 JSON');
    }
    return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
  }

  /// 把台词里的说话人自动补进角色表
  static void autoAddCharacters(Project p) {
    final names = <String>{};
    for (final sc in p.script.scenes) {
      for (final ln in sc.dialogue) {
        final n = ln.speaker.trim();
        if (n.isNotEmpty) names.add(n);
      }
    }
    final existing = p.characters.map((c) => c.name).toSet();
    for (final n in names) {
      if (!existing.contains(n)) {
        p.characters
            .add(Character(id: 'c${p.characters.length + 1}', name: n));
      }
    }
  }

  static Script demoScript(String premise) {
    final t = premise.trim().isEmpty ? '与优香的放学后' : premise.trim();
    return Script(
      title: t,
      summary: 'AI 未配置密钥时的示例剧本（可自由编辑、自由更换 BGM/CG）',
      start: 's1',
      scenes: [
        Scene(
          id: 's1',
          name: '放学后的教室',
          bgHint: '夕阳斜照的教室',
          bgmHint: '轻快温柔的钢琴曲',
          dialogue: [
            Line(speaker: '优香', text: '今天也辛苦啦！作业写完的话，要不要一起去商店街逛逛？'),
            Line(text: '夕阳把教室染成一片金黄，优香的眼睛亮晶晶的。'),
          ],
          choices: [
            Choice(text: '好呀，走吧！', next: 's2'),
            Choice(text: '抱歉，我还有作业要写……', next: 's3'),
          ],
        ),
        Scene(
          id: 's2',
          name: '商店街的黄昏',
          bgHint: '热闹的商店街黄昏',
          bgmHint: '欢快的进行曲',
          dialogue: [
            Line(speaker: '优香', text: '哇，新出的鲷鱼烧！老板说今天买一送一！'),
            Line(speaker: '优香', text: '……嘿嘿，其实我是特意等你一起的。一个人吃多没意思。'),
          ],
          next: 's4',
        ),
        Scene(
          id: 's3',
          name: '空无一人的教室',
          bgHint: '夜晚安静的教室',
          bgmHint: '安静抒情的钢琴',
          dialogue: [
            Line(text: '教室里只剩下笔尖沙沙的声音。'),
            Line(speaker: '优香', text: '那我……先走啦。明天见！'),
            Line(text: '不知道为什么，总觉得有点后悔。'),
          ],
          next: 's4',
        ),
        Scene(
          id: 's4',
          name: '第二天清晨',
          bgHint: '清晨的校门口',
          bgmHint: '清新明亮的小提琴',
          dialogue: [
            Line(speaker: '优香', text: '早！昨天的事……我其实一直想跟你说。'),
            Line(speaker: '优香', text: '下次，一起去看电影吧？就这样说定了哦！'),
            Line(text: '——新的故事，才刚刚开始。'),
          ],
        ),
      ],
    );
  }
}

// ---------------- 导出服务 ----------------
class ExportService {
  static const List<String> audioExts = [
    'mp3', 'wav', 'ogg', 'm4a', 'flac', 'aac', 'opus',
  ];
  static const List<String> imageExts = [
    'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp',
  ];

  static bool isAudio(String path) {
    final e = path.split('.').last.toLowerCase();
    return audioExts.contains(e);
  }

  static bool isImage(String path) {
    final e = path.split('.').last.toLowerCase();
    return imageExts.contains(e);
  }

  /// 导出为 zip：project.json（canonical）+ README.md（agent 指引）+ assets/
  /// 返回 zip 文件路径
  static Future<String> buildZip(Project p) async {
    final outDir = await Storage.exportsDir();
    final slug = Storage.sanitizeName(p.title).replaceAll(' ', '_');
    final zipPath = '${outDir.path}/${slug}_${p.id}.zip';

    final assets = await Storage.listAssets(p.id);
    final manifest = <String, List<String>>{'bgm': [], 'cg': []};
    for (final f in assets) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (isAudio(name)) {
        manifest['bgm']!.add(name);
      } else if (isImage(name)) {
        manifest['cg']!.add(name);
      }
    }

    final canonical = Map<String, dynamic>.from(p.toJson());
    canonical['assets'] = manifest;

    final archive = Archive();
    void addText(String path, String content) {
      final bytes = utf8.encode(content);
      archive.add(ArchiveFile(path, bytes.length, bytes));
    }

    addText('$slug/project.json',
        const JsonEncoder.withIndent('  ').convert(canonical));
    addText('$slug/README.md', readme(p, slug));
    for (final f in assets) {
      final bytes = await f.readAsBytes();
      archive.add(ArchiveFile('$slug/assets/${f.path.split(Platform.pathSeparator).last}',
          bytes.length, bytes));
    }

    final zipped = ZipEncoder().encode(archive);
    final out = File(zipPath);
    await out.create(recursive: true);
    await out.writeAsBytes(zipped);
    return zipPath;
  }

  /// 随包附带的 agent 指引（任何 AI agent 拿到此文件即可理解如何加工）
  static String readme(Project p, String slug) {
    return '''# $slug — VN Studio 导出项目包

这是由「VN Studio · 视觉小说创作工坊」导出的视觉小说项目，**专为 AI agent 加工设计**。

## 文件清单
- `project.json` — 唯一权威数据源（完整剧情 + 角色 + 资产清单）
- `assets/` — 图片（CG/背景）与音乐（BGM）文件，被 project.json 引用
- `README.md` — 本文件（给 agent 看的加工指引）

## project.json 结构（format: vnstudio/project@1）
```json
{
  "format": "vnstudio/project@1",
  "id": "项目ID",
  "title": "作品标题",
  "desc": "简介",
  "script": {
    "title": "游戏标题",
    "summary": "一句话简介",
    "start_scene": "起始场景id",
    "scenes": [
      {
        "id": "s1",
        "name": "场景名",
        "bg": "背景图文件名(assets/下, 可为空)",
        "bgm": "BGM文件名(可为空)",
        "bgm_volume": 0.8,
        "bg_hint": "AI建议的背景画面描述",
        "bgm_hint": "AI建议的音乐风格",
        "dialogue": [
          {"speaker": "说话人(空=旁白)", "text": "台词", "cg": "本句CG文件名(可为空)", "cg_hint": "AI建议画面"}
        ],
        "choices": [{"text": "选项文字", "next": "目标场景id"}],
        "next": "无选项时自动进入的下一场景id(空=结局)"
      }
    ]
  },
  "characters": [{"id": "c1", "name": "角色名", "color": "#ff7ab8"}],
  "assets": {"bgm": ["文件名..."], "cg": ["文件名..."]}
}
```

## 给 Agent 的加工流程（推荐）
1. 读取 `project.json`，校验：start_scene 存在、choices[].next 与 scenes[].next 都指向存在的场景、assets 文件名都能在 assets/ 找到。
2. 按 `script` 生成完整游戏工程。推荐目标：**Ren'Py**（脚本可读性强、支持安卓打包）：
   - 每个场景 → `label`；dialogue → 台词行；choices → `menu`；bg → `scene/show`；bgm → `play music`（volume 用 bgm_volume）。
   - 素材放入 `game/images/` 与 `game/audio/`。
3. 补齐游戏性包装（标题画面、存档、回退、结局收集等）。
4. 打包安卓 APK（Ren'Py SDK 或 CI workflow），必要时补 UI 资源。
5. 如素材缺失（bg/cg/bgm 为空），可用 AI 生成图片/音乐补齐，或留占位。

## 可编辑性
JSON 是纯文本，任何 agent 都能直接增删场景、改分支、换 BGM/CG 文件名，改完重新打包即可。
本包不包含二进制引擎，只是"故事 + 素材"的中间格式。
''';
  }
}
