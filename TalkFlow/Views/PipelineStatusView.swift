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

        // 恢复默认边框（pasteFailed 会覆盖）
        layer?.borderColor = NSColor.separatorColor.cgColor

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
        label.textColor = NSColor(red: 0, green: 0.78, blue: 1.0, alpha: 1.0)
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
        warnIcon.contentTintColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1.0)
        warnIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(warnIcon)
        indicatorView = warnIcon

        let label = NSTextField(labelWithString: "自动粘贴失败，请手动粘贴")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(red: 1.0, green: 0.69, blue: 0.13, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textLabel = label

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
    private(set) var currentPhase: PipelinePhase = .recording
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


