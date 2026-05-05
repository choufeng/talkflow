# Token 缓存优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 app 存活期内缓存 Vertex AI access_token，后续调用省去 JWT 签名 + OAuth2 交换开销，降低润色/翻译延迟 ~1s。

**Architecture:** 装饰器模式 — 新建 `CachedTokenProvider`（actor）包装现有 `TokenProviderIO`，内存缓存 token + TTL。AppDelegate 抽取共享实例，润色和翻译复用同一 provider。

**Tech Stack:** Swift 5.10+, async/await, actor, XCTest

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `TalkFlow/IO/CachedTokenProvider.swift`（新增）| actor 装饰器，缓存 access_token |
| `TalkFlowTests/IO/CachedTokenProviderTests.swift`（新增）| 单元测试 |
| `TalkFlow/AppDelegate.swift`（修改）| 抽取共享 CachedTokenProvider |

---

### Task 1: 编写 CachedTokenProvider 失败测试

**Files:**
- Create: `TalkFlowTests/IO/CachedTokenProviderTests.swift`

- [ ] **Step 1: 编写缓存命中测试 + 缓存过期测试 + 错误透传测试**

```swift
import XCTest
@testable import TalkFlow

final class CachedTokenProviderTests: XCTestCase {

    // MARK: - 缓存命中：不调 inner

    func test_getAccessToken_returnsCachedToken_whenCacheValid() async throws {
        let mock = MockTokenProviderIO()
        mock.stubbedToken = "token-1"

        let cached = CachedTokenProvider(inner: mock)

        let first = try await cached.getAccessToken()
        XCTAssertEqual(first, "token-1")
        XCTAssertEqual(mock.getTokenCallCount, 1)

        // 第二次应命中缓存，不调 inner
        let second = try await cached.getAccessToken()
        XCTAssertEqual(second, "token-1")
        XCTAssertEqual(mock.getTokenCallCount, 1)
    }

    // MARK: - 缓存过期：重新调 inner

    func test_getAccessToken_refreshes_whenCacheExpired() async throws {
        let mock = MockTokenProviderIO()
        mock.stubbedToken = "token-1"

        // ttl: 0 = 立即过期
        let cached = CachedTokenProvider(inner: mock, ttl: 0)

        _ = try await cached.getAccessToken()
        XCTAssertEqual(mock.getTokenCallCount, 1)

        mock.stubbedToken = "token-2"
        let second = try await cached.getAccessToken()
        XCTAssertEqual(second, "token-2")
        XCTAssertEqual(mock.getTokenCallCount, 2)
    }

    // MARK: - 错误透传

    func test_getAccessToken_throws_whenInnerThrows() async {
        let mock = MockTokenProviderIO()
        mock.stubbedError = .authenticationFailed("bad sa")

        let cached = CachedTokenProvider(inner: mock)

        do {
            _ = try await cached.getAccessToken()
            XCTFail("Expected authenticationFailed")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .authenticationFailed("bad sa"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 错误不应缓存
        mock.stubbedError = nil
        mock.stubbedToken = "recovered"
        let recovered = try? await cached.getAccessToken()
        XCTAssertEqual(recovered, "recovered")
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing TalkFlowTests/CachedTokenProviderTests
```

Expected: 编译失败（`CachedTokenProvider` 未定义）

- [ ] **Step 3: 提交**

```bash
git add TalkFlowTests/IO/CachedTokenProviderTests.swift
git commit -m "test: add CachedTokenProviderTests"
```

---

### Task 2: 实现 CachedTokenProvider

**Files:**
- Create: `TalkFlow/IO/CachedTokenProvider.swift`

- [ ] **Step 1: 编写最小实现**

```swift
import Foundation

/// 装饰器：为任意 TokenProviderIO 提供内存级 access_token 缓存
/// 使用 actor 保证线程安全
actor CachedTokenProvider: TokenProviderIO {

    private let inner: any TokenProviderIO
    private var cachedToken: String?
    private var expiresAt: Date = .distantPast
    private let ttl: TimeInterval

    /// - Parameters:
    ///   - inner: 被装饰的实际 token 提供者
    ///   - ttl: 缓存有效期，默认 3300 秒（55 分钟，略小于 token 1h 有效期）
    init(inner: any TokenProviderIO, ttl: TimeInterval = 3300) {
        self.inner = inner
        self.ttl = ttl
    }

    func getAccessToken() async throws -> String {
        if let token = cachedToken, Date() < expiresAt {
            return token
        }

        let token = try await inner.getAccessToken()
        cachedToken = token
        expiresAt = Date().addingTimeInterval(ttl)
        return token
    }
}
```

- [ ] **Step 2: 更新 Xcode project 添加新文件**

```bash
# 手动或通过 Xcode 将 CachedTokenProvider.swift 添加到 TalkFlow target
```

- [ ] **Step 3: 运行测试验证通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing TalkFlowTests/CachedTokenProviderTests
```

Expected: 全部 3 个测试 PASS

- [ ] **Step 4: 运行全部现有测试确保无回归**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow
```

Expected: 全部测试 PASS

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/IO/CachedTokenProvider.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: add CachedTokenProvider actor with TTL-based token caching"
```

---

### Task 3: AppDelegate 集成共享 CachedTokenProvider

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 添加共享 provider 属性**

在 `AppDelegate` 的私有属性区域（`private var logViewerWindow` 之后）添加：

```swift
private var cachedTokenProvider: CachedTokenProvider?
```

- [ ] **Step 2: 添加共享 provider 获取方法**

在 `impureMakePolishingProvider` 之前插入：

```swift
private func impureMakeTokenProvider() async -> (any TokenProviderIO)? {
    guard let adc = impureLoadADCFromDefaultPath() else {
        logger.info(tag: "Token", "ADC 未检测到")
        return nil
    }

    let provider: any TokenProviderIO
    switch adc {
    case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
        let sa = ServiceAccount(
            projectID: impureLoadAppConfig().vertexAI.projectID,
            privateKey: privateKey,
            clientEmail: clientEmail,
            tokenURI: tokenURI
        )
        provider = JWTTokenProvider(sa: sa)
    case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
        provider = RefreshTokenProviderIO(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )
    }

    let cached = CachedTokenProvider(inner: provider)
    cachedTokenProvider = cached
    return cached
}
```

- [ ] **Step 3: 重构 impureMakePolishingProvider 使用共享 provider**

将 `impureMakePolishingProvider` 中的 token provider 创建逻辑替换为：

```swift
private func impureMakePolishingProvider() -> VertexAIIO? {
    guard let adc = impureLoadADCFromDefaultPath() else {
        logger.info(tag: "Pipeline", "润色 — ADC 未检测到，跳过")
        return nil
    }

    let config = impureLoadAppConfig()
    let projectID = config.vertexAI.projectID
    let modelName = config.vertexAI.modelName

    guard !projectID.isEmpty, !modelName.isEmpty else {
        logger.info(tag: "Pipeline", "润色 — ProjectID 或 modelName 为空，跳过")
        return nil
    }

    let promptConfig = PromptConfig(
        defaultPrompt: makePolishingSystemPrompt(),
        userSupplement: config.transcription.polishPrompt
    )

    return VertexAIIO(
        tokenProvider: cachedTokenProvider ?? {
            let provider = createInnerTokenProvider(from: adc)
            let cached = CachedTokenProvider(inner: provider)
            cachedTokenProvider = cached
            return cached
        }(),
        projectID: projectID,
        location: "us-central1",
        model: modelName,
        promptConfig: promptConfig,
        thinkingBudget: config.vertexAI.thinkingBudget
    )
}
```

**等待** — 以上闭包写法过于繁琐。更 clean 的方案：

将 `impureMakePolishingProvider` 改为 async，提取共享 provider 获取：

```swift
private func impureMakePolishingProvider() async -> VertexAIIO? {
    guard let adc = impureLoadADCFromDefaultPath() else {
        logger.info(tag: "Pipeline", "润色 — ADC 未检测到，跳过")
        return nil
    }

    let config = impureLoadAppConfig()
    let projectID = config.vertexAI.projectID
    let modelName = config.vertexAI.modelName

    guard !projectID.isEmpty, !modelName.isEmpty else {
        logger.info(tag: "Pipeline", "润色 — ProjectID 或 modelName 为空，跳过")
        return nil
    }

    let tokenProvider: any TokenProviderIO
    if let cached = cachedTokenProvider {
        tokenProvider = cached
    } else {
        let inner = impureCreateTokenProvider(from: adc)
        let cached = CachedTokenProvider(inner: inner)
        cachedTokenProvider = cached
        tokenProvider = cached
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

还需要抽取 `impureCreateTokenProvider(from:)` ：

```swift
private func impureCreateTokenProvider(from adc: ADCCredential) -> any TokenProviderIO {
    switch adc {
    case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
        let sa = ServiceAccount(
            projectID: impureLoadAppConfig().vertexAI.projectID,
            privateKey: privateKey,
            clientEmail: clientEmail,
            tokenURI: tokenURI
        )
        return JWTTokenProvider(sa: sa)
    case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
        return RefreshTokenProviderIO(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )
    }
}
```

Wait — user said thinking is not needed. Let me simplify. The plan should be precise with exact code changes.

Let me write this properly - the plan needs exact edits shown.

Actually, this is getting complex. Let me re-read the key changes:

1. Add `private var cachedTokenProvider: CachedTokenProvider?` property
2. Extract `impureCreateTokenProvider(from:)` helper to deduplicate ADC→TokenProvider logic 
3. Modify both `impureMakePolishingProvider` and `impureMakeTranslationProvider` to use shared cached provider
4. Both methods need to become `async` since they need to access the `actor`? No - they don't, because creating a `CachedTokenProvider` doesn't need await, only `getAccessToken()` does.

Actually wait - `impureMakePolishingProvider()` and `impureMakeTranslationProvider()` are NOT async currently. But they DON'T need to be - they just create the provider. The `getAccessToken()` is called inside `send()` which is already async. So no signature change needed.

The only change: both methods use a shared `cachedTokenProvider` instead of creating their own inner provider each time.

Let me think about how to structure the deduplication cleanly:

```swift
// New helper
private func impureCreateTokenProvider(from adc: ADCCredential) -> any TokenProviderIO {
    switch adc {
    case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
        let sa = ServiceAccount(
            projectID: impureLoadAppConfig().vertexAI.projectID,
            privateKey: privateKey,
            clientEmail: clientEmail,
            tokenURI: tokenURI
        )
        return JWTTokenProvider(sa: sa)
    case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
        return RefreshTokenProviderIO(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )
    }
}
```

Then in both methods:

```swift
let tokenProvider: any TokenProviderIO
if let cached = cachedTokenProvider {
    tokenProvider = cached
} else {
    let inner = impureCreateTokenProvider(from: adc)
    let cached = CachedTokenProvider(inner: inner)
    cachedTokenProvider = cached
    tokenProvider = cached
}
```

The rest of each method stays the same (promptConfig, VertexAIIO init with the shared tokenProvider).

OK, let me write the plan with exact edits now.<｜end▁of▁thinking｜>

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="write">
<｜｜DSML｜｜parameter name="content" string="true"># Token 缓存优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 app 存活期内缓存 Vertex AI access_token，后续调用省去 JWT 签名 + OAuth2 交换开销，降低润色/翻译延迟 ~1s。

**Architecture:** 装饰器模式 — 新建 `CachedTokenProvider`（actor）包装现有 `TokenProviderIO`，内存缓存 token + TTL。AppDelegate 抽取共享实例，润色和翻译复用同一 provider。

**Tech Stack:** Swift 5.10+, async/await, actor, XCTest

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `TalkFlow/IO/CachedTokenProvider.swift`（新增）| actor 装饰器，缓存 access_token |
| `TalkFlowTests/IO/CachedTokenProviderTests.swift`（新增）| 单元测试 |
| `TalkFlow/AppDelegate.swift`（修改）| 抽取共享 CachedTokenProvider |

---

### Task 1: CachedTokenProvider 单元测试

**Files:**
- Create: `TalkFlowTests/IO/CachedTokenProviderTests.swift`

- [ ] **Step 1: 编写测试文件**

```swift
import XCTest
@testable import TalkFlow

final class CachedTokenProviderTests: XCTestCase {

    // MARK: - 缓存命中：不调 inner

    func test_getAccessToken_returnsCachedToken_whenCacheValid() async throws {
        let mock = MockTokenProviderIO()
        mock.stubbedToken = "token-1"

        let cached = CachedTokenProvider(inner: mock)

        let first = try await cached.getAccessToken()
        XCTAssertEqual(first, "token-1")
        XCTAssertEqual(mock.getTokenCallCount, 1)

        let second = try await cached.getAccessToken()
        XCTAssertEqual(second, "token-1")
        XCTAssertEqual(mock.getTokenCallCount, 1)
    }

    // MARK: - 缓存过期：重新调 inner

    func test_getAccessToken_refreshes_whenCacheExpired() async throws {
        let mock = MockTokenProviderIO()
        mock.stubbedToken = "token-1"

        let cached = CachedTokenProvider(inner: mock, ttl: 0)

        _ = try await cached.getAccessToken()
        XCTAssertEqual(mock.getTokenCallCount, 1)

        mock.stubbedToken = "token-2"
        let second = try await cached.getAccessToken()
        XCTAssertEqual(second, "token-2")
        XCTAssertEqual(mock.getTokenCallCount, 2)
    }

    // MARK: - 错误透传

    func test_getAccessToken_throws_whenInnerThrows() async {
        let mock = MockTokenProviderIO()
        mock.stubbedError = .authenticationFailed("bad sa")

        let cached = CachedTokenProvider(inner: mock)

        do {
            _ = try await cached.getAccessToken()
            XCTFail("Expected authenticationFailed")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .authenticationFailed("bad sa"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // 错误不应缓存 — 后续调用仍尝试 inner
        mock.stubbedError = nil
        mock.stubbedToken = "recovered"
        let recovered = try? await cached.getAccessToken()
        XCTAssertEqual(recovered, "recovered")
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing TalkFlowTests/CachedTokenProviderTests
```

Expected: 编译失败 — `Cannot find 'CachedTokenProvider' in scope`

- [ ] **Step 3: 提交**

```bash
git add TalkFlowTests/IO/CachedTokenProviderTests.swift
git commit -m "test: add CachedTokenProviderTests"
```

---

### Task 2: 实现 CachedTokenProvider

**Files:**
- Create: `TalkFlow/IO/CachedTokenProvider.swift`

- [ ] **Step 1: 编写实现**

```swift
import Foundation

/// 装饰器：为任意 TokenProviderIO 提供内存级 access_token 缓存
/// 使用 actor 保证线程安全
actor CachedTokenProvider: TokenProviderIO {

    private let inner: any TokenProviderIO
    private var cachedToken: String?
    private var expiresAt: Date = .distantPast
    private let ttl: TimeInterval

    /// - Parameters:
    ///   - inner: 被装饰的实际 token 提供者
    ///   - ttl: 缓存有效期，默认 3300 秒（55 分钟，略小于 token 1h 有效期）
    init(inner: any TokenProviderIO, ttl: TimeInterval = 3300) {
        self.inner = inner
        self.ttl = ttl
    }

    func getAccessToken() async throws -> String {
        if let token = cachedToken, Date() < expiresAt {
            return token
        }

        let token = try await inner.getAccessToken()
        cachedToken = token
        expiresAt = Date().addingTimeInterval(ttl)
        return token
    }
}
```

- [ ] **Step 2: 将文件加入 Xcode project**

手动操作：将 `CachedTokenProvider.swift` 拖入 Xcode 的 `TalkFlow/IO` group，勾选 `TalkFlow` target。

- [ ] **Step 3: 运行测试验证通过**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -only-testing TalkFlowTests/CachedTokenProviderTests
```

Expected: 3 tests PASS

- [ ] **Step 4: 运行全量回归测试**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow
```

Expected: All tests PASS

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/IO/CachedTokenProvider.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: add CachedTokenProvider actor with TTL-based token caching"
```

---

### Task 3: AppDelegate 集成共享 CachedTokenProvider

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 添加共享 provider 属性**

在 AppDelegate 私有属性区（`private var logViewerWindow` 之后，`private var hotkeyIO` 之前）添加：

```swift
private var cachedTokenProvider: CachedTokenProvider?
```

- [ ] **Step 2: 抽取 ADC → TokenProvider 工厂方法**

在 `impureMakePolishingProvider` 之前插入：

```swift
private func impureCreateTokenProvider(from adc: ADCCredential) -> any TokenProviderIO {
    let config = impureLoadAppConfig()
    switch adc {
    case .serviceAccount(let clientEmail, let privateKey, let tokenURI, _):
        let sa = ServiceAccount(
            projectID: config.vertexAI.projectID,
            privateKey: privateKey,
            clientEmail: clientEmail,
            tokenURI: tokenURI
        )
        return JWTTokenProvider(sa: sa)
    case .authorizedUser(let clientID, let clientSecret, let refreshToken, _):
        return RefreshTokenProviderIO(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )
    }
}
```

- [ ] **Step 3: 重构 impureMakePolishingProvider — 替换 tokenProvider 创建逻辑**

原代码（412-459 行）中，删除内联的 `tokenProvider` switch 块，替换为：

```swift
    private func impureMakePolishingProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            logger.info(tag: "Pipeline", "润色 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            logger.info(tag: "Pipeline", "润色 — ProjectID 或 modelName 为空，跳过")
            return nil
        }

        let tokenProvider: any TokenProviderIO
        if let cached = cachedTokenProvider {
            tokenProvider = cached
        } else {
            let inner = impureCreateTokenProvider(from: adc)
            let cached = CachedTokenProvider(inner: inner)
            cachedTokenProvider = cached
            tokenProvider = cached
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

- [ ] **Step 4: 重构 impureMakeTranslationProvider — 替换 tokenProvider 创建逻辑**

原代码（461-518 行）中，删除内联的 `tokenProvider` switch 块，替换为：

```swift
    private func impureMakeTranslationProvider() -> VertexAIIO? {
        guard let adc = impureLoadADCFromDefaultPath() else {
            logger.info(tag: "Pipeline", "翻译 — ADC 未检测到，跳过")
            return nil
        }

        let config = impureLoadAppConfig()
        let projectID = config.vertexAI.projectID
        let modelName = config.vertexAI.modelName

        guard !projectID.isEmpty, !modelName.isEmpty else {
            logger.info(tag: "Pipeline", "翻译 — ProjectID 或 modelName 为空，跳过")
            return nil
        }

        let tokenProvider: any TokenProviderIO
        if let cached = cachedTokenProvider {
            tokenProvider = cached
        } else {
            let inner = impureCreateTokenProvider(from: adc)
            let cached = CachedTokenProvider(inner: inner)
            cachedTokenProvider = cached
            tokenProvider = cached
        }

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
```

- [ ] **Step 5: 编译验证**

```bash
xcodebuild build -project TalkFlow.xcodeproj -scheme TalkFlow
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: 运行全量测试**

```bash
xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow
```

Expected: All tests PASS

- [ ] **Step 7: 提交**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "refactor: share CachedTokenProvider across polishing and translation providers"
```
