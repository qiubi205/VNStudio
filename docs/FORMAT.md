# VN Studio 导出格式（Agent 契约）

> 本文件是 **VN Studio 导出 zip 的权威格式说明**。任何 AI agent 处理导出包时以此为准。

## 包结构

```
<slug>/
  project.json    权威数据源（完整剧情 + 角色 + 素材清单）
  assets/         BGM/CG 原文件（被 project.json 引用）
  README.md       随包附带的加工指引（与本文等价）
```

## project.json

```json
{
  "format": "vnstudio/project@1",
  "id": "字符串ID",
  "title": "作品标题",
  "desc": "简介",
  "created": 1710000000,
  "updated": 1710000000,
  "script": {
    "title": "游戏标题（可与作品标题不同）",
    "summary": "一句话简介",
    "start_scene": "s1",
    "scenes": [
      {
        "id": "s1",
        "name": "场景名",
        "bg": "背景图文件名（assets/ 下；空字符串=无）",
        "bgm": "BGM 文件名（空=无）",
        "bgm_volume": 0.8,
        "bgm_loop": true,
        "bg_hint": "AI 建议的背景画面描述（仅提示，非强制）",
        "bgm_hint": "AI 建议的音乐风格（仅提示）",
        "dialogue": [
          {
            "speaker": "说话人姓名（空字符串=旁白）",
            "text": "台词内容",
            "cg": "本句 CG 文件名（空=无）",
            "cg_hint": "AI 建议的画面描述（仅提示）"
          }
        ],
        "choices": [
          {"text": "选项文字", "next": "目标场景 id"}
        ],
        "next": "无选项时自动进入的下一场景 id（空字符串=结局）"
      }
    ]
  },
  "characters": [
    {"id": "c1", "name": "角色名", "color": "#ff7ab8"}
  ],
  "assets": {
    "bgm": ["audio1.mp3"],
    "cg": ["img1.png"]
  }
}
```

## 语义规则（agent 必须校验）

1. `script.start_scene` 必须指向 `scenes` 中存在的 id
2. `scenes[].choices[].next` 与 `scenes[].next` 若非空，必须指向存在的场景 id
3. 场景内 `dialogue` 按顺序逐句播放；播完后：
   - 有 `choices` → 显示选项，点击跳 `next` 场景
   - 无 `choices` 且 `next` 非空 → 自动进入 `next`
   - 无 `choices` 且 `next` 为空 → **结局**（游戏结束）
4. `bg` / `bgm` / `cg` 引用的文件名必须存在于 `assets/`；缺失时 agent 应生成占位素材或留空
5. 引擎内无法识别的字段（`*_hint`、`bgm_loop` 等）可忽略，不得报错

## 加工建议（最小改动 → 完整游戏）

- **默认目标引擎：Ren'Py**（脚本可读、免费、官方支持安卓打包）
- 映射关系：
  - 场景 → `label 场景id:`；进入时 `scene 背景`（若有 bg）、`play music bgm loop volume 0.8`（若有 bgm）
  - 台词 → 直接写文本；有 speaker 用 `speaker "名字"`（先在 define 里建角色并配色）
  - choices → `menu:` 块，`"选项文字": jump 目标id`
  - next → `jump 目标id`
  - 结局场景 → `return` / `jump ending`
- 素材放 `game/images/`（bg、cg）与 `game/audio/`（bgm），文件名保持与 JSON 一致（中文/空格需处理或改名并同步 JSON）
- 包装：标题画面、存档（Ren'Py 自带）、CG 回顾页、设置页
- 打包安卓 APK：Ren'Py SDK 的 Android 支持（rapt），或 CI workflow
