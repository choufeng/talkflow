import AppKit

/// 录音中浮动状态窗 — 显示录制时长
/// init 仅赋值（rule 16），setUp() 显式触发副作用
final class RecordingStatusView: NSView {

    // MARK: - Subviews

    private let indicatorLabel = NSTextField(labelWithString: "🔴")
    private let timeLabel = NSTextField(labelWithString: "00:00")

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

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        indicatorLabel.font = NSFont.systemFont(ofSize: 14)
        indicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicatorLabel)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        let hintLabel = NSTextField(labelWithString: "ESC 取消")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            indicatorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            indicatorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            timeLabel.leadingAnchor.constraint(equalTo: indicatorLabel.trailingAnchor, constant: 6),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // MARK: - 公开更新方法

    /// 更新显示的录音时长
    func updateDuration(_ duration: TimeInterval) {
        timeLabel.stringValue = formatDuration(duration)
    }
}

// MARK: - 浮动窗口

/// 管理录音状态浮动窗口的生命周期
final class RecordingStatusWindow {

    private var window: NSWindow?
    private var statusView: RecordingStatusView?
    private var timer: Timer?

    // MARK: - ⚠️ 显示

    func show() {
        dismiss()

        let view = RecordingStatusView()
        view.setUp()
        statusView = view

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
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

        // 定时更新时长
        let startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak view] _ in
            let elapsed = Date().timeIntervalSince(startTime)
            view?.updateDuration(elapsed)
        }
    }

    // MARK: - ⚠️ 消失

    func dismiss() {
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
        statusView = nil
    }
}
