import AppKit

// MARK: - 转写设置内容视图

/// 转写设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI
final class TranscriptionSettingsView: NSView {

    // MARK: - Subviews

    private let useLLMCheckbox = NSButton(checkboxWithTitle: "通过远程大语言模型对文本进行修饰和加工", target: nil, action: nil)

    // MARK: - 构造

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 显式副作用入口

    func setUp() {
        impureSetupUI()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        useLLMCheckbox.state = .off
        useLLMCheckbox.font = NSFont.systemFont(ofSize: 13)
        useLLMCheckbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(useLLMCheckbox)

        NSLayoutConstraint.activate([
            useLLMCheckbox.topAnchor.constraint(equalTo: topAnchor),
            useLLMCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            useLLMCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            useLLMCheckbox.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
