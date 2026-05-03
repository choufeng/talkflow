# TalkFlow

macOS 桌面语音助手应用，将语音实时转写为文本，支持流式对话交互。

## 特性

- 🎤 麦克风权限自动检测与引导
- 🔊 菜单栏快捷控制（mic 图标，显示/隐藏窗口）
- 📝 语音实时转写
- 💬 流式对话交互

## 系统要求

- macOS 14.0+
- 麦克风权限

## 构建

```bash
open TalkFlow.xcodeproj
```

在 Xcode 中选择 `Product > Build`（⌘B）。

## 技术架构

本项目严格遵循函数式编程范式，详见 [AGENTS.md](AGENTS.md)。

## 开源协议

Apache License 2.0，详见 [LICENSE](LICENSE)。
