# 提示词一键优化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户在转写/翻译设置的输入框中填写补充提示词后，点击「优化并保存」按钮，LLM 优化内容结构后回填输入框并自动保存。

**Architecture:** 新建 `PromptOptimizerIO` 封装优化 prompt 和 Vertex AI 调用（复用 ProviderIO 协议），修改两个 SettingView 各加一个按钮和加载态。

**Tech Stack:** Swift, AppKit, VertexAIIO (复用)

---

### Task 1: PromptOptimizerIO

**Files:**
- Create: `TalkFlow/IO/PromptOptimizerIO.swift`

- [ ] **Step 1: 写测试**

```swift
// TalkFlowTests/IO/PromptOptimizerIOTests.swift
import XCTest
@testable import TalkFlow

final class PromptOptimizerIOTests: XCTestCase {

    func test_optimize_nonEmptyInput_returnsOptimized() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "1. 保持口语化风格\n2. 不要改变语义")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        let result = try await optimizer.optimize("保持口语化风格不要改变语义")

        XCTAssertEqual(result, "1. 保持口语化风格\n2. 不要改变语义")
        XCTAssertEqual(mockProvider.sendCallCount, 1)
    }

    func test_optimize_emptyInput_returnsEmpty() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        let result = try await optimizer.optimize("")

        XCTAssertEqual(result, "")
        XCTAssertEqual(mockProvider.sendCallCount, 1)
    }

    func test_optimize_whitespaceOnly_returnsEmpty() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        let result = try await optimizer.optimize("   ")

        XCTAssertEqual(result, "")
    }

    func test_optimize_promptContainsRawInput() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "优化后")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        _ = try await optimizer.optimize("我的自定义提示词")

        let req = mockProvider.sendLastRequest
        let content = req?.messages.first?.content ?? ""
        XCTAssertTrue(content.contains("我的自定义提示词"), "应包含用户原始提示词")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptOptimizerIOTests 2>&1 | tail -10
```
Expected: FAIL

- [ ] **Step 3: 实现 PromptOptimizerIO**

```swift
// TalkFlow/IO/PromptOptimizerIO.swift
import Foundation

// MARK: - 提示词优化 IO

final class PromptOptimizerIO {
    private let provider: ProviderIO

    init(provider: ProviderIO) {
        self.provider = provider
    }

    /// 优化用户补充提示词
    /// - Parameter rawPrompt: 用户在输入框中的原始文本
    /// - Returns: 优化后的提示词
    func optimize(_ rawPrompt: String) async throws -> String {
        let prompt = makeOptimizePrompt(rawPrompt: rawPrompt)
        let request = ChatRequest(messages: [ChatMessage(role: .user, content: prompt)])
        let response = try await provider.send(request)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 优化 Prompt

private func makeOptimizePrompt(rawPrompt: String) -> String {
    """
    优化以下用户自定义提示词，使其更清晰、无歧义、不矛盾：

    原则：
    - 结构化：如有多个要求，用编号或分段
    - 删除与"去语气词、修错别字、去口吃重复"矛盾的内容
    - 删除暗示总结、改写、概括的任何表述
    - 如果输入为空或仅有空白，返回空字符串
    - 仅输出优化后的提示词文本，不输出解释或任何其他内容

    用户原始提示词：
    \(rawPrompt)
    """
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PromptOptimizerIOTests 2>&1 | tail -10
```
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/IO/PromptOptimizerIO.swift TalkFlowTests/IO/PromptOptimizerIOTests.swift
git commit -m "feat: 添加 PromptOptimizerIO + 测试"
```

---

### Task 2: TranscriptionSettingsView 添加优化按钮

**Files:**
- Modify: `TalkFlow/Views/TranscriptionSettingsView.swift`

- [ ] **Step 1: 修改 setUp 和 UI**

```swift
// 在 TranscriptionSettingsView 中添加以下内容：

// MARK: - 新增 Subviews

private let optimizeButton = NSButton(title: "✨ 优化并保存", target: nil, action: nil)
private var isOptimizing = false
private var optimizeTask: Task<Void, Never>?

// 在 impureSetupUI() 中添加按钮（scrollView.bottomAnchor 改为连到 optimizeButton）：

// 优化按钮
optimizeButton.bezelStyle = .rounded
optimizeButton.font = NSFont.systemFont(ofSize: 12)
optimizeButton.target = self
optimizeButton.action = #selector(impureOptimizeTapped)
optimizeButton.translatesAutoresizingMaskIntoConstraints = false
optimizeButton.toolTip = "调用 LLM 优化提示词，可能消耗 API 配额"
addSubview(optimizeButton)

// 修改 scrollView 约束：scrollView.bottomAnchor 不再连到 bottomAnchor
NSLayoutConstraint.activate([
    promptLabel.topAnchor.constraint(equalTo: topAnchor),
    promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

    scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
    scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
    scrollView.heightAnchor.constraint(equalToConstant: 80),

    optimizeButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
    optimizeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
    optimizeButton.bottomAnchor.constraint(equalTo: bottomAnchor),
])
```

- [ ] **Step 2: 添加优化逻辑**

```swift
// MARK: - ⚠️ 优化逻辑

@objc private func impureOptimizeTapped() {
    guard !isOptimizing else { return }
    let rawPrompt = textView.string

    guard let adc = impureLoadADCFromDefaultPath() else {
        impureMakeLogger().warning(tag: "TranscriptionSettings", "ADC 未检测到，无法优化")
        NSSound.beep()
        return
    }

    let config = impureLoadAppConfig()
    let projectID = config.vertexAI.projectID
    let modelName = config.vertexAI.modelName
    guard !projectID.isEmpty, !modelName.isEmpty else {
        impureMakeLogger().warning(tag: "TranscriptionSettings", "ProjectID/ModelName 未配置")
        NSSound.beep()
        return
    }

    let tokenProvider: any TokenProviderIO
    switch adc {
    case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
        let sa = ServiceAccount(projectID: projectID, privateKey: privateKey, clientEmail: clientEmail, tokenURI: tokenURI)
        tokenProvider = JWTTokenProvider(sa: sa)
    case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
        tokenProvider = RefreshTokenProviderIO(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
    }

    let provider = VertexAIIO(
        tokenProvider: tokenProvider,
        projectID: projectID,
        location: "us-central1",
        model: modelName,
        promptConfig: PromptConfig(defaultPrompt: "", userSupplement: "")
    )
    let optimizer = PromptOptimizerIO(provider: provider)

    isOptimizing = true
    optimizeButton.title = "⏳ 优化中..."
    optimizeButton.isEnabled = false

    optimizeTask = Task { [weak self] in
        guard let self = self else { return }
        do {
            let optimized = try await optimizer.optimize(rawPrompt)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                if !optimized.isEmpty {
                    self.textView.string = optimized
                }
                self.impureSavePromptConfig()
                self.isOptimizing = false
                self.optimizeButton.title = "✨ 优化并保存"
                self.optimizeButton.isEnabled = true
                impureMakeLogger().info(tag: "TranscriptionSettings", "提示词优化完成")
            }
        } catch {
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isOptimizing = false
                self.optimizeButton.title = "✨ 优化并保存"
                self.optimizeButton.isEnabled = true
                impureMakeLogger().error(tag: "TranscriptionSettings", "优化失败: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild build -scheme TalkFlow -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD" | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/Views/TranscriptionSettingsView.swift
git commit -m "feat: TranscriptionSettingsView 添加优化并保存按钮"
```

---

### Task 3: TranslationSettingsView 添加优化按钮

**Files:**
- Modify: `TalkFlow/Views/TranslationSettingsView.swift`

与 Task 2 相同的模式，修改 `TranslationSettingsView.swift`：

- [ ] **Step 1: 添加按钮属性**

```swift
// 在 TranslationSettingsView 中添加：

private let optimizeButton = NSButton(title: "✨ 优化并保存", target: nil, action: nil)
private var isOptimizing = false
private var optimizeTask: Task<Void, Never>?
```

- [ ] **Step 2: 修改 impureSetupUI() 添加按钮并调整约束**

在 `impureSetupUI()` 末尾的 `NSLayoutConstraint.activate` 之前添加：

```swift
        // 优化按钮
        optimizeButton.bezelStyle = .rounded
        optimizeButton.font = NSFont.systemFont(ofSize: 12)
        optimizeButton.target = self
        optimizeButton.action = #selector(impureOptimizeTapped)
        optimizeButton.translatesAutoresizingMaskIntoConstraints = false
        optimizeButton.toolTip = "调用 LLM 优化提示词，可能消耗 API 配额"
        addSubview(optimizeButton)
```

修改约束数组，将 `scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)` 替换为：

```swift
            scrollView.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 80),

            optimizeButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            optimizeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            optimizeButton.bottomAnchor.constraint(equalTo: bottomAnchor),
```

- [ ] **Step 3: 添加优化方法**

```swift
    // MARK: - ⚠️ 优化逻辑

    @objc private func impureOptimizeTapped() {
        guard !isOptimizing else { return }
        let rawPrompt = textView.string

        guard let adc = impureLoadADCFromDefaultPath() else {
            impureMakeLogger().warning(tag: "TranslationSettings", "ADC 未检测到，无法优化")
            NSSound.beep()
            return
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName
        guard !projectID.isEmpty, !modelName.isEmpty else {
            impureMakeLogger().warning(tag: "TranslationSettings", "ProjectID/ModelName 未配置")
            NSSound.beep()
            return
        }

        let tokenProvider: any TokenProviderIO
        switch adc {
        case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
            let sa = ServiceAccount(projectID: projectID, privateKey: privateKey, clientEmail: clientEmail, tokenURI: tokenURI)
            tokenProvider = JWTTokenProvider(sa: sa)
        case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
            tokenProvider = RefreshTokenProviderIO(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
        }

        let provider = VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: PromptConfig(defaultPrompt: "", userSupplement: "")
        )
        let optimizer = PromptOptimizerIO(provider: provider)

        isOptimizing = true
        optimizeButton.title = "⏳ 优化中..."
        optimizeButton.isEnabled = false

        optimizeTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let optimized = try await optimizer.optimize(rawPrompt)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if !optimized.isEmpty {
                        self.textView.string = optimized
                    }
                    self.impureSaveTranslationPrompt()
                    self.isOptimizing = false
                    self.optimizeButton.title = "✨ 优化并保存"
                    self.optimizeButton.isEnabled = true
                    impureMakeLogger().info(tag: "TranslationSettings", "提示词优化完成")
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isOptimizing = false
                    self.optimizeButton.title = "✨ 优化并保存"
                    self.optimizeButton.isEnabled = true
                    impureMakeLogger().error(tag: "TranslationSettings", "优化失败: \(error.localizedDescription)")
                    NSSound.beep()
                }
            }
        }
    }
```

- [ ] **Step 4: 编译验证**

```bash
xcodebuild build -scheme TalkFlow -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD" | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 全量测试**

```bash
make test
```
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add TalkFlow/Views/TranslationSettingsView.swift
git commit -m "feat: TranslationSettingsView 添加优化并保存按钮"
```
