# Pipeline 状态浮窗升级 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将录音专用浮动窗升级为覆盖"录音→转写→粘贴失败"三阶段状态指示器，参照 TalkShow 风格。

**Architecture:** 新增 `PipelinePhase` enum 定义三个阶段；`PipelineStatusView` 根据 phase 渲染不同子视图；`PipelineStatusWindow` 管理面板生命周期和计时器。AppDelegate 在各管道节点调用 `show(phase:)` / `dismiss()`。

**Tech Stack:** AppKit (NSView, NSPanel, NSProgressIndicator, CABasicAnimation, SF Symbols)

---

## 文件结构

| 文件 | 操作 | 职责 |
|---|---|---|
| `TalkFlow/Utils/PipelinePhase.swift` | **新建** | 三阶段枚举定义 |
| `TalkFlow/Views/PipelineStatusView.swift` | **新建** | 多阶段视图 + 浮动窗口管理 |
| `TalkFlow/Views/RecordingStatusView.swift` | **删除** | 旧文件，被 PipelineStatusView 替代 |
| `TalkFlow/AppDelegate.swift` | **修改** | 集成新浮窗，增加转写中止 |
| `TalkFlow.xcodeproj/project.pbxproj` | **修改** | 文件引用更新 |

---

### Task 1: PipelinePhase 枚举

**Files:**
- Create: `TalkFlow/Utils/PipelinePhase.swift`

- [ ] **Step 1: 创建 PipelinePhase.swift**

```swift
import Foundation

/// 管道阶段 — 驱动浮窗显示状态
enum PipelinePhase {
    case recording
    case transcribing
    case pasteFailed
}
```

- [ ] **Step 2: 注册到 pbxproj**

用 Python 脚本将 `TalkFlow/Utils/PipelinePhase.swift` 加入 TalkFlow group 和 TalkFlow target Sources build phase。

- [ ] **Step 3: 编译验证并提交**

```bash
make test
git add TalkFlow/Utils/PipelinePhase.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: PipelinePhase 枚举（录音/转写/粘贴失败）"
```

---

### Task 2: PipelineStatusView + PipelineStatusWindow

**Files:**
- Create: `TalkFlow/Views/PipelineStatusView.swift`
- Delete: `TalkFlow/Views/RecordingStatusView.swift`

- [ ] **Step 1: 创建 PipelineStatusView.swift（完整代码）**

```swift
import AppKit

// MARK: - 管道阶段视图

/// 根据 PipelinePhase 渲染不同状态的浮动指示器
/// init 仅赋值（rule 16），setUp() 触发副作用
final class PipelineStatusView: NSView {

    private var phase: PipelinePhase = .recording

    // 子视图（按需创建）
    private var indicatorView: NSView?     // 录制：呼吸圈 | 转写：进度器 | 失败：警告图标
    private var textLabel: NSTextField?
    private var recLabel: NSTextField?     // 仅录制阶段的 "REC"

    // 录制计时器依赖
    var onCancel: (() -> Void)?

    // MARK: - 构造

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setUp() {
        impureSetupUI()
    }

    // MARK: - 公开方法

    func render(phase: PipelinePhase) {
        self.phase = phase
        impureRebuildContent()
    }

    func updateTime(_ duration: TimeInterval) {
        guard phase == .recording else { return }
        textLabel?.stringValue = formatDuration(duration)
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.cornerRadius = 22
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func impureRebuildContent() {
        // 清除旧子视图
        subviews.forEach { $0.removeFromSuperview() }
        indicatorView = nil
        textLabel = nil
        recLabel = nil

        switch phase {
        case .recording:
            impureBuildRecording()
        case .transcribing:
            impureBuildTranscribing()
        case .pasteFailed:
            impureBuildPasteFailed()
        }

        // 关闭按钮（所有阶段共用）
        let closeButton = impureMakeCloseButton()
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 26),
            closeButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    // MARK: - 录制态

    private func impureBuildRecording() {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        indicatorView = dot

        // 呼吸动画
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 1.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        dot.layer?.add(animation, forKey: "pulse")

        let timeField = NSTextField(labelWithString: "00:00")
        timeField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timeField.textColor = .systemRed
        timeField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeField)
        textLabel = timeField

        let rec = NSTextField(labelWithString: "REC")
        rec.font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
        rec.textColor = NSColor.systemRed.withAlphaComponent(0.5)
        rec.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rec)
        recLabel = rec

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            timeField.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            timeField.centerYAnchor.constraint(equalTo: centerYAnchor),

            rec.leadingAnchor.constraint(equalTo: timeField.trailingAnchor, constant: 6),
            rec.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - 转写态

    private func impureBuildTranscribing() {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        indicatorView = spinner

        let label = NSTextField(labelWithString: "转写中...")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 1.0) // 青色
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textLabel = label

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - 粘贴失败态

    private func impureBuildPasteFailed() {
        let warnIcon = NSImageView()
        warnIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                  accessibilityDescription: "warning")
        warnIcon.contentTintColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1.0) // 琥珀色
        warnIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(warnIcon)
        indicatorView = warnIcon

        let label = NSTextField(labelWithString: "自动粘贴失败，请手动粘贴")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textLabel = label

        // 琥珀色边框
        layer?.borderColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 0.3).cgColor

        NSLayoutConstraint.activate([
            warnIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            warnIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            warnIcon.widthAnchor.constraint(equalToConstant: 14),
            warnIcon.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: warnIcon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - 关闭按钮

    private func impureMakeCloseButton() -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.title = ""
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: "xmark",
                             accessibilityDescription: "close")
        btn.imagePosition = .imageOnly
        btn.contentTintColor = .secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.target = self
        btn.action = #selector(impureCloseTapped)
        return btn
    }

    @objc private func impureCloseTapped() {
        onCancel?()
    }
}

// MARK: - 浮动窗口管理

final class PipelineStatusWindow {

    private var window: NSWindow?
    private var statusView: PipelineStatusView?
    private var timer: Timer?
    private var dismissWorkItem: DispatchWorkItem?
    private var currentPhase: PipelinePhase = .recording
    private var recordingStartTime: Date?

    // MARK: - ⚠️ 显示

    func show(phase: PipelinePhase) {
        currentPhase = phase
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        if let statusView {
            // 面板已存在，切换内容
            statusView.render(phase: phase)
            handleTimer(for: phase)
            return
        }

        // 创建新面板
        let view = PipelineStatusView()
        view.setUp()
        view.render(phase: phase)
        view.onCancel = { [weak self] in
            self?.onCancelTapped()
        }
        statusView = view

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = view
        panel.center()

        window = panel
        panel.orderFront(nil)

        handleTimer(for: phase)
    }

    // MARK: - 计时器

    private func handleTimer(for phase: PipelinePhase) {
        timer?.invalidate()
        timer = nil

        if phase == .recording {
            recordingStartTime = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.statusView?.updateTime(elapsed)
            }
        }
    }

    /// 仅 recording 阶段有效
    func updateTime(_ duration: TimeInterval) {
        statusView?.updateTime(duration)
    }

    // MARK: - ⚠️ 消失

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        timer?.invalidate()
        timer = nil
        recordingStartTime = nil

        guard let window else { return }

        // 淡出动画
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        } completionHandler: {
            window.close()
            self.window = nil
            self.statusView = nil
        }
    }

    /// 带延迟消失（pasteFailed 用）
    func dismissAfter(seconds: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem?.cancel()
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    // MARK: - ✕ 按钮回调

    var onCancel: (() -> Void)?

    private func onCancelTapped() {
        onCancel?()
    }
}

// MARK: - 时间格式化

private func formatDuration(_ duration: TimeInterval) -> String {
    let d = max(0, duration)
    let minutes = Int(d) / 60
    let seconds = Int(d) % 60
    return String(format: "%02d:%02d", minutes, seconds)
}
```

- [ ] **Step 2: 删除旧文件 RecordingStatusView.swift**

```bash
rm TalkFlow/Views/RecordingStatusView.swift
```

- [ ] **Step 3: 更新 pbxproj**

用 Python + plistlib：删除 `RecordingStatusView.swift` 的 PBXFileReference 和 PBXBuildFile；创建 `PipelineStatusView.swift` 和 `PipelinePhase.swift` 的 PBXFileReference、PBXBuildFile，加入 TalkFlow group 和 Sources build phase。

- [ ] **Step 4: 编译测试并提交**

```bash
make test
git add TalkFlow/Views/PipelineStatusView.swift TalkFlow/Utils/PipelinePhase.swift TalkFlow.xcodeproj/project.pbxproj
git rm TalkFlow/Views/RecordingStatusView.swift
git commit -m "feat: PipelineStatusView 三阶段浮窗 + PipelineStatusWindow"
```

---

### Task 3: AppDelegate 集成

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 替换 statusWindow 类型声明**

```swift
// 旧：
// private let statusWindow = RecordingStatusWindow()
// 新：
private let statusWindow = PipelineStatusWindow()
```

- [ ] **Step 2: 修改 impureStartRecording**

```swift
private func impureStartRecording() {
    let url = filePathIO.nextRecordingURL()
    print("[Pipeline] 🎤 开始录音 → \(url.lastPathComponent)")
    do {
        try audioRecorder.startRecording(to: url)
        statusWindow.show(phase: .recording)   // ← 改为 show(phase:)
        impureUpdateMenuBarIcon(isRecording: true)
        hotkeyIO?.registerEscHotkey { [weak self] in
            self?.impureCancelRecording()
        }
    } catch {
        print("[Pipeline] ❌ 录音启动失败: \(error)")
        recordingPhase = .idle
    }
}
```

- [ ] **Step 3: 修改 impureStopRecording**

```swift
private func impureStopRecording() {
    let duration = audioRecorder.stopRecording()
    let savedURL = audioRecorder.recordingURL
    print("[Pipeline] ⏹ 停止录音 时长=\(String(format: "%.1f", duration))s")
    statusWindow.show(phase: .transcribing)   // ← 转写中
    hotkeyIO?.unregisterEscHotkey()
    impureUpdateMenuBarIcon(isRecording: false)

    if shouldSave(duration: duration, minDuration: minRecordingDuration),
       let url = savedURL {
        onRecordingComplete?(url)
    } else {
        print("[Pipeline] 录音太短(< \(minRecordingDuration)s) — 丢弃")
        statusWindow.dismiss()                // ← 短录音直接消失
        if let url = savedURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: 修改 impureCancelRecording**

```swift
private func impureCancelRecording() {
    audioRecorder.cancelRecording()
    statusWindow.dismiss()   // ← 使用 dismiss()
    hotkeyIO?.unregisterEscHotkey()
    impureUpdateMenuBarIcon(isRecording: false)
    recordingPhase = .idle
}
```

- [ ] **Step 5: 修改 impureSetupSTT — 粘贴集成点**

```swift
private func impureSetupSTT() {
    onRecordingComplete = { [weak self] url in
        print("[Pipeline] 录音文件: \(url.path)")
        Task { [weak self] in
            guard let self else { return }
            print("[Pipeline] 开始 STT 转写...")
            do {
                let result = try await self.sttEngine.transcribe(url: url)
                await MainActor.run {
                    print("[Pipeline] STT 转写完成: \(result)")
                    switch result {
                    case .speech(let text, let language):
                        print("[Pipeline] 识别文本 (\(language)): \(text)")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        print("[Pipeline] 已写入剪贴板")
                        let pasted = self.pasteIO.paste()
                        if pasted {
                            print("[Pipeline] Cmd+V 粘贴✅ 成功")
                            self.statusWindow.dismiss()
                        } else {
                            print("[Pipeline] Cmd+V 粘贴❌ 失败")
                            self.statusWindow.show(phase: .pasteFailed)
                            self.statusWindow.dismissAfter(seconds: 3)
                        }
                    case .silence:
                        print("[Pipeline] 静音 — 跳过粘贴")
                        self.statusWindow.dismiss()
                    case .failure(let error):
                        print("[Pipeline] STT 失败: \(error)")
                        self.statusWindow.show(phase: .pasteFailed)
                        self.statusWindow.dismissAfter(seconds: 3)
                    }
                }
            } catch {
                print("[Pipeline] STT 异常: \(error)")
                await MainActor.run {
                    self.statusWindow.dismiss()
                }
            }
        }
    }
}
```

- [ ] **Step 6: 添加转写中止支持**

在 AppDelegate 中添加 sttTask 属性和停止逻辑：

```swift
// 在 AppDelegate 中添加属性
private var sttTask: Task<Void, Never>?

// 修改 impureSetupSTT 中的 Task 赋值
private func impureSetupSTT() {
    onRecordingComplete = { [weak self] url in
        print("[Pipeline] 录音文件: \(url.path)")
        self?.sttTask = Task { [weak self] in   // ← 保存 task
            // ... 同上
        }
    }
}
```

并在 `applicationDidFinishLaunching` 中设置 cancel 回调：

```swift
statusWindow.onCancel = { [weak self] in
    guard let self else { return }
    switch self.statusWindow.currentPhase {   // 需要暴露 currentPhase
    case .recording:
        self.impureCancelRecording()
    case .transcribing:
        self.sttTask?.cancel()
        self.statusWindow.dismiss()
    case .pasteFailed:
        self.statusWindow.dismiss()
    }
}
```

> **注：** 需要让 `PipelineStatusWindow.currentPhase` 可读（改为 `private(set) var`）。

- [ ] **Step 7: 编译测试并提交**

```bash
make test
git add TalkFlow/AppDelegate.swift TalkFlow/Views/PipelineStatusView.swift
git commit -m "feat: AppDelegate 集成三段式浮窗 + 转写中止"
```

---

### Task 4: 端到端验证

- [ ] **Step 1: Xcode ⌘R 运行**
- [ ] **Step 2: 验证录制态** — 快捷键触发，浮窗显示红点呼吸 + 计时器 + REC
- [ ] **Step 3: 验证转写态** — 停止录音，浮窗切换为青色 spinner + "转写中..."
- [ ] **Step 4: 验证粘贴成功** — 浮窗自动消失
- [ ] **Step 5: 验证粘贴失败** — 浮窗显示 ⚠️ + "自动粘贴失败，请手动粘贴"，3秒后消失
- [ ] **Step 6: 验证 ✕ 按钮** — 各阶段点击关闭按钮行为正确
- [ ] **Step 7: 验证静音** — 不说话录制，浮窗直接消失
