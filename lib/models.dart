// VN Studio · 视觉小说创作工坊 — 数据模型
// 内部存储与导出的 project.json 使用同一套 schema（format: vnstudio/project@1）
import 'dart:ui' show Color;

Script emptyScript() => Script(
      title: '',
      summary: '',
      start: 's1',
      scenes: [
        Scene(id: 's1', name: '场景 1', dialogue: [Line()]),
      ],
    );

class Line {
  String speaker;
  String text;
  String cg;
  String cgHint;
  Line({this.speaker = '', this.text = '', this.cg = '', this.cgHint = ''});

  factory Line.fromJson(Map<String, dynamic> j) => Line(
        speaker: (j['speaker'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        cg: (j['cg'] as String?) ?? '',
        cgHint: (j['cg_hint'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'speaker': speaker, 'text': text, 'cg': cg, 'cg_hint': cgHint};
}

class Choice {
  String text;
  String next;
  Choice({this.text = '', this.next = ''});

  factory Choice.fromJson(Map<String, dynamic> j) => Choice(
        text: (j['text'] as String?) ?? '',
        next: (j['next'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {'text': text, 'next': next};
}

class Scene {
  String id;
  String name;
  String bg;
  String bgm;
  String bgHint;
  String bgmHint;
  double bgmVolume;
  String next;
  List<Line> dialogue;
  List<Choice> choices;

  Scene({
    required this.id,
    this.name = '',
    this.bg = '',
    this.bgm = '',
    this.bgHint = '',
    this.bgmHint = '',
    this.bgmVolume = 0.8,
    this.next = '',
    List<Line>? dialogue,
    List<Choice>? choices,
  })  : dialogue = dialogue ?? [],
        choices = choices ?? [];

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        bg: (j['bg'] as String?) ?? '',
        bgm: (j['bgm'] as String?) ?? '',
        bgHint: (j['bg_hint'] as String?) ?? '',
        bgmHint: (j['bgm_hint'] as String?) ?? '',
        bgmVolume: ((j['bgm_volume'] as num?) ?? 0.8).toDouble(),
        next: (j['next'] as String?) ?? '',
        dialogue: (j['dialogue'] as List?)
                ?.map((e) => Line.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        choices: (j['choices'] as List?)
                ?.map((e) => Choice.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bg': bg,
        'bgm': bgm,
        'bg_hint': bgHint,
        'bgm_hint': bgmHint,
        'bgm_volume': bgmVolume,
        'bgm_loop': true,
        'dialogue': dialogue.map((e) => e.toJson()).toList(),
        'choices': choices.map((e) => e.toJson()).toList(),
        'next': next,
      };
}

class Script {
  String title;
  String summary;
  String start;
  List<Scene> scenes;

  Script({this.title = '', this.summary = '', this.start = '', List<Scene>? scenes})
      : scenes = scenes ?? [];

  factory Script.fromJson(Map<String, dynamic> j) => Script(
        title: (j['title'] as String?) ?? '',
        summary: (j['summary'] as String?) ?? '',
        start: (j['start_scene'] as String?) ?? (j['start'] as String?) ?? '',
        scenes: (j['scenes'] as List?)
                ?.map((e) => Scene.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'start_scene': start,
        'scenes': scenes.map((e) => e.toJson()).toList(),
      };

  int indexOfScene(String id) => scenes.indexWhere((s) => s.id == id);

  Scene? findScene(String id) {
    for (final s in scenes) {
      if (s.id == id) return s;
    }
    return null;
  }
}

class Character {
  String id;
  String name;
  String color;
  Character({required this.id, this.name = '', this.color = '#ff7ab8'});

  factory Character.fromJson(Map<String, dynamic> j) => Character(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        color: (j['color'] as String?) ?? '#ff7ab8',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
}

class Project {
  String id;
  String title;
  String desc;
  int created;
  int updated;
  Script script;
  List<Character> characters;

  Project({
    required this.id,
    this.title = '',
    this.desc = '',
    int? created,
    int? updated,
    Script? script,
    List<Character>? characters,
  })  : created = created ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updated = updated ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        script = script ?? emptyScript(),
        characters = characters ?? <Character>[];

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        desc: (j['desc'] as String?) ?? '',
        created: (j['created'] as num?)?.toInt(),
        updated: (j['updated'] as num?)?.toInt(),
        script: j['script'] is Map<String, dynamic>
            ? Script.fromJson(j['script'] as Map<String, dynamic>)
            : emptyScript(),
        characters: (j['characters'] as List?)
                ?.map((e) => Character.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'format': 'vnstudio/project@1',
        'id': id,
        'title': title,
        'desc': desc,
        'created': created,
        'updated': updated,
        'script': script.toJson(),
        'characters': characters.map((e) => e.toJson()).toList(),
      };
}

Color parseColor(String hex) {
  try {
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'ff$h';
    return Color(int.parse('0x$h'));
  } catch (_) {
    return const Color(0xFFFF7AB8);
  }
}

String fmtTime(int epochSec) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
