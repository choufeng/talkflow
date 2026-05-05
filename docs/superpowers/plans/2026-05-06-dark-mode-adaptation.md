# 明暗模式自动适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为主窗体 4 个视图组件添加明暗模式自动跟随能力，修复 Layer CGColor 静态快照与硬编码 RGB 问题。

**Architecture:** 每个视图独立覆写 AppKit 的 appearance 回调（`updateLayer()` 或 `viewDidChangeEffectiveAppearance()`），在回调中重新赋值 layer 颜色属性。硬编码 RGB 替换为语义色。

**Tech Stack:** Swift, AppKit, CALayer / CAShapeLayer

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `TalkFlow/Views/CardView.swift` | 修改 | 卡片容器，新增 `updateLayer()` |
| `TalkFlow/Views/PipelineStatusView.swift` | 修改 | 浮动管线状态面板，新增 `updateLayer()` + 硬编码色替换 |
| `TalkFlow/Views/JellyfishView.swift` | 修改 | 水母动画，新增 `viewDidChangeEffectiveAppearance()` + cyan → controlAccentColor |
| `TalkFlow/Views/PulseRingView.swift` | 修改 | 录制呼吸环，新增 `viewDidChangeEffectiveAppearance()` |

---

### Task 1: CardView — 新增 updateLayer() 覆写

**Files:**
- Modify: `TalkFlow/Views/CardView.swift`

- [ ] **Step 1: 在 CardView 类中新增 updateLayer() 覆写**

在 `CardView` 类的 `impureSetupUI()` 方法之后，`// MARK: - ⚠️ UI 构建` 区域之前，添加：

```swift
    // MARK: - Appearance

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
```

> 注意：`updateLayer()` 在 view 标记 `wantsLayer = true` 且 appearance 变化时自动调用。

- [ ] **Step 2: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/Views/CardView.swift
git commit -m "feat: CardView 明暗模式 layer 颜色自适应"
```

---

### Task 2: PipelineStatusView — 新增 updateLayer() + 硬编码色替换

**Files:**
- Modify: `TalkFlow/Views/PipelineStatusView.swift`

- [ ] **Step 1: 新增 updateLayer() 覆写**

在 `impureSetupUI()` 方法之后添加：

```swift
    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
```

- [ ] **Step 2: 转写标签颜色替换（硬编码 cyan → controlAccentColor）**

在 `impureBuildTranscribing()` 方法中，找到：

```swift
label.textColor = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 1.0)
```

替换为：

```swift
label.textColor = .controlAccentColor
```

- [ ] **Step 3: 粘贴失败态颜色替换（硬编码 amber → systemOrange）**

在 `impureBuildPasteFailed()` 方法中，找到两处硬编码 amber：

第一处（warnIcon contentTintColor）：

```swift
warnIcon.contentTintColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1.0)
```

替换为：

```swift
warnIcon.contentTintColor = .systemOrange
```

第二处（label textColor）：

```swift
label.textColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1.0)
```

替换为：

```swift
label.textColor = .systemOrange
```

第三处（layer borderColor）：

```swift
layer?.borderColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 0.3).cgColor
```

替换为：

```swift
layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.3).cgColor
```

- [ ] **Step 4: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Views/PipelineStatusView.swift
git commit -m "feat: PipelineStatusView 明暗模式自适应 + 硬编码色替换为语义色"
```

---

### Task 3: JellyfishView — 新增 viewDidChangeEffectiveAppearance() + cyan → controlAccentColor

**Files:**
- Modify: `TalkFlow/Views/JellyfishView.swift`

- [ ] **Step 1: 移除硬编码 cyan 存储属性，新增 accentColor 计算属性 + 颜色应用方法**

找到类顶部属性声明区：

```swift
    // 颜色
    private let cyan = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 1.0).cgColor
    private let cyanGlow = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 0.15).cgColor
```

替换为：

```swift
    // 颜色 — 跟随系统强调色
    private var accentColor: NSColor { .controlAccentColor }

    private func applyAccentColors() {
        let accent = accentColor
        let accentCG = accent.cgColor
        let glowCG = accent.withAlphaComponent(0.15).cgColor
        let fillCG = accent.withAlphaComponent(0.08).cgColor

        bellLayer.fillColor = fillCG
        bellLayer.strokeColor = accentCG
        bellLayer.shadowColor = accentCG
        innerGlowLayer.fillColor = glowCG
        innerGlowLayer.shadowColor = accentCG
        tentacleLayers.forEach {
            $0.strokeColor = accentCG
            $0.shadowColor = accentCG
        }
    }
```

- [ ] **Step 2: 更新 init() 中的颜色设置**

2a. 删除 `bellLayer.fillColor = ...cgColor` 行（alpha 0.08 那行）及 `bellLayer.strokeColor = cyan` 行及 `bellLayer.shadowColor = cyan` 行。在 `bellLayer.shadowOffset = .zero` 之后插入：

```swift
        applyAccentColors()
```

2b. 删除 `innerGlowLayer.fillColor = cyanGlow` 行及 `innerGlowLayer.shadowColor = cyan` 行。

2c. 在触须 for 循环中，删除 `t.strokeColor = cyan` 行及 `t.shadowColor = cyan` 行。

> `applyAccentColors()` 内部已包含 bellLayer fill/stroke/shadow、innerGlowLayer fill/shadow、以及所有 tentacleLayers stroke/shadow 的统一设置。

**init() 最终效果：** 所有颜色赋值集中在 `applyAccentColors()` 一处调用，其余不变（lineWidth、shadowRadius、opacity 等保持原样）。

- [ ] **Step 3: 新增 viewDidChangeEffectiveAppearance() 覆写**

在 `layout()` 方法之后添加：

```swift
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAccentColors()
    }
```

- [ ] **Step 4: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Views/JellyfishView.swift
git commit -m "feat: JellyfishView accentColor 自适应 + viewDidChangeEffectiveAppearance"
```

---

### Task 4: PulseRingView — 新增 viewDidChangeEffectiveAppearance()

**Files:**
- Modify: `TalkFlow/Views/PulseRingView.swift`

- [ ] **Step 1: 新增 viewDidChangeEffectiveAppearance() 覆写**

在 `layout()` 方法之后添加：

```swift
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let red = NSColor.systemRed.cgColor
        ringLayer.strokeColor = red
        ringLayer.shadowColor = red
        dotLayer.fillColor = red
    }
```

- [ ] **Step 2: 编译验证**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/Views/PulseRingView.swift
git commit -m "feat: PulseRingView 明暗模式自适应"
```

---

### Task 5: 全量编译 + 运行测试

- [ ] **Step 1: 全量编译**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: 运行现有测试**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: 手动验证清单（需人工操作）**

1. 启动应用
2. 系统设置 → 外观 → 切换至**黑暗模式**
3. 观察主窗口：
   - 所有卡片（权限、快捷键、转写、翻译、模型、日志）背景应为深色、边框为深色分隔线
   - 卡片标题和内容文字可读
4. 触发录音：浮动面板背景应为深色、红色 REC/计时器可见
5. 停止录音进入转写态：水母动画颜色应跟随系统强调色（非固定 cyan）、"转写中..." 标签色与水母一致
6. 模拟粘贴失败：警告图标与文字为 systemOrange，在暗色背景上可见
7. 切换回**明亮模式**，重复 3-6，确认所有颜色恢复浅色方案
8. 打开日志查看器（主窗口底部日志卡片 → 打开），确认分屏两侧色彩正常

- [ ] **Step 4: 最终提交（如有手动验证调整）**

```bash
git add -A && git commit -m "chore: 明暗模式手动验证确认"
```

---

### Task 6: 推送并准备合并

- [ ] **Step 1: 推送分支**

```bash
git push -u origin feature/dark-mode-adaptation
```
