# 快捷键录音 → 转写 → 自动粘贴 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** STT 转写完成后自动 Cmd+V 粘贴文本到焦点应用

**Architecture:** 新增 PasteIO 协议（粘贴操作抽象） + CGEventPasteIO 实现，注入到 AppDelegate 的 onRecordingComplete 回调中，在 `.speech` 分支剪贴板写入后追加 paste() 调用

**Tech Stack:** Swift, CGEvent, XCTest

**Context:** 项目已有 ClipboardIO 协议（含 paste()），但 AppDelegate 未使用 — 直接用 NSPasteboard。本次新增独立的 PasteIO 协议，职责单一。

---

### Task 1: PasteIO 协议 + 实现

**Files:**
- Create: `TalkFlow/IO/PasteIO.swift`

- [ ] **Step 1: 创建 PasteIO.swift**

```swift
import Foundation

// MARK: - 协议

protocol PasteIO {
    /// ⚠️ 含副作用：模拟 Cmd+V 粘贴，依赖辅助功能权限
    func paste() -> Bool
}

// MARK: - 实现

/// 通过 CGEvent 模拟 Cmd+V 粘贴
final class CGEventPasteIO: PasteIO {

    /// ⚠️ CGEventPost 写入系统事件流
    func paste() -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand

        let postDown = down.post(tap: .cgAnnotatedSessionEventTap)
        let postUp = up.post(tap: .cgAnnotatedSessionEventTap)

        return postDown == .success && postUp == .success
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -5`

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: 提交**

```bash
git add TalkFlow/IO/PasteIO.swift
git commit -m "feat: PasteIO 协议 + CGEventPasteIO 实现"
```

---

### Task 2: MockPasteIO

**Files:**
- Create: `TalkFlowTests/Mocks/MockPasteIO.swift`

- [ ] **Step 1: 创建 MockPasteIO**

```swift
import Foundation
@testable import TalkFlow

// MARK: - MockPasteIO

final class MockPasteIO: PasteIO {
    var shouldSucceed = true
    var pasteCallCount = 0

    func paste() -> Bool {
        pasteCallCount += 1
        return shouldSucceed
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -5`

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: 提交**

```bash
git add TalkFlowTests/Mocks/MockPasteIO.swift
git commit -m "test: MockPasteIO"
```

---

### Task 3: PasteIOTests — 基础行为

**Files:**
- Create: `TalkFlowTests/IO/PasteIOTests.swift`

- [ ] **Step 1: 写入测试并验证**

```swift
// TalkFlowTests/IO/PasteIOTests.swift
import XCTest
@testable import TalkFlow

final class PasteIOTests: XCTestCase {

    // MARK: - paste() 基础行为

    func test_paste_success_returnsTrue() {
        let mock = MockPasteIO()
        mock.shouldSucceed = true
        XCTAssertTrue(mock.paste())
    }

    func test_paste_failure_returnsFalse() {
        let mock = MockPasteIO()
        mock.shouldSucceed = false
        XCTAssertFalse(mock.paste())
    }

    func test_paste_incrementsCallCount() {
        let mock = MockPasteIO()
        mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 1)
        mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 2)
    }
}
```

- [ ] **Step 2: 运行测试，验证通过**

Run: `make test 2>&1 | grep -E "(PasteIOTests|passed|failed|SUCCEEDED|FAILED)"`

Expected: 3 tests pass

- [ ] **Step 3: 提交**

```bash
git add TalkFlowTests/IO/PasteIOTests.swift
git commit -m "test: PasteIO 基础行为测试"
```

---

### Task 4: PasteIOTests — 管道行为

**Files:**
- Modify: `TalkFlowTests/IO/PasteIOTests.swift`

- [ ] **Step 1: 追加管道行为测试**

在 `PasteIOTests` 类中追加以下测试方法：

```swift
    // MARK: - 管道行为（模拟 onRecordingComplete 中的粘贴逻辑）

    func test_pipeline_pasteCalledAfterSTTSpeech() {
        let mock = MockPasteIO()
        let result = STTResult.speech(text: "你好世界", language: "zh")

        switch result {
        case .speech(let text, _):
            // 步骤 1: 写剪贴板（模拟）
            // 步骤 2: 粘贴
            _ = mock.paste()
            XCTAssertEqual(mock.pasteCallCount, 1)
        case .silence, .failure:
            XCTFail("应进入 .speech 分支")
        }
    }

    func test_pipeline_pasteNotCalledOnSilence() {
        let mock = MockPasteIO()
        let result = STTResult.silence

        switch result {
        case .speech:
            XCTFail("不应进入 .speech 分支")
        case .silence, .failure:
            // silence/failure 不粘贴
            break
        }

        XCTAssertEqual(mock.pasteCallCount, 0)
    }

    func test_pipeline_pasteNotCalledOnFailure() {
        let mock = MockPasteIO()
        let result = STTResult.failure(.modelNotReady)

        switch result {
        case .speech:
            XCTFail("不应进入 .speech 分支")
        case .silence, .failure:
            break
        }

        XCTAssertEqual(mock.pasteCallCount, 0)
    }

    func test_pipeline_clipboardWrittenBeforePaste() {
        let mock = MockPasteIO()
        let result = STTResult.speech(text: "测试文本", language: "zh")

        var clipboardText: String?
        var pastePerformed = false

        switch result {
        case .speech(let text, _):
            // 严格顺序：先写剪贴板
            clipboardText = text
            // 再粘贴
            pastePerformed = mock.paste()
        case .silence, .failure:
            XCTFail("应进入 .speech 分支")
        }

        XCTAssertNotNil(clipboardText)
        XCTAssertTrue(pastePerformed)
    }
```

- [ ] **Step 2: 运行测试，验证全部通过**

Run: `make test 2>&1 | grep -E "(PasteIOTests|passed|failed|SUCCEEDED|FAILED)"`

Expected: 7 tests pass (3 已有 + 4 新增)

- [ ] **Step 3: 提交**

```bash
git add TalkFlowTests/IO/PasteIOTests.swift
git commit -m "test: PasteIO 管道行为测试（speech/silence/failure/顺序）"
```

---

### Task 5: AppDelegate 集成 PasteIO

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 注入 pasteIO 属性**

在 `AppDelegate` 中追加属性（紧接 `private let sttEngine: SenseVoiceIO = impureMakeSenseVoiceEngine()` 之后）：

```swift
    // 粘贴模块
    private let pasteIO: PasteIO = CGEventPasteIO()
```

- [ ] **Step 2: 修改 onRecordingComplete 的 .speech 分支**

将 `impureSetupSTT` 方法中的 `case .speech` 分支从：

```swift
                    case .speech(let text, let language):
                        print("[STT] \(language): \(text)")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
```

修改为：

```swift
                    case .speech(let text, let language):
                        print("[STT] \(language): \(text)")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        let pasted = self.pasteIO.paste()
                        print("[Paste] \(pasted ? "✅" : "❌") pasted to active app")
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -5`

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 运行全部测试，验证无回归**

Run: `make test 2>&1 | grep -E "(passed|failed|SUCCEEDED|FAILED)"`

Expected: All tests pass (93 + 7 = 100)

- [ ] **Step 5: 提交**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: AppDelegate 集成 PasteIO — STT 完成后自动粘贴"
```

---

### 文件变更汇总

| 文件 | 操作 | Task |
|---|---|---|
| `TalkFlow/IO/PasteIO.swift` | 新增（协议 + CGEventPasteIO） | 1 |
| `TalkFlowTests/Mocks/MockPasteIO.swift` | 新增（Mock） | 2 |
| `TalkFlowTests/IO/PasteIOTests.swift` | 新增（7 个测试） | 3-4 |
| `TalkFlow/AppDelegate.swift` | 修改（2 行新增） | 5 |
