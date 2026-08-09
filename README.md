# VN Studio · 视觉小说创作工坊

Android 原生 APP：**自主安排视觉小说游戏的全部流程，并自由编辑 BGM / CG / 剧本**。
用 GitHub 开源工具链构建（Flutter + GitHub Actions），一键产出 APK。

## 这是什么

一个跑在安卓手机上的「视觉小说创作工坊」：

- 🤖 **AI 自主安排全部流程**：输入主题 → DeepSeek 自动生成完整剧本（场景 / 台词 / 分支选项 / BGM 与 CG 提示），生成后仍可逐项自由编辑
- 📝 **流程自由编辑**：场景增删排序、台词增删调序、分支选项与跳转、角色管理（说话人配色）
- 🎵🎨 **BGM / CG 自由管理**：从手机相册/文件里添加图片与音乐，逐场景、逐句指派背景 / 立绘 / BGM（音量可调）
- ▶️ **内嵌试玩**：BGM 循环、CG 立绘、分支选择、快进、对话履历、自动存档续玩
- 📦 **Agent 友好导出**：导出 zip（`project.json` + `assets/` + `README.md`），任何 AI agent 拿到即可理解并**进一步加工成完整的游戏**（推荐转 Ren'Py 工程并打包安卓 APK）

## 目录结构

```
lib/                  Flutter 源码
  main.dart           入口
  models.dart         数据模型（与导出 schema 一致）
  storage.dart        本地存储（项目/资产/存档）
  services.dart       AI 生成 + 导出服务
  screens.dart        全部界面
docs/
  FORMAT.md           导出格式（project.json schema）—— agent 契约
  AGENT_PIPELINE.md   agent 加工流水线指引
tools/
  json_to_renpy.py    project.json → Ren'Py 工程转换器（agent 可运行/改进）
.github/workflows/
  build.yml           GitHub Actions 自动构建 APK
```

## 构建 APK

推到 GitHub 后 Actions 自动构建：仓库 Actions 页面 → `Build APK` → 下载 `vnstudio-apk` 产物。
本地构建：`flutter build apk --release`（需 Flutter + Android SDK）。

## 导出 → 完整游戏 流水线（agent 加工）

1. APP 里「📦 导出并分享」→ 得到 `xxx.zip`（project.json + assets + README）
2. 把 zip 交给任何 AI agent（或本仓库 `tools/json_to_renpy.py`）
3. agent 校验 JSON → 生成 Ren'Py 工程（或其它引擎）→ 补齐游戏性包装
4. 用 Ren'Py SDK / CI 打包安卓 APK → 完整的可玩游戏

详细契约见 [docs/FORMAT.md](docs/FORMAT.md) 与 [docs/AGENT_PIPELINE.md](docs/AGENT_PIPELINE.md)。
