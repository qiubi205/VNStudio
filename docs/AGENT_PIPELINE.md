# Agent 加工流水线：VN Studio 导出包 → 完整游戏 APK

> 给 AI agent（或人）的操作手册。目标：把 APP 导出的 zip 变成**可安装、可通关、有包装**的安卓视觉小说。

## 输入

`<slug>.zip`，内含 `project.json`（格式见 FORMAT.md）、`assets/`、`README.md`。

## 步骤

### 1. 解包与校验
```bash
unzip xxx.zip -d work/
python3 - <<'EOF'
import json
p = json.load(open('work/<slug>/project.json'))
ids = {s['id'] for s in p['script']['scenes']}
assert p['script']['start_scene'] in ids
for s in p['script']['scenes']:
    for ch in s['choices']:
        assert ch['next'] in ids or ch['next'] == ''
    assert s['next'] in ids or s['next'] == ''
print('OK', len(p['script']['scenes']), 'scenes')
EOF
```
修正任何违规引用（把悬空 next 改为空=结局）。

### 2. 生成 Ren'Py 工程
```bash
python3 tools/json_to_renpy.py work/<slug>/project.json -o game/
```
- 输出 `game/script.rpy`、`game/options.rpy`、`game/images/`、`game/audio/`
- 素材文件名若含空格/中文，转换器会统一 slug 化并同步 JSON 引用

### 3. 人工/AI 润色（可选项，提升"完整游戏"感）
- 标题画面、主菜单、设置、存档（Ren'Py 自带，`options.rpy` 配置）
- CG 回顾 / 结局收集（`persistent` + `gallery` 屏）
- 缺失素材（bg/cg/bgm 为空）→ 用 AI 生图/生乐补齐，或加纯色背景占位
- 旁白样式、打字机效果、对话框头像（`define` 角色 + `image`）

### 4. 本地/CI 验证
- 本地：装 Ren'Py SDK，`renpy.sh game` 跑一遍全流程（含全部分支）
- CI：把 `game/` 放进带 Ren'Py Android 构建 workflow 的仓库，出 APK

### 5. 交付
- APK 签名后发给用户安装（注意：目标设备 Android 10，minSdk 建议 21+）

## 常见问题

- **素材缺失**：JSON 引用但 assets 里没有 → 生成占位图（纯色+场景名）并继续，别中断流程
- **超长台词**：Ren'Py 一行过长可换行拼接；文本里有 `"` 需转义
- **分支过多**：确保所有场景从 start 可达；不可达场景（死代码）可保留为隐藏结局
- **中文**：Ren'Py 原生支持 UTF-8，无需额外字体；安卓上默认字体可显示中文
