# ClipboardIO 模块实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建 ClipboardIO 协议抽象层，支持写入系统剪贴板 + ⌘V 模拟粘贴 + 读取剪贴板内容。

**Architecture:** 单协议 `ClipboardIO` 封装 write/paste/read，`NSPasteboardClipboardIO` 为真实现，`MockClipboardIO` 为测试替身。遵循项目现有 IO 协议模式。

**Tech Stack:** Swift 5, AppKit (`NSPasteboard`), CoreGraphics (`CGEvent`)

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `TalkFlow/IO/ClipboardIO.swift` | 协议 + NSPasteboardClipboardIO 实现 |
| `TalkFlowTests/Mocks/MockClipboardIO.swift` | 测试用 Mock |
| `TalkFlowTests/IO/ClipboardIOTests.swift` | 协议行为测试 |
| `TalkFlow.xcodeproj/project.pbxproj` | 添加 3 个新文件的引用 |

---

### Task 1: 创建协议 + 实现骨架

**Files:**
- Create: `TalkFlow/IO/ClipboardIO.swift`
- Modify: `TalkFlow.xcodeproj/project.pbxproj`

- [ ] **Step 1: 创建 ClipboardIO.swift**

写入以下内容到 `TalkFlow/IO/ClipboardIO.swift`：

```swift
import AppKit

// MARK: - 协议

protocol ClipboardIO {
    /// ⚠️ 含副作用：写入系统剪贴板
    func write(_ text: String)

    /// ⚠️ 含副作用：发送 ⌘V 粘贴
    func paste()

    /// ⚠️ 非引用透明：读取剪贴板当前内容
    func read() -> String?
}

// MARK: - 实现

struct NSPasteboardClipboardIO: ClipboardIO {

    func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func paste() {
        let src = CGEventSource(stateID: .private)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
```

- [ ] **Step 2: 将 ClipboardIO.swift 添加到 Xcode 项目**

在 `project.pbxproj` 中添加：

**2a.** 在 `PBXBuildFile` section（第 14-15 行附近）添加：

```
		C1B2C3D4E5F6A1B2C3D4E701 /* ClipboardIO.swift in Sources */ = {isa = PBXBuildFile; fileRef = C1B2C3D4E5F6A1B2C3D4E702 /* ClipboardIO.swift */; };
```

**2b.** 在 `PBXFileReference` section（第 47-48 行附近）添加：

```
		C1B2C3D4E5F6A1B2C3D4E702 /* ClipboardIO.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ClipboardIO.swift; sourceTree = "<group>"; };
```

**2c.** 在 `IO` group（第 86-93 行）的 children 中添加：

```
				C1B2C3D4E5F6A1B2C3D4E702 /* ClipboardIO.swift */,
```

**2d.** 在 `A1B2C3D4E5F6A1B2C3D4E601 /* Sources */` build phase files 列表中添加：

```
				C1B2C3D4E5F6A1B2C3D4E701 /* ClipboardIO.swift in Sources */,
```

- [ ] **Step 3: 验证编译通过**

```bash
cd TalkFlow && xcodebuild -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 提交**

```bash
git add TalkFlow/IO/ClipboardIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ClipboardIO 协议 + NSPasteboardClipboardIO 实现"
```

---

### Task 2: 创建 Mock

**Files:**
- Create: `TalkFlowTests/Mocks/MockClipboardIO.swift`
- Modify: `TalkFlow.xcodeproj/project.pbxproj`

- [ ] **Step 1: 创建 MockClipboardIO.swift**

写入以下内容到 `TalkFlowTests/Mocks/MockClipboardIO.swift`：

```swift
// TalkFlowTests/Mocks/MockClipboardIO.swift
import Foundation
@testable import TalkFlow

final class MockClipboardIO: ClipboardIO {
    var writtenTexts: [String] = []
    var pasteCallCount = 0
    var readCallCount = 0
    var stubbedReadResult: String?

    func write(_ text: String) {
        writtenTexts.append(text)
    }

    func paste() {
        pasteCallCount += 1
    }

    func read() -> String? {
        readCallCount += 1
        return stubbedReadResult
    }
}
```

- [ ] **Step 2: 将 MockClipboardIO.swift 添加到 Xcode 项目**

在 `project.pbxproj` 中添加：

**2a.** 在 `PBXBuildFile` section 添加：

```
		C1B2C3D4E5F6A1B2C3D4E703 /* MockClipboardIO.swift in Sources */ = {isa = PBXBuildFile; fileRef = C1B2C3D4E5F6A1B2C3D4E704 /* MockClipboardIO.swift */; };
```

**2b.** 在 `PBXFileReference` section 添加：

```
		C1B2C3D4E5F6A1B2C3D4E704 /* MockClipboardIO.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MockClipboardIO.swift; sourceTree = "<group>"; };
```

**2c.** 在 `Mocks` group（第 147-153 行）的 children 中添加：

```
				C1B2C3D4E5F6A1B2C3D4E704 /* MockClipboardIO.swift */,
```

**2d.** 在 `2047A542841C4FD6A08BBEE4 /* Sources */` build phase files 列表中添加：

```
				C1B2C3D4E5F6A1B2C3D4E703 /* MockClipboardIO.swift in Sources */,
```

- [ ] **Step 3: 验证编译通过**

```bash
xcodebuild -scheme TalkFlow -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 提交**

```bash
git add TalkFlowTests/Mocks/MockClipboardIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: MockClipboardIO"
```

---

### Task 3: 编写测试（TDD — 先写失败测试）

**Files:**
- Create: `TalkFlowTests/IO/ClipboardIOTests.swift`
- Modify: `TalkFlow.xcodeproj/project.pbxproj`

- [ ] **Step 1: 创建 ClipboardIOTests.swift**

写入以下内容到 `TalkFlowTests/IO/ClipboardIOTests.swift`：

```swift
// TalkFlowTests/IO/ClipboardIOTests.swift
import XCTest
@testable import TalkFlow

final class ClipboardIOTests: XCTestCase {

    // MARK: - write()

    func test_write_shouldAppendTextToWrittenTexts() {
        let mock = MockClipboardIO()
        mock.write("hello")
        XCTAssertEqual(mock.writtenTexts, ["hello"])
    }

    func test_writeMultipleTimes_shouldAccumulateInOrder() {
        let mock = MockClipboardIO()
        mock.write("first")
        mock.write("second")
        mock.write("third")
        XCTAssertEqual(mock.writtenTexts, ["first", "second", "third"])
    }

    // MARK: - paste()

    func test_paste_shouldIncrementCallCount() {
        let mock = MockClipboardIO()
        mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 1)
        mock.paste()
        XCTAssertEqual(mock.pasteCallCount, 2)
    }

    // MARK: - read()

    func test_read_shouldReturnStubbedValue() {
        let mock = MockClipboardIO()
        mock.stubbedReadResult = "copied text"
        XCTAssertEqual(mock.read(), "copied text")
    }

    func test_read_shouldIncrementCallCount() {
        let mock = MockClipboardIO()
        _ = mock.read()
        _ = mock.read()
        XCTAssertEqual(mock.readCallCount, 2)
    }

    func test_read_whenNoStub_shouldReturnNil() {
        let mock = MockClipboardIO()
        XCTAssertNil(mock.read())
    }
}
```

- [ ] **Step 2: 将 ClipboardIOTests.swift 添加到 Xcode 项目**

在 `project.pbxproj` 中添加：

**2a.** 在 `PBXBuildFile` section 添加：

```
		C1B2C3D4E5F6A1B2C3D4E705 /* ClipboardIOTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = C1B2C3D4E5F6A1B2C3D4E706 /* ClipboardIOTests.swift */; };
```

**2b.** 在 `PBXFileReference` section 添加：

```
		C1B2C3D4E5F6A1B2C3D4E706 /* ClipboardIOTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ClipboardIOTests.swift; sourceTree = "<group>"; };
```

**2c.** 在 `40F4A5F6BED5447E9E9F74CF /* IO */` group 的 children 中添加：

```
				C1B2C3D4E5F6A1B2C3D4E706 /* ClipboardIOTests.swift */,
```

**2d.** 在 `2047A542841C4FD6A08BBEE4 /* Sources */` build phase files 列表中添加：

```
				C1B2C3D4E5F6A1B2C3D4E705 /* ClipboardIOTests.swift in Sources */,
```

- [ ] **Step 3: 运行测试，确认通过**

```bash
make test 2>&1 | grep "ClipboardIO\|TEST SUCCEEDED\|TEST FAILED\|Executed"
```

Expected: 6 tests pass for `ClipboardIOTests`, total 63 tests, 0 failures.

- [ ] **Step 4: 提交**

```bash
git add TalkFlowTests/IO/ClipboardIOTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "test: ClipboardIO 协议行为测试（6 个用例）"
```

---

### Task 4: 最终验证 + 提交

- [ ] **Step 1: 运行全部测试**

```bash
make test 2>&1 | grep "TEST SUCCEEDED\|TEST FAILED\|Executed"
```

Expected: `** TEST SUCCEEDED **`，63 tests（57 现有 + 6 新增），0 failures。

- [ ] **Step 2: 最终提交（如有未提交变更）**

```bash
git status
git add -A
git commit -m "chore: ClipboardIO 模块最终验证通过"
```
