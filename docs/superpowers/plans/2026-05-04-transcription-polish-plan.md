# 转写润色功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** STT 转写完成后，根据配置调用 LLM 润色文本，再写入剪贴板粘贴

**Architecture:** 在现有管线中插入润色步骤——AppConfig 扩展 polishPrompt 字段，PromptConfig.swift 新增硬编码固定提示词纯函数，AppDelegate 中 .speech 分支增加 LLM 调用与降级逻辑，TranscriptionSettingsView 增加多行输入框

**Tech Stack:** Swift, AppKit (NSScrollView + NSTextView), Vertex AI Gemini API

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `TalkFlow/Utils/AppConfig.swift` | 修改 | 新增 `polishPrompt` 字段 |
| `TalkFlow/Utils/PromptConfig.swift` | 修改 | 新增 `makePolishingSystemPrompt()` 纯函数 |
| `TalkFlow/AppDelegate.swift` | 修改 | 管线中插入润色步骤 + Provider 工厂方法 |
| `TalkFlow/Views/TranscriptionSettingsView.swift` | 修改 | 新增多行输入框 |
| `TalkFlowTests/Pure/PromptConfigTests.swift` | 修改 | 新增固定提示词测试 |

---

### Task 1: Config 扩展 — polishPrompt 字段

**Files:**
- Modify: `TalkFlow/Utils/AppConfig.swift`

- [ ] **Step 1: 在 TranscriptionConfig 中新增 polishPrompt**

```swift
/// 转写配置
struct TranscriptionConfig: Codable, Equatable {
    var useLLM: Bool = false
    /// 用户自定义润色要求，与固定提示词拼接后作为 LLM system prompt
    var polishPrompt: String = ""
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -scheme TalkFlow -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/Utils/AppConfig.swift
git commit -m "feat: AppConfig.TranscriptionConfig 新增 polishPrompt 字段"
```

---

### Task 2: 固定提示词纯函数 + 测试

**Files:**
- Modify: `TalkFlow/Utils/PromptConfig.swift`
- Modify: `TalkFlowTests/Pure/PromptConfigTests.swift`

- [ ] **Step 1: 编写测试（先写，验证失败）**

在 `TalkFlowTests/Pure/PromptConfigTests.swift` 末尾新增：

```swift
    // MARK: - makePolishingSystemPrompt

    func test_makePolishingSystemPrompt_isNotEmpty() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertFalse(prompt.isEmpty, "固定提示词不应为空")
    }

    func test_makePolishingSystemPrompt_containsRemovalRule() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertTrue(prompt.contains("去除"), "应包含去除语气词规则")
        XCTAssertTrue(prompt.contains("\"嗯\""), "应包含具体示例")
    }

    func test_makePolishingSystemPrompt_containsTypoRule() {
        let prompt = makePolishingSystemPrompt()
        XCTAssertTrue(prompt.contains("错别字"), "应包含错别字修正规则")
        XCTAssertTrue(prompt.contains("\"的/地/得\""), "应包含同音错误示例")
    }

    func test_makePolishingSystemPrompt_isDeterministic() {
        let a = makePolishingSystemPrompt()
        let b = makePolishingSystemPrompt()
        XCTAssertEqual(a, b, "纯函数不应有状态依赖")
    }

    func test_mergePrompts_withFixedPromptAndUserSupplement() {
        let result = mergePrompts(PromptConfig(
            defaultPrompt: makePolishingSystemPrompt(),
            userSupplement: "保持口语化风格"
        ))
        XCTAssertTrue(result.contains("去除"), "应含固定提示词")
        XCTAssertTrue(result.contains("保持口语化风格"), "应含用户补充")
        XCTAssertTrue(result.contains("\n"), "应以换行拼接")
    }

    func test_mergePrompts_withFixedPromptOnly_emptySupplement() {
        let result = mergePrompts(PromptConfig(
            defaultPrompt: makePolishingSystemPrompt(),
            userSupplement: ""
        ))
        XCTAssertEqual(result, makePolishingSystemPrompt())
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptConfigTests 2>&1 | grep -E '(error:|test_.*passed|test_.*failed|TEST SUCCEEDED|TEST FAILED)'`
Expected: 编译错误 `Cannot find 'makePolishingSystemPrompt' in scope` 或测试失败

- [ ] **Step 3: 实现 makePolishingSystemPrompt**

在 `TalkFlow/Utils/PromptConfig.swift` 末尾（`mergePrompts` 之后）新增：

```swift
// MARK: - 转写润色固定提示词

/// 转写润色固定系统提示词 — 通用 ASR 后处理规则
/// 不可通过 UI 编辑，仅可在此处修改
func makePolishingSystemPrompt() -> String {
    """
    去除中文口语中常见的无意义语气词和填充词，包括但不限于：
    "嗯"、"啊"、"额"、"呃"、"那个"、"就是"、"然后"、"对吧"、"的话"、"怎么说呢"。
    注意保留有实际语义的词语，例如"然后"在表示时间顺序时应保留。不要改变原文的语义和语气。

    识别并修正文本中的错别字、同音错误和常见输入法导致的文字错误。
    只修正明确的错误，不要对有歧义的内容做主观改动。
    常见的同音错误示例："的/地/得"、"做/作"、"在/再"、"已/以"、"即/既"。
    """
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptConfigTests 2>&1 | grep -E '(test_.*passed|test_.*failed|TEST SUCCEEDED)'`
Expected: 所有新增测试 passed, `TEST SUCCEEDED`

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/Utils/PromptConfig.swift TalkFlowTests/Pure/PromptConfigTests.swift
git commit -m "feat: 转写润色固定提示词 makePolishingSystemPrompt + 测试"
```

---

### Task 3: 管线润色步骤

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 新增 impureMakePolishingProvider 工厂方法**

在 AppDelegate 末尾（`applicationShouldTerminateAfterLastWindowClosed` 之后）新增：

```swift
    // MARK: - ⚠️ 润色 Provider 工厂

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
```

- [ ] **Step 2: 修改 .speech 分支插入润色步骤**

找到 `impureSetupSTT` 中的 `.speech` 分支（约第 41-57 行），替换为：

```swift
                        case .speech(let text, let language):
                            print("[Pipeline] 识别文本 (\(language)): \(text)")

                            // 润色步骤
                            let finalText: String
                            let config = impureLoadAppConfig()
                            if config.transcription.useLLM,
                               let provider = self.impureMakePolishingProvider() {
                                print("[Pipeline] 开始 LLM 润色...")
                                do {
                                    let request = ChatRequest(messages: [
                                        ChatMessage(role: .user, content: text)
                                    ])
                                    let response = try await provider.send(request)
                                    finalText = response.content
                                    print("[Pipeline] 润色完成: \(finalText.prefix(60))...")
                                } catch {
                                    print("[Pipeline] 润色失败，降级使用原文: \(error)")
                                    finalText = text
                                }
                            } else {
                                finalText = text
                            }

                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(finalText, forType: .string)
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
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -scheme TalkFlow -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: 运行全部测试确认无回归**

Run: `make test 2>&1 | grep -E '(Executed.*tests|TEST SUCCEEDED|TEST FAILED)'`
Expected: 全部测试通过（原 108 个 + 新增 6 个 = 114 个）

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: 管线润色步骤 — STT 后调用 LLM 润色，失败降级用原文"
```

---

### Task 4: 转写设置 UI — 多行提示词输入框

**Files:**
- Modify: `TalkFlow/Views/TranscriptionSettingsView.swift`

- [ ] **Step 1: 新增 NSTextView 多行输入框**

完整替换 `TranscriptionSettingsView.swift`：

```swift
import AppKit

// MARK: - 转写设置内容视图

/// 转写设置视图 — 作为卡片内容使用
/// init 仅赋值（rule 16），setUp() 显式构建 UI + 加载配置
final class TranscriptionSettingsView: NSView {

    // MARK: - Subviews

    private let useLLMCheckbox = NSButton(checkboxWithTitle: "通过远程大语言模型对文本进行修饰和加工", target: nil, action: nil)
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
        impureLoadCheckboxState()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        useLLMCheckbox.font = NSFont.systemFont(ofSize: 13)
        useLLMCheckbox.target = self
        useLLMCheckbox.action = #selector(impureCheckboxToggled)
        useLLMCheckbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(useLLMCheckbox)

        // 提示词标签
        promptLabel.font = NSFont.systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.isHidden = true
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
        scrollView.isHidden = true
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            useLLMCheckbox.topAnchor.constraint(equalTo: topAnchor),
            useLLMCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            useLLMCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            promptLabel.topAnchor.constraint(equalTo: useLLMCheckbox.bottomAnchor, constant: 12),
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - ⚠️ 配置加载

    private func impureLoadCheckboxState() {
        let config = impureLoadAppConfig()
        useLLMCheckbox.state = config.transcription.useLLM ? .on : .off
        impureUpdatePromptVisibility()

        if !config.transcription.polishPrompt.isEmpty {
            textView.string = config.transcription.polishPrompt
        }
    }

    private func impureUpdatePromptVisibility() {
        let isOn = useLLMCheckbox.state == .on
        promptLabel.isHidden = !isOn
        scrollView.isHidden = !isOn
    }

    // MARK: - ⚠️ 事件

    @objc private func impureCheckboxToggled() {
        let isOn = useLLMCheckbox.state == .on
        var config = impureLoadAppConfig()
        config.transcription.useLLM = isOn
        impureSaveAppConfig(config)
        impureUpdatePromptVisibility()
        NotificationCenter.default.post(name: .talkFlowUseLLMChanged, object: isOn)
    }

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

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -scheme TalkFlow -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD SUCCEEDED|BUILD FAILED)'`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 运行全部测试**

Run: `make test 2>&1 | grep -E '(Executed.*tests|TEST SUCCEEDED|TEST FAILED)'`
Expected: 114 tests, 0 failures

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/Views/TranscriptionSettingsView.swift
git commit -m "feat: 转写设置卡片新增润色要求多行输入框"
```

---

### Task 5: 全文集成验证

- [ ] **Step 1: 运行全部测试**

Run: `make test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`, 114 tests, 0 failures

- [ ] **Step 2: 确认 git log**

```bash
git log --oneline -5
```

期望输出类似：
```
<hash> feat: 转写设置卡片新增润色要求多行输入框
<hash> feat: 管线润色步骤 — STT 后调用 LLM 润色，失败降级用原文
<hash> feat: 转写润色固定提示词 makePolishingSystemPrompt + 测试
<hash> feat: AppConfig.TranscriptionConfig 新增 polishPrompt 字段
<hash> docs: 转写润色功能设计文档
```

- [ ] **Step 3: 功能完整性检查清单**

| 检查项 | 验证方式 |
|--------|----------|
| `polishPrompt` 持久化 | 设置中输入文本 → 重启 App → 文本仍在 |
| useLLM 关闭时隐藏输入框 | checkbox 取消勾选 → 输入框消失 |
| 固定提示词不可在 UI 显示/编辑 | 代码审查 — `makePolishingSystemPrompt` 无 UI 引用 |
| LLM 润色失败降级 | 关闭网络 → STT → 原始文本仍写入剪贴板 |
| 配置向后兼容 | 删除 config.json → App 正常运行 |
