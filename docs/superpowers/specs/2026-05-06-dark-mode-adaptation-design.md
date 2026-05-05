# 明暗模式自动适配 — 主窗体 UI 修复设计

**日期**: 2026-05-06
**状态**: 已确认

---

## 问题

桌面主窗体在系统级切换明亮/黑暗模式时，仅极少数组件（使用语义 `NSColor` 的 `NSTextField`）自动跟随，其余组件存在严重视觉断层。

### 根因分析

| 问题分类 | 涉及组件 | 原因 |
|---------|---------|------|
| **Layer CGColor 静态快照** | CardView（背景+边框）、PipelineStatusView（背景+边框）、PulseRingView（ring/dot 颜色） | `layer?.backgroundColor = someNSColor.cgColor` 在赋值时捕获当前外观的 CGColor 快照，`effectiveAppearance` 变化后不自动刷新 |
| **硬编码 RGB** | JellyfishView（全部 cyan）、PipelineStatusView（转写标签 cyan、粘贴失败 amber） | `NSColor(red:green:blue:alpha:)` 创建静态色，不响应外观变化 |

### AppKit 预期解决方案

Apple 为 layer-backed view 提供了两个专用 API：

- `updateLayer()` — 当 view 自身的 `layer` 属性需要根据 appearance 变化更新时调用
- `viewDidChangeEffectiveAppearance()` — 当 view 的 effectiveAppearance 变化时调用，适用于子 layer（`CAShapeLayer`）

---

## 修改范围

### 4 个文件

| 文件 | 覆写方法 | 原因 |
|------|---------|------|
| `CardView.swift` | `updateLayer()` | 修改 view.layer 的 backgroundColor / borderColor |
| `PipelineStatusView.swift` | `updateLayer()` + 硬编码色替换 | 同上 + 转写标签/粘贴失败颜色改为语义色 |
| `JellyfishView.swift` | `viewDidChangeEffectiveAppearance()` | 修改 CAShapeLayer 子 layer（bellLayer, innerGlowLayer, tentacleLayers） |
| `PulseRingView.swift` | `viewDidChangeEffectiveAppearance()` | 修改 CAShapeLayer 子 layer（ringLayer, dotLayer） |

### 硬编码色 → 语义色映射

| 原值 | 新值 | 说明 |
|------|------|------|
| `NSColor(red: 0, green: 0.78, blue: 1.0, ...)` — JellyfishView 全线 cyan | `.controlAccentColor` | 跟随系统强调色设定 |
| `NSColor(red: 0, green: 0.78, blue: 1.0, ...)` — PipelineStatusView 转写标签 | `.controlAccentColor` | 与水母动画一致 |
| `NSColor(red: 1.0, green: 0.69, blue: 0.13, ...)` — PipelineStatusView 粘贴失败 | `.systemOrange` | 语义色自动适配 |

### 实现模式

每处修改均为**纯增量**：新增 override 方法 + 提取颜色更新逻辑。不改任何现有方法签名或行为。

```swift
// 模式 1 — view 自身 layer（CardView, PipelineStatusView）
override func updateLayer() {
    super.updateLayer()
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    layer?.borderColor = NSColor.separatorColor.cgColor
}

// 模式 2 — sublayer CAShapeLayer（JellyfishView, PulseRingView）
override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    // 重新赋值所有 CAShapeLayer 颜色属性
}
```

---

## 不变部分

以下已正确使用语义 `NSColor` 的代码**无需修改**：

- 所有 `NSTextField.textColor`（`.secondaryLabelColor`, `.tertiaryLabelColor`, `.systemGreen`, `.systemRed`, `.placeholderTextColor` 等）
- `NSTextView.textColor` / `.backgroundColor`（`.textColor`, `.textBackgroundColor`, `.labelColor`, `.controlBackgroundColor`）
- `NSBox` 分隔线（`.separator` boxType 自动跟随）

---

## 测试要点

- 系统设置 → 外观 → 切换 明亮/黑暗/自动，观察主窗口各卡片背景色、边框色是否正确跟随
- 浮动面板（录制态、转写态、粘贴失败态）背景与文字在两种模式下可读性
- 水母动画颜色在两种模式下均与强调色一致
- 呼吸环红色在两种模式下可见度
- 日志查看器窗口分屏在两种模式下的行交替色
