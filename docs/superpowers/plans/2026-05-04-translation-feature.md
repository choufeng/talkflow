# 翻译功能实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增翻译功能 — 翻译快捷键触发录音+STT+润色翻译合并 LLM 调用，结果写入剪贴板粘贴；移除 useLLM 勾选框。

**Architecture:** 扩展 HotkeyIO 协议支持第二套快捷键（翻译），HotkeySettingsView 重构为双行布局，新增 TranslationSettingsView 卡片，AppDelegate 通过 Workflow 枚举区分转写/翻译管线分流。

**Tech Stack:** Swift, AppKit, Carbon HotKey API, Vertex AI Gemini

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `TalkFlow/Utils/PromptConfig.swift` | 修改 | 新增 `makeTranslationSystemPrompt`、`mergeTranslationPrompts` |
| `TalkFlow/Utils/AppConfig.swift` | 修改 | `useLLM` 默认值 → true；新增 `translationLanguage`、`translationPrompt` |
| `TalkFlow/Utils/Hotkey.swift` | 修改 | 新增翻译通知名、`Workflow` 枚举 |
| `TalkFlow/IO/HotkeyIO.swift` | 修改 | 协议+实现：翻译快捷键存储/注册/录制 |
| `TalkFlow/Views/HotkeySettingsView.swift` | 修改 | 重构为双行布局（转写+翻译） |
| `TalkFlow/Views/TranscriptionSettingsView.swift` | 修改 | 移除 checkbox |
| `TalkFlow/Views/TranslationSettingsView.swift` | 新建 | 翻译卡片：语言选择框+翻译补充输入框 |
| `TalkFlow/AppDelegate.swift` | 修改 | 翻译管线分流、卡片布局调整 |
| `TalkFlowTests/Pure/PromptConfigTests.swift` | 修改 | 新增翻译 prompt 测试 |
| `TalkFlowTests/Pure/AppConfigTests.swift` | 新建 | 配置 Codable 往返测试 |

---

### Task 1: PromptConfig 纯函数 — 翻译固定提示词与合并

**Files:**
- Modify: `TalkFlow/Utils/PromptConfig.swift`
- Modify: `TalkFlowTests/Pure/PromptConfigTests.swift`

- [ ] **Step 1: 编写翻译 prompt 测试（先写测试，验证失败）**

在 `TalkFlowTests/Pure/PromptConfigTests.swift` 末尾添加：

```swift
// MARK: - makeTranslationSystemPrompt

func test_makeTranslationSystemPrompt_isNotEmpty() {
    let prompt = makeTranslationSystemPrompt(language: "英文")
    XCTAssertFalse(prompt.isEmpty, "翻译固定提示词不应为空")
}

func test_makeTranslationSystemPrompt_containsLanguage() {
    let prompt = makeTranslationSystemPrompt(language: "英文")
    XCTAssertTrue(prompt.contains("英文"), "应包含目标语言")
}

func test_makeTranslationSystemPrompt_containsTranslationRule() {
    let prompt = makeTranslationSystemPrompt(language: "日文")
    XCTAssertTrue(prompt.contains("翻译"), "应包含翻译指令")
    XCTAssertTrue(prompt.contains("日文"), "应包含指定的目标语言")
}

func test_makeTranslationSystemPrompt_isDeterministic() {
    let a = makeTranslationSystemPrompt(language: "越南语")
    let b = makeTranslationSystemPrompt(language: "越南语")
    XCTAssertEqual(a, b, "纯函数不应有状态依赖")
}

// MARK: - mergeTranslationPrompts

func test_mergeTranslationPrompts_fullMerge() {
    let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "保持口语")
    let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "保持格式")
    let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
    XCTAssertEqual(result, "【润色】\n保持口语\n翻译成英文\n保持格式")
}

func test_mergeTranslationPrompts_noSupplement() {
    let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "")
    let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "")
    let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
    XCTAssertEqual(result, "【润色】\n翻译成英文")
}

func test_mergeTranslationPrompts_polishOnly() {
    let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "")
    let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "保持格式")
    let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
    XCTAssertEqual(result, "【润色】\n翻译成英文\n保持格式")
}

func test_mergeTranslationPrompts_translationOnly() {
    let polishConfig = PromptConfig(defaultPrompt: "【润色】", userSupplement: "保持口语")
    let translationConfig = PromptConfig(defaultPrompt: "翻译成英文", userSupplement: "")
    let result = mergeTranslationPrompts(polishConfig: polishConfig, translationConfig: translationConfig)
    XCTAssertEqual(result, "【润色】\n保持口语\n翻译成英文")
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptConfigTests 2>&1 | tail -20
```

预期：编译失败，`makeTranslationSystemPrompt` 和 `mergeTranslationPrompts` 未定义。

- [ ] **Step 3: 实现 PromptConfig 纯函数**

在 `TalkFlow/Utils/PromptConfig.swift` 末尾添加：

```swift
// MARK: - 翻译固定提示词

/// 翻译固定系统提示词 — 将文本翻译为目标语言
/// 不可通过 UI 编辑，仅可在此处修改
func makeTranslationSystemPrompt(language: String) -> String {
    """
    将用户提供的文本翻译为\(language)。

    要求：
    - 保持原文语义和语气，不添加额外解释
    - 专业术语保持一致，不随意替换
    - 自然流畅，符合目标语言表达习惯
    - 仅输出翻译结果，不输出原文或其他内容
    """
}

// MARK: - 润色+翻译提示词合并

/// 合并润色提示词与翻译提示词，用于翻译流程的一次 LLM 调用
/// 顺序：润色固定 + 润色补充 + 翻译固定 + 翻译补充
func mergeTranslationPrompts(
    polishConfig: PromptConfig,
    translationConfig: PromptConfig
) -> String {
    let polishPart = mergePrompts(polishConfig)
    let translationPart = mergePrompts(translationConfig)
    return "\(polishPart)\n\(translationPart)"
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptConfigTests 2>&1 | tail -20
```

预期：全部测试通过。

- [ ] **Step 5: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/Utils/PromptConfig.swift TalkFlowTests/Pure/PromptConfigTests.swift && git commit -m "feat: 新增翻译固定提示词与润色翻译合并函数"
```

---

### Task 2: AppConfig 扩展 — 翻译字段与 useLLM 默认值

**Files:**
- Modify: `TalkFlow/Utils/AppConfig.swift`
- Create: `TalkFlowTests/Pure/AppConfigTests.swift`

- [ ] **Step 1: 编写 AppConfig 测试**

创建 `TalkFlowTests/Pure/AppConfigTests.swift`：

```swift
import XCTest
@testable import TalkFlow

final class AppConfigTests: XCTestCase {

    func test_defaultConfig_useLLM_isTrue() {
        let config = makeDefaultAppConfig()
        XCTAssertTrue(config.transcription.useLLM, "默认应启用 LLM")
    }

    func test_defaultConfig_translationLanguage_isEnglish() {
        let config = makeDefaultAppConfig()
        XCTAssertEqual(config.transcription.translationLanguage, "英文")
    }

    func test_defaultConfig_translationPrompt_isEmpty() {
        let config = makeDefaultAppConfig()
        XCTAssertEqual(config.transcription.translationPrompt, "")
    }

    func test_codableRoundTrip() throws {
        var config = makeDefaultAppConfig()
        config.transcription.translationLanguage = "日文"
        config.transcription.translationPrompt = "保持敬语"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.transcription.translationLanguage, "日文")
        XCTAssertEqual(decoded.transcription.translationPrompt, "保持敬语")
        XCTAssertTrue(decoded.transcription.useLLM)
    }

    func test_codable_oldConfigWithoutTranslationFields_decodesWithDefaults() throws {
        let oldJSON = """
        {"vertexAI":{"modelName":"gemini","projectID":"p","thinkingBudget":0},"transcription":{"useLLM":true,"polishPrompt":"old"}}
        """
        let data = oldJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.transcription.translationLanguage, "英文", "旧配置应有默认语言")
        XCTAssertEqual(decoded.transcription.translationPrompt, "", "旧配置应有默认提示词")
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/AppConfigTests 2>&1 | tail -20
```

预期：编译失败，`translationLanguage` 和 `translationPrompt` 未定义，或 `useLLM` 默认值不是 `true`。

- [ ] **Step 3: 修改 AppConfig**

编辑 `TalkFlow/Utils/AppConfig.swift`，修改 `TranscriptionConfig`：

```swift
/// 转写配置
struct TranscriptionConfig: Codable, Equatable {
    var useLLM: Bool = true
    /// 用户自定义润色要求，与固定提示词拼接后作为 LLM system prompt
    var polishPrompt: String = ""
    /// 翻译目标语言，默认英文
    var translationLanguage: String = "英文"
    /// 用户自定义翻译补充要求
    var translationPrompt: String = ""
}
```

无需修改 `makeDefaultAppConfig()`，`AppConfig()` 即用默认值。

- [ ] **Step 4: 运行测试验证通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/AppConfigTests 2>&1 | tail -20
```

预期：全部测试通过。

- [ ] **Step 5: 同时运行全部现有测试确保无回归**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

预期：全部测试通过。

- [ ] **Step 6: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/Utils/AppConfig.swift TalkFlowTests/Pure/AppConfigTests.swift TalkFlow.xcodeproj/xcshareddata/xcschemes/TalkFlow.xcscheme 2>/dev/null; git add TalkFlow.xcodeproj/project.pbxproj 2>/dev/null; git commit -m "feat: AppConfig 新增翻译字段，useLLM 默认值改为 true"
```

> 注意：若 `project.pbxproj` 有变更（新增测试文件引用），需一并提交。

---

### Task 3: Hotkey — 翻译通知名与 Workflow 枚举

**Files:**
- Modify: `TalkFlow/Utils/Hotkey.swift`
- Modify: `TalkFlow/IO/HotkeyIO.swift` (通知名定义)

无独立测试文件 — 通知名定义为常量，纯数据类型无需复杂测试。

- [ ] **Step 1: 添加通知名和 Workflow 枚举**

在 `TalkFlow/Utils/Hotkey.swift` 末尾添加：

```swift
// MARK: - 工作流类型

/// 区分转写业务流与翻译业务流
enum Workflow: Equatable {
    case transcription
    case translation
}
```

编辑 `TalkFlow/IO/HotkeyIO.swift` 末尾的 `Notification.Name` 扩展（注意：通知名定义在 HotkeyIO.swift 末尾，不在 Hotkey.swift），在 `talkFlowUseLLMChanged` 旁新增：

```swift
static let talkFlowTranslationHotkeyTriggered = Notification.Name("TalkFlowTranslationHotkeyTriggered")
```

同时移除 `talkFlowUseLLMChanged`（不再需要）：

```swift
extension Notification.Name {
    static let talkFlowHotkeyTriggered = Notification.Name("TalkFlowHotkeyTriggered")
    static let talkFlowTranslationHotkeyTriggered = Notification.Name("TalkFlowTranslationHotkeyTriggered")
}
```

- [ ] **Step 2: 运行全部测试确保编译通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

预期：全部测试通过。

- [ ] **Step 3: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/Utils/Hotkey.swift TalkFlow/IO/HotkeyIO.swift && git commit -m "feat: 新增 Workflow 枚举与翻译快捷键通知名，移除 useLLM 变更通知"
```

---

### Task 4: HotkeyIO — 翻译快捷键协议与 Carbon 实现

**Files:**
- Modify: `TalkFlow/IO/HotkeyIO.swift`

- [ ] **Step 1: 扩展 HotkeyIO 协议**

在 `TalkFlow/IO/HotkeyIO.swift` 中，`protocol HotkeyIO` 内，`unregisterEscHotkey()` 后添加：

```swift
// MARK: - 翻译快捷键

/// ⚠️ 加载翻译快捷键绑定
func loadTranslationBinding() -> HotkeyBinding?

/// ⚠️ 保存翻译快捷键绑定
func saveTranslationBinding(_ binding: HotkeyBinding)

/// ⚠️ 清除翻译快捷键绑定
func clearTranslationBinding()

/// ⚠️ 注册翻译全局快捷键
func registerTranslationHotkey(_ binding: HotkeyBinding) -> Bool

/// ⚠️ 注销翻译全局快捷键
func unregisterTranslationHotkey()

/// ⚠️ 开始录制翻译快捷键
func startTranslationRecording(onCaptured: @escaping (HotkeyBinding) -> Void)

/// ⚠️ 停止录制翻译快捷键
func stopTranslationRecording()
```

- [ ] **Step 2: 实现 CarbonHotkeyIO 翻译快捷键**

在 `CarbonHotkeyIO` 类中：

在 `private let storageKey` 下方添加：

```swift
private let translationStorageKey = "TalkFlow_TranslationHotkeyBinding"
```

在 `private let hotkeyID` 下方添加：

```swift
private var translationHotkeyRef: EventHotKeyRef?
private var translationRecordingMonitor: Any?
private let translationHotkeyID = EventHotKeyID(signature: 0x54464C4F, id: 3) // "TFLO"
```

在 `deinit` 中添加 `unregisterTranslationHotkey()`：

```swift
deinit {
    stopRecording()
    stopTranslationRecording()
    unregisterEscHotkey()
    unregisterTranslationHotkey()
    unregisterHotkey()
}
```

在 `// MARK: - 存储` 区域末尾添加：

```swift
// MARK: - 翻译快捷键存储

func loadTranslationBinding() -> HotkeyBinding? {
    guard let data = UserDefaults.standard.data(forKey: translationStorageKey) else {
        hotkeyLog("未找到已保存的翻译快捷键绑定")
        return nil
    }
    do {
        let binding = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        hotkeyLog("加载已保存的翻译快捷键: \(formatHotkey(binding))")
        return binding
    } catch {
        hotkeyLog("⚠️ 翻译快捷键绑定解码失败: \(error.localizedDescription)")
        return nil
    }
}

func saveTranslationBinding(_ binding: HotkeyBinding) {
    do {
        let data = try JSONEncoder().encode(binding)
        UserDefaults.standard.set(data, forKey: translationStorageKey)
        hotkeyLog("保存翻译快捷键: \(formatHotkey(binding))")
    } catch {
        hotkeyLog("⚠️ 翻译快捷键绑定编码失败: \(error.localizedDescription)")
    }
}

func clearTranslationBinding() {
    UserDefaults.standard.removeObject(forKey: translationStorageKey)
    hotkeyLog("清除已保存的翻译快捷键")
}
```

在 `// MARK: - 全局注册` 区域末尾添加：

```swift
// MARK: - 翻译快捷键注册

func registerTranslationHotkey(_ binding: HotkeyBinding) -> Bool {
    unregisterTranslationHotkey()

    let modifiers = UInt32(binding.modifiers)
    let keyCode = UInt32(binding.keyCode)

    hotkeyLog("正在注册翻译快捷键: \(formatHotkey(binding)) (keyCode=\(keyCode), modifiers=0x\(String(modifiers, radix: 16)))")

    // 安装事件处理器（复用已有的 handlerRef）
    if eventHandlerRef == nil {
        var handlerRef: EventHandlerRef?
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventMonitorTarget(),
            CarbonHotkeyIO.eventHandlerCallback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        if status != noErr {
            hotkeyLog("❌ 安装事件处理器失败 (OSStatus: \(status))")
            return false
        }
        eventHandlerRef = handlerRef
    }

    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
        keyCode,
        modifiers,
        translationHotkeyID,
        GetEventMonitorTarget(),
        0,
        &ref
    )
    if status != noErr {
        hotkeyLog("❌ 翻译快捷键 RegisterEventHotKey 失败 (OSStatus: \(status))")
        return false
    }
    translationHotkeyRef = ref
    hotkeyLog("✅ 翻译快捷键注册成功")
    return true
}

func unregisterTranslationHotkey() {
    if let ref = translationHotkeyRef {
        UnregisterEventHotKey(ref)
        translationHotkeyRef = nil
        hotkeyLog("已注销翻译快捷键")
    }
}

func startTranslationRecording(onCaptured: @escaping (HotkeyBinding) -> Void) {
    stopTranslationRecording()
    hotkeyLog("开始录制翻译快捷键...")

    translationRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }

        let carbonMods = nseventModifiersToCarbon(event.modifierFlags)
        guard carbonMods != 0 else { return event }
        let binding = HotkeyBinding(keyCode: event.keyCode, modifiers: carbonMods)
        hotkeyLog("捕获翻译快捷键: \(formatHotkey(binding))")

        self.stopTranslationRecording()
        onCaptured(binding)
        return nil
    }
}

func stopTranslationRecording() {
    if let monitor = translationRecordingMonitor {
        NSEvent.removeMonitor(monitor)
        translationRecordingMonitor = nil
        hotkeyLog("停止翻译快捷键录制")
    }
}
```

在事件回调 `eventHandlerCallback` 中，`hotkeyID.id == 1` 和 `hotkeyID.id == 2` 后添加第三个分支：

```swift
} else if hotkeyID.id == 3 {
    hotkeyLog("🔥 翻译快捷键触发！")
    NotificationCenter.default.post(name: .talkFlowTranslationHotkeyTriggered, object: nil)
}
```

- [ ] **Step 3: 运行全部测试确保编译通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

预期：全部测试通过。

- [ ] **Step 4: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/IO/HotkeyIO.swift && git commit -m "feat: HotkeyIO 协议扩展翻译快捷键存储/注册/录制"
```

---

### Task 5: HotkeySettingsView — 双快捷键行布局

**Files:**
- Modify: `TalkFlow/Views/HotkeySettingsView.swift`

- [ ] **Step 1: 重写 HotkeySettingsView**

替换 `TalkFlow/Views/HotkeySettingsView.swift` 完整内容：

```swift
import AppKit
import os.log

// MARK: - 日志

private let log = OSLog(subsystem: "im.xiajia.TalkFlow", category: "HotkeyView")

private func uiLog(_ msg: String) {
    os_log("%{public}@", log: log, type: .info, msg)
    print("[TalkFlow.HotkeyUI] \(msg)")
}

// MARK: - 快捷键行内部状态

private struct HotkeyRowState {
    var binding: HotkeyBinding? = nil
    var isRecording = false
}

// MARK: - 快捷键设置内容视图

/// 快捷键设置视图 — 包含转写快捷键与翻译快捷键两行
/// init 仅赋值 HotkeyIO（rule 16），setUp() 显式触发副作用
final class HotkeySettingsView: NSView {

    // MARK: - Dependency

    private let io: HotkeyIO

    // MARK: - 可变状态

    private var transcriptionState = HotkeyRowState()
    private var translationState = HotkeyRowState()

    // MARK: - Subviews（转写行）

    private let transcriptionDesc = NSTextField(labelWithString: "")
    private let transcriptionLabel = NSTextField(labelWithString: "")
    private let transcriptionRecordBtn = NSButton(title: "", target: nil, action: nil)
    private let transcriptionClearBtn = NSButton(title: "", target: nil, action: nil)
    private let transcriptionStatus = NSTextField(labelWithString: "")

    // MARK: - Subviews（翻译行）

    private let translationDesc = NSTextField(labelWithString: "")
    private let translationLabel = NSTextField(labelWithString: "")
    private let translationRecordBtn = NSButton(title: "", target: nil, action: nil)
    private let translationClearBtn = NSButton(title: "", target: nil, action: nil)
    private let translationStatus = NSTextField(labelWithString: "")

    // MARK: - 构造

    init(io: HotkeyIO) {
        self.io = io
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 显式副作用入口

    func setUp() {
        impureSetupUI()
        impureLoadAndRegister()
        impureRenderAll()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // — 转写行 —
        impureSetupHotkeyRow(
            desc: transcriptionDesc,
            label: transcriptionLabel,
            recordBtn: transcriptionRecordBtn,
            clearBtn: transcriptionClearBtn,
            status: transcriptionStatus,
            recordAction: #selector(impureTranscriptionRecordClicked),
            clearAction: #selector(impureTranscriptionClearClicked)
        )

        // — 翻译行 —
        impureSetupHotkeyRow(
            desc: translationDesc,
            label: translationLabel,
            recordBtn: translationRecordBtn,
            clearBtn: translationClearBtn,
            status: translationStatus,
            recordAction: #selector(impureTranslationRecordClicked),
            clearAction: #selector(impureTranslationClearClicked)
        )

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            // 转写行
            transcriptionDesc.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            transcriptionDesc.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptionLabel.topAnchor.constraint(equalTo: transcriptionDesc.bottomAnchor, constant: 10),
            transcriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            transcriptionRecordBtn.leadingAnchor.constraint(equalTo: transcriptionLabel.trailingAnchor, constant: 16),
            transcriptionRecordBtn.centerYAnchor.constraint(equalTo: transcriptionLabel.centerYAnchor),
            transcriptionRecordBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            transcriptionClearBtn.leadingAnchor.constraint(equalTo: transcriptionRecordBtn.trailingAnchor, constant: 8),
            transcriptionClearBtn.centerYAnchor.constraint(equalTo: transcriptionLabel.centerYAnchor),
            transcriptionStatus.topAnchor.constraint(equalTo: transcriptionLabel.bottomAnchor, constant: 6),
            transcriptionStatus.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptionStatus.trailingAnchor.constraint(equalTo: trailingAnchor),

            // 分隔线
            separator.topAnchor.constraint(equalTo: transcriptionStatus.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),

            // 翻译行
            translationDesc.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            translationDesc.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationLabel.topAnchor.constraint(equalTo: translationDesc.bottomAnchor, constant: 10),
            translationLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            translationRecordBtn.leadingAnchor.constraint(equalTo: translationLabel.trailingAnchor, constant: 16),
            translationRecordBtn.centerYAnchor.constraint(equalTo: translationLabel.centerYAnchor),
            translationRecordBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            translationClearBtn.leadingAnchor.constraint(equalTo: translationRecordBtn.trailingAnchor, constant: 8),
            translationClearBtn.centerYAnchor.constraint(equalTo: translationLabel.centerYAnchor),
            translationStatus.topAnchor.constraint(equalTo: translationLabel.bottomAnchor, constant: 6),
            translationStatus.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationStatus.trailingAnchor.constraint(equalTo: trailingAnchor),
            translationStatus.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func impureSetupHotkeyRow(
        desc: NSTextField,
        label: NSTextField,
        recordBtn: NSButton,
        clearBtn: NSButton,
        status: NSTextField,
        recordAction: Selector,
        clearAction: Selector
    ) {
        desc.font = NSFont.systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.translatesAutoresizingMaskIntoConstraints = false
        addSubview(desc)

        label.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        recordBtn.bezelStyle = .rounded
        recordBtn.font = NSFont.systemFont(ofSize: 13)
        recordBtn.target = self
        recordBtn.action = recordAction
        recordBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recordBtn)

        clearBtn.bezelStyle = .rounded
        clearBtn.font = NSFont.systemFont(ofSize: 13)
        clearBtn.controlSize = .small
        clearBtn.target = self
        clearBtn.action = clearAction
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearBtn)

        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .tertiaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)
    }

    // MARK: - ⚠️ 启动时加载 + 注册

    private func impureLoadAndRegister() {
        if let binding = io.loadBinding() {
            transcriptionState.binding = binding
            let ok = io.registerHotkey(binding)
            if ok {
                uiLog("启动时注册转写快捷键成功: \(formatHotkey(binding))")
            } else {
                uiLog("⚠️ 启动时注册转写快捷键失败: \(formatHotkey(binding))")
            }
        } else {
            uiLog("未检测到已保存的转写快捷键")
        }

        if let binding = io.loadTranslationBinding() {
            translationState.binding = binding
            let ok = io.registerTranslationHotkey(binding)
            if ok {
                uiLog("启动时注册翻译快捷键成功: \(formatHotkey(binding))")
            } else {
                uiLog("⚠️ 启动时注册翻译快捷键失败: \(formatHotkey(binding))")
            }
        } else {
            uiLog("未检测到已保存的翻译快捷键")
        }
    }

    // MARK: - ⚠️ 转写快捷键事件

    @objc private func impureTranscriptionRecordClicked() {
        if transcriptionState.isRecording {
            io.stopRecording()
            transcriptionState.isRecording = false
            impureRenderAll()
            return
        }

        transcriptionState.isRecording = true
        impureRenderAll()
        uiLog("等待用户按下转写快捷键...")

        io.startRecording { [weak self] binding in
            guard let self = self else { return }
            self.transcriptionState.isRecording = false
            self.io.saveBinding(binding)
            self.io.unregisterHotkey()
            let ok = self.io.registerHotkey(binding)
            self.transcriptionState.binding = binding

            if ok {
                uiLog("✅ 转写快捷键已更新: \(formatHotkey(binding))")
            } else {
                uiLog("❌ 转写快捷键注册失败: \(formatHotkey(binding))")
            }
            self.impureRenderAll()
        }
    }

    @objc private func impureTranscriptionClearClicked() {
        io.unregisterHotkey()
        io.clearBinding()
        transcriptionState.binding = nil
        uiLog("转写快捷键已清除")
        impureRenderAll()
    }

    // MARK: - ⚠️ 翻译快捷键事件

    @objc private func impureTranslationRecordClicked() {
        if translationState.isRecording {
            io.stopTranslationRecording()
            translationState.isRecording = false
            impureRenderAll()
            return
        }

        translationState.isRecording = true
        impureRenderAll()
        uiLog("等待用户按下翻译快捷键...")

        io.startTranslationRecording { [weak self] binding in
            guard let self = self else { return }
            self.translationState.isRecording = false
            self.io.saveTranslationBinding(binding)
            self.io.unregisterTranslationHotkey()
            let ok = self.io.registerTranslationHotkey(binding)
            self.translationState.binding = binding

            if ok {
                uiLog("✅ 翻译快捷键已更新: \(formatHotkey(binding))")
            } else {
                uiLog("❌ 翻译快捷键注册失败: \(formatHotkey(binding))")
            }
            self.impureRenderAll()
        }
    }

    @objc private func impureTranslationClearClicked() {
        io.unregisterTranslationHotkey()
        io.clearTranslationBinding()
        translationState.binding = nil
        uiLog("翻译快捷键已清除")
        impureRenderAll()
    }

    // MARK: - ⚠️ 渲染

    private func impureRenderAll() {
        transcriptionDesc.stringValue = "转写快捷键"

        let tState = produceHotkeyUIState(
            binding: transcriptionState.binding,
            isRecording: transcriptionState.isRecording
        )
        transcriptionLabel.stringValue = tState.displayText
        transcriptionLabel.textColor = tState.isSet ? .systemGreen : .placeholderTextColor
        transcriptionRecordBtn.title = tState.isRecording ? "停止录制" : "录制快捷键"
        transcriptionRecordBtn.isEnabled = true
        transcriptionClearBtn.title = "清除"
        transcriptionClearBtn.isHidden = !tState.isSet
        transcriptionStatus.stringValue = tState.statusMessage

        translationDesc.stringValue = "翻译快捷键"

        let tlState = produceHotkeyUIState(
            binding: translationState.binding,
            isRecording: translationState.isRecording
        )
        translationLabel.stringValue = tlState.displayText
        translationLabel.textColor = tlState.isSet ? .systemGreen : .placeholderTextColor
        translationRecordBtn.title = tlState.isRecording ? "停止录制" : "录制快捷键"
        translationRecordBtn.isEnabled = true
        translationClearBtn.title = "清除"
        translationClearBtn.isHidden = !tlState.isSet
        translationStatus.stringValue = tlState.statusMessage
    }
}
```

- [ ] **Step 2: 运行全部测试确保编译通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

预期：全部测试通过。

- [ ] **Step 3: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/Views/HotkeySettingsView.swift && git commit -m "feat: 快捷键卡片重构为双行布局（转写+翻译）"
```

---

### Task 6: TranscriptionSettingsView — 移除 useLLM checkbox

**Files:**
- Modify: `TalkFlow/Views/TranscriptionSettingsView.swift`

- [ ] **Step 1: 移除 checkbox，润色输入框始终可见**

替换 `TalkFlow/Views/TranscriptionSettingsView.swift` 完整内容：

```swift
import AppKit

// MARK: - 转写设置内容视图

/// 转写设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranscriptionSettingsView: NSView {

    // MARK: - Subviews

    private let promptLabel = NSTextField(labelWithString: "润色要求:")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

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
        impureLoadPromptState()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // 提示词标签
        promptLabel.font = NSFont.systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptLabel)

        // 多行输入框
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            promptLabel.topAnchor.constraint(equalTo: topAnchor),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 配置加载

    private func impureLoadPromptState() {
        let config = impureLoadAppConfig()
        if !config.transcription.polishPrompt.isEmpty {
            textView.string = config.transcription.polishPrompt
        }
    }

    // MARK: - ⚠️ 事件

    private func impureSavePromptConfig() {
        var config = impureLoadAppConfig()
        config.transcription.polishPrompt = textView.string
        impureSaveAppConfig(config)
    }
}

// MARK: - NSTextViewDelegate

extension TranscriptionSettingsView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        impureSavePromptConfig()
    }
}
```

- [ ] **Step 2: 运行全部测试确保编译通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

预期：全部测试通过。

- [ ] **Step 3: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/Views/TranscriptionSettingsView.swift && git commit -m "feat: 移除转写设置 useLLM checkbox，润色输入框始终可见"
```

---

### Task 7: TranslationSettingsView — 新建翻译卡片

**Files:**
- Create: `TalkFlow/Views/TranslationSettingsView.swift`

- [ ] **Step 1: 创建 TranslationSettingsView**

创建 `TalkFlow/Views/TranslationSettingsView.swift`：

```swift
import AppKit

// MARK: - 翻译设置内容视图

/// 翻译设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranslationSettingsView: NSView {

    // MARK: - Subviews

    private let languageLabel = NSTextField(labelWithString: "目标语言:")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let promptLabel = NSTextField(labelWithString: "翻译要求:")
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    // MARK: - 语言选项

    private let languageOptions = ["英文", "越南语", "西班牙语", "日文", "韩语"]

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
        impureLoadConfig()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // 语言标签
        languageLabel.font = NSFont.systemFont(ofSize: 12)
        languageLabel.textColor = .secondaryLabelColor
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(languageLabel)

        // 语言选择框
        languagePopup.addItems(withTitles: languageOptions)
        languagePopup.font = NSFont.systemFont(ofSize: 13)
        languagePopup.target = self
        languagePopup.action = #selector(impureLanguageChanged)
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(languagePopup)

        // 翻译要求标签
        promptLabel.font = NSFont.systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptLabel)

        // 多行输入框
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            languageLabel.topAnchor.constraint(equalTo: topAnchor),
            languageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            languagePopup.leadingAnchor.constraint(equalTo: languageLabel.trailingAnchor, constant: 8),
            languagePopup.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),

            promptLabel.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 12),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 配置加载

    private func impureLoadConfig() {
        let config = impureLoadAppConfig()
        if let idx = languageOptions.firstIndex(of: config.transcription.translationLanguage) {
            languagePopup.selectItem(at: idx)
        }
        if !config.transcription.translationPrompt.isEmpty {
            textView.string = config.transcription.translationPrompt
        }
    }

    // MARK: - ⚠️ 事件

    @objc private func impureLanguageChanged() {
        var config = impureLoadAppConfig()
        config.transcription.translationLanguage = languagePopup.titleOfSelectedItem ?? "英文"
        impureSaveAppConfig(config)
    }

    private func impureSaveTranslationPrompt() {
        var config = impureLoadAppConfig()
        config.transcription.translationPrompt = textView.string
        impureSaveAppConfig(config)
    }
}

// MARK: - NSTextViewDelegate

extension TranslationSettingsView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        impureSaveTranslationPrompt()
    }
}
```

- [ ] **Step 2: 运行全部测试确保编译通过（注意：需将新文件添加到 Xcode 项目）**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

> 若编译失败，检查 `TranslationSettingsView.swift` 是否已添加到 `TalkFlow.xcodeproj/project.pbxproj`。在 Xcode 中将文件拖入 `TalkFlow/Views` group 即可。

预期：全部测试通过。

- [ ] **Step 3: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/Views/TranslationSettingsView.swift && git commit -m "feat: 新建翻译卡片（语言选择框+翻译补充输入框）"
```

---

### Task 8: AppDelegate — 翻译管线分流与布局调整

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

这是最大的一步，涉及：翻译管线监听、Workflow 分流、翻译 Provider 工厂、卡片布局调整（翻译卡片插入、快捷键卡片标题改为"快捷键"、模型卡片始终可见）。

- [ ] **Step 1: 修改 AppDelegate — 翻译管线**

替换 `TalkFlow/AppDelegate.swift` 完整内容：

```swift
import AppKit

// MARK: - 工作流（纯数据类型，区分转写/翻译）

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var modelCard: CardView?

    // 录音模块
    private var hotkeyIO: HotkeyIO?
    private let audioRecorder: AudioRecorderIO = AVAudioRecorderIO()
    private let filePathIO: FilePathIO = AppSupportFilePathIO()
    private let statusWindow = PipelineStatusWindow()
    private var recordingPhase: RecordingPhase = .idle
    private var lastToggleTime: Date?
    private let debounceInterval: TimeInterval = 0.5
    private let minRecordingDuration: TimeInterval = 1.0

    // STT 模块
    private let sttEngine: SenseVoiceIO = impureMakeSenseVoiceEngine()
    private var sttTask: Task<Void, Never>?
    // 粘贴模块
    private let pasteIO: PasteIO = CGEventPasteIO()

    // 当前工作流（纯数据类型，用于快捷触发热键后分流）
    private var currentWorkflow: Workflow = .transcription

    /// 录音完成回调 — 供后续工作流（语音转写）接入
    var onRecordingComplete: ((URL) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        impureSetupMenuBarIcon()
        impureShowMainWindow()
        impureSetupSTT()

        // 监听转写快捷键触发
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureHandleTranscriptionHotkey),
            name: .talkFlowHotkeyTriggered,
            object: nil
        )
        // 监听翻译快捷键触发
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(impureHandleTranslationHotkey),
            name: .talkFlowTranslationHotkeyTriggered,
            object: nil
        )
    }

    private func impureSetupSTT() {
        onRecordingComplete = { [weak self] url in
            print("[Pipeline] 录音文件: \(url.path)")
            self?.sttTask = Task { [weak self] in
                guard let self else { return }
                print("[Pipeline] 开始 STT 转写...")
                do {
                    let result = try await self.sttEngine.transcribe(url: url)

                    let finalResult: STTResult
                    switch result {
                    case .speech(let text, let language):
                        let config = impureLoadAppConfig()
                        switch self.currentWorkflow {
                        case .transcription:
                            if let provider = self.impureMakePolishingProvider() {
                                print("[Pipeline] 开始 LLM 润色...")
                                do {
                                    let request = ChatRequest(messages: [
                                        ChatMessage(role: .user, content: text)
                                    ])
                                    let response = try await provider.send(request)
                                    print("[Pipeline] 润色完成: \(response.content.prefix(60))...")
                                    finalResult = .speech(text: response.content, language: language)
                                } catch {
                                    print("[Pipeline] 润色失败，降级使用原文: \(error)")
                                    finalResult = result
                                }
                            } else {
                                finalResult = result
                            }

                        case .translation:
                            if let provider = self.impureMakeTranslationProvider() {
                                print("[Pipeline] 开始 LLM 润色+翻译...")
                                do {
                                    let request = ChatRequest(messages: [
                                        ChatMessage(role: .user, content: text)
                                    ])
                                    let response = try await provider.send(request)
                                    print("[Pipeline] 润色+翻译完成: \(response.content.prefix(60))...")
                                    finalResult = .speech(text: response.content, language: language)
                                } catch {
                                    print("[Pipeline] 翻译失败，降级使用原文: \(error)")
                                    finalResult = result
                                }
                            } else {
                                finalResult = result
                            }
                        }
                    default:
                        finalResult = result
                    }

                    await MainActor.run {
                        print("[Pipeline] 管线完成: \(finalResult)")
                        switch finalResult {
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

        // ✕ 按钮回调
        statusWindow.onCancel = { [weak self] in
            guard let self else { return }
            switch self.statusWindow.currentPhase {
            case .recording:
                self.impureCancelRecording()
            case .transcribing:
                self.sttTask?.cancel()
                self.statusWindow.dismiss()
            case .pasteFailed:
                self.statusWindow.dismiss()
            }
        }
    }

    // MARK: - ⚠️ 菜单栏图标

    private func impureSetupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "TalkFlow")
            button.image?.size = NSSize(width: 18, height: 18)
            button.toolTip = "TalkFlow"
            button.action = #selector(impureToggleWindow)
            button.target = self
        }
    }

    @objc private func impureToggleWindow() {
        guard let window = window else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - ⚠️ 主窗口

    private func impureShowMainWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 800, height: 900)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window?.title = "TalkFlow"
        window?.center()

        // 根视图
        let rootView = NSView(frame: windowRect)

        // 权限管理卡片
        let ios: [PermissionIO] = [MicrophonePermissionIO(), AccessibilityPermissionIO()]
        let permissionList = PermissionListView(ios: ios)
        permissionList.setUp()

        let permissionCard = CardView(title: "权限管理", contentView: permissionList)
        permissionCard.setUp()
        rootView.addSubview(permissionCard)

        // 快捷键卡片（包含转写快捷键 + 翻译快捷键）
        let hotkeyIO = CarbonHotkeyIO()
        self.hotkeyIO = hotkeyIO
        let hotkeyView = HotkeySettingsView(io: hotkeyIO)
        hotkeyView.setUp()

        let hotkeyCard = CardView(title: "快捷键", contentView: hotkeyView)
        hotkeyCard.setUp()
        rootView.addSubview(hotkeyCard)

        // 转写设置卡片
        let transcriptionView = TranscriptionSettingsView()
        transcriptionView.setUp()

        let transcriptionCard = CardView(title: "转写", contentView: transcriptionView)
        transcriptionCard.setUp()
        rootView.addSubview(transcriptionCard)

        // 翻译设置卡片
        let translationView = TranslationSettingsView()
        translationView.setUp()

        let translationCard = CardView(title: "翻译", contentView: translationView)
        translationCard.setUp()
        rootView.addSubview(translationCard)

        // 模型配置卡片
        let modelView = ModelSettingsView()
        modelView.setUp()
        let mc = CardView(title: "模型", contentView: modelView)
        mc.setUp()
        self.modelCard = mc
        rootView.addSubview(mc)

        // 模型卡片始终可见
        mc.isHidden = false

        NSLayoutConstraint.activate([
            permissionCard.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            permissionCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            permissionCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            hotkeyCard.topAnchor.constraint(equalTo: permissionCard.bottomAnchor, constant: 16),
            hotkeyCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            hotkeyCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            transcriptionCard.topAnchor.constraint(equalTo: hotkeyCard.bottomAnchor, constant: 16),
            transcriptionCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            transcriptionCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            translationCard.topAnchor.constraint(equalTo: transcriptionCard.bottomAnchor, constant: 16),
            translationCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            translationCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),

            mc.topAnchor.constraint(equalTo: translationCard.bottomAnchor, constant: 16),
            mc.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            mc.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            mc.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -20),
        ])

        window?.contentView = rootView
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - ⚠️ 快捷键处理（分流）

    @objc private func impureHandleTranscriptionHotkey() {
        currentWorkflow = .transcription
        impureHandleHotkeySignal()
    }

    @objc private func impureHandleTranslationHotkey() {
        currentWorkflow = .translation
        impureHandleHotkeySignal()
    }

    private func impureHandleHotkeySignal() {
        let now = Date()

        guard shouldAcceptToggle(lastToggleTime: lastToggleTime, now: now, debounce: debounceInterval) else {
            print("[Pipeline] 防抖忽略（间隔 < \(debounceInterval)s）")
            return
        }
        lastToggleTime = now

        let nextPhase = recordingPhaseFromToggle(recordingPhase, now: now)
        recordingPhase = nextPhase

        print("[Pipeline] 快捷键触发（\(currentWorkflow)）→ 切换到 \(nextPhase)")
        switch nextPhase {
        case .idle:
            impureStopRecording()
        case .recording:
            impureStartRecording()
        }
    }

    // MARK: - ⚠️ 录音协调

    private func impureStartRecording() {
        let url = filePathIO.nextRecordingURL()
        print("[Pipeline] 🎤 开始录音 → \(url.lastPathComponent)")
        do {
            try audioRecorder.startRecording(to: url)
            statusWindow.show(phase: .recording)
            impureUpdateMenuBarIcon(isRecording: true)
            hotkeyIO?.registerEscHotkey { [weak self] in
                self?.impureCancelRecording()
            }
        } catch {
            print("[Pipeline] ❌ 录音启动失败: \(error)")
            recordingPhase = .idle
        }
    }

    private func impureStopRecording() {
        let duration = audioRecorder.stopRecording()
        let savedURL = audioRecorder.recordingURL
        print("[Pipeline] ⏹ 停止录音 时长=\(String(format: "%.1f", duration))s")
        statusWindow.show(phase: .transcribing)
        hotkeyIO?.unregisterEscHotkey()
        impureUpdateMenuBarIcon(isRecording: false)

        if shouldSave(duration: duration, minDuration: minRecordingDuration),
           let url = savedURL {
            onRecordingComplete?(url)
        } else {
            print("[Pipeline] 录音太短(< \(minRecordingDuration)s) — 丢弃")
            statusWindow.dismiss()
            if let url = savedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func impureCancelRecording() {
        audioRecorder.cancelRecording()
        statusWindow.dismiss()
        hotkeyIO?.unregisterEscHotkey()
        impureUpdateMenuBarIcon(isRecording: false)
        recordingPhase = .idle
    }

    // MARK: - ⚠️ 菜单栏图标状态

    private func impureUpdateMenuBarIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        let symbolName = isRecording ? "mic.circle.fill" : "mic.fill"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRecording ? "TalkFlow (录制中)" : "TalkFlow"
        )
        button.image?.size = NSSize(width: 18, height: 18)
    }

    // MARK: - ⚠️ Provider 工厂

    private func impureMakePolishingProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            print("[Pipeline] 润色 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            print("[Pipeline] 润色 — ProjectID 或 modelName 为空，跳过")
            return nil
        }

        let tokenProvider: any TokenProviderIO
        switch adc {
        case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
            let sa = ServiceAccount(
                projectID: projectID,
                privateKey: privateKey,
                clientEmail: clientEmail,
                tokenURI: tokenURI
            )
            tokenProvider = JWTTokenProvider(sa: sa)

        case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
            tokenProvider = RefreshTokenProviderIO(
                clientID: clientID,
                clientSecret: clientSecret,
                refreshToken: refreshToken
            )
        }

        let promptConfig = PromptConfig(
            defaultPrompt: makePolishingSystemPrompt(),
            userSupplement: config.transcription.polishPrompt
        )

        return VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: promptConfig,
            thinkingBudget: config.vertexAI.thinkingBudget
        )
    }

    private func impureMakeTranslationProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            print("[Pipeline] 翻译 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            print("[Pipeline] 翻译 — ProjectID 或 modelName 为空，跳过")
            return nil
        }

        let tokenProvider: any TokenProviderIO
        switch adc {
        case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
            let sa = ServiceAccount(
                projectID: projectID,
                privateKey: privateKey,
                clientEmail: clientEmail,
                tokenURI: tokenURI
            )
            tokenProvider = JWTTokenProvider(sa: sa)

        case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
            tokenProvider = RefreshTokenProviderIO(
                clientID: clientID,
                clientSecret: clientSecret,
                refreshToken: refreshToken
            )
        }

        // 合并润色+翻译系统提示词，作为翻译流程的 system prompt
        let systemPrompt = mergeTranslationPrompts(
            polishConfig: PromptConfig(
                defaultPrompt: makePolishingSystemPrompt(),
                userSupplement: config.transcription.polishPrompt
            ),
            translationConfig: PromptConfig(
                defaultPrompt: makeTranslationSystemPrompt(language: config.transcription.translationLanguage),
                userSupplement: config.transcription.translationPrompt
            )
        )
        let promptConfig = PromptConfig(
            defaultPrompt: systemPrompt,
            userSupplement: ""
        )

        return VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: promptConfig,
            thinkingBudget: config.vertexAI.thinkingBudget
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
```

- [ ] **Step 2: 运行全部测试确保编译通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -10
```

预期：全部测试通过。

- [ ] **Step 3: Commit**

```bash
cd /Users/jia.xia/development/TalkFlow && git add TalkFlow/AppDelegate.swift && git commit -m "feat: 翻译管线分流，快捷键卡片+翻译卡片集成，移除 useLLM 监听"
```

---

### Task 9: 最终验证 — 全量测试

- [ ] **Step 1: 运行全部现有测试**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -15
```

预期：全部测试通过，0 failures。

- [ ] **Step 2: 确认 git 状态**

```bash
cd /Users/jia.xia/development/TalkFlow && git status && git log --oneline -10
```

预期：工作树干净，10 次提交记录。

---

## 完成检查清单

- [ ] `makeTranslationSystemPrompt(language:)` 返回含目标语言的固定提示词
- [ ] `mergeTranslationPrompts` 按润色→翻译顺序拼接，空 supplement 时不产生多余换行
- [ ] `AppConfig.TranscriptionConfig.useLLM` 默认 `true`
- [ ] `AppConfig` Codable 往返正确，旧配置向后兼容
- [ ] 两个通知名独立：`talkFlowHotkeyTriggered` / `talkFlowTranslationHotkeyTriggered`
- [ ] `HotkeyIO` 协议新增翻译快捷键全套方法
- [ ] `CarbonHotkeyIO` 实现翻译快捷键存储/注册/录制，hotkeyID=3
- [ ] 快捷键卡片标题"快捷键"，包含转写行+翻译行
- [ ] 转写设置卡片无 checkbox，润色输入框始终可见
- [ ] 翻译卡片：语言选择框 5 种语言，翻译补充输入框
- [ ] AppDelegate 中 `currentWorkflow` 正确分流转写/翻译管线
- [ ] 翻译 Provider 使用 `mergeTranslationPrompts` 合并 prompt
- [ ] 卡片顺序：权限管理 → 快捷键 → 转写 → 翻译 → 模型
- [ ] 模型卡片始终可见
- [ ] 全部现有测试通过
