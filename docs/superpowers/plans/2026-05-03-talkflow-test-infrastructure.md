# TalkFlow 测试基础设施实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从零搭建分层测试体系，覆盖纯函数、IO 层、View 逻辑，配合覆盖率门禁与 CI 强制执行。

**Architecture:** 单一 `TalkFlowTests` target，目录分层（Pure/IO/ViewLogic/Mocks/Helpers），利用已有 `MicPermissionIO` 协议做 Mock 注入。最后以 Makefile + pre-commit hook 固化 CI 门禁。

**Tech Stack:** XCTest, Swift 5.0, macOS 14.0+, Xcode 16.0+

---

### Task 1: 创建 Xcode Test Target

**Files:**
- Modify: `TalkFlow.xcodeproj/project.pbxproj`

> ⚠️ pbxproj 编辑需精确匹配旧文本。所有 UUID 已预生成，保证唯一。

- [ ] **Step 1: 在 PBXBuildFile section 末尾添加测试文件 build references**

找到 `/* End PBXBuildFile section */`，在其前插入：

```
		B68DF300A22943D9A22E65A4 /* MockMicPermissionIO.swift in Sources */ = {isa = PBXBuildFile; fileRef = B68DF300A22943D9A22E65A0; };
		9FC5960652A34BD8ADA6B126 /* XCTestCase+Async.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9FC5960652A34BD8ADA6B120; };
		E84532008AC04E0B963F4BF4 /* MicPermissionStatusTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = E84532008AC04E0B963F4BF0; };
		FA75952012F44B3D9DAF335C /* MicPermissionUIStateTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = FA75952012F44B3D9DAF3350; };
		D459C9BDCB2E47FE92880B72 /* MicPermissionIOTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = D459C9BDCB2E47FE92880B70; };
		4CFB696C80C74F97B99ED6DF /* PermissionCheckViewTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 4CFB696C80C74F97B99ED6D0; };
```

- [ ] **Step 2: 在 PBXFileReference section 末尾添加测试文件引用**

找到 `/* End PBXFileReference section */`，在其前插入：

```
		A9B3802F73E34506A606275E /* TalkFlowTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = TalkFlowTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		B68DF300A22943D9A22E65A0 /* MockMicPermissionIO.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MockMicPermissionIO.swift; sourceTree = "<group>"; };
		9FC5960652A34BD8ADA6B120 /* XCTestCase+Async.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = XCTestCase+Async.swift; sourceTree = "<group>"; };
		E84532008AC04E0B963F4BF0 /* MicPermissionStatusTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MicPermissionStatusTests.swift; sourceTree = "<group>"; };
		FA75952012F44B3D9DAF3350 /* MicPermissionUIStateTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MicPermissionUIStateTests.swift; sourceTree = "<group>"; };
		D459C9BDCB2E47FE92880B70 /* MicPermissionIOTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MicPermissionIOTests.swift; sourceTree = "<group>"; };
		4CFB696C80C74F97B99ED6D0 /* PermissionCheckViewTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PermissionCheckViewTests.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: 在 PBXGroup section 末尾添加 TalkFlowTests 文件组**

找到 `/* End PBXGroup section */`，在其前插入：

```
		AB72CF4CE5954A4597A7D359 /* TalkFlowTests */ = {
			isa = PBXGroup;
			children = (
				BA923226DE0E488FA0315146 /* Mocks */,
				4C078380F29B473A87A2EF1C /* Helpers */,
				C1AB66AA81174BF3BF985070 /* Pure */,
				8A5DB2648BAB49BCB071FA0A /* IO */,
				5DA1488335274E599BEA90D7 /* ViewLogic */,
			);
			path = TalkFlowTests;
			sourceTree = "<group>";
		};
		BA923226DE0E488FA0315146 /* Mocks */ = {
			isa = PBXGroup;
			children = (
				B68DF300A22943D9A22E65A0 /* MockMicPermissionIO.swift */,
			);
			path = Mocks;
			sourceTree = "<group>";
		};
		4C078380F29B473A87A2EF1C /* Helpers */ = {
			isa = PBXGroup;
			children = (
				9FC5960652A34BD8ADA6B120 /* XCTestCase+Async.swift */,
			);
			path = Helpers;
			sourceTree = "<group>";
		};
		C1AB66AA81174BF3BF985070 /* Pure */ = {
			isa = PBXGroup;
			children = (
				E84532008AC04E0B963F4BF0 /* MicPermissionStatusTests.swift */,
				FA75952012F44B3D9DAF3350 /* MicPermissionUIStateTests.swift */,
			);
			path = Pure;
			sourceTree = "<group>";
		};
		8A5DB2648BAB49BCB071FA0A /* IO */ = {
			isa = PBXGroup;
			children = (
				D459C9BDCB2E47FE92880B70 /* MicPermissionIOTests.swift */,
			);
			path = IO;
			sourceTree = "<group>";
		};
		5DA1488335274E599BEA90D7 /* ViewLogic */ = {
			isa = PBXGroup;
			children = (
				4CFB696C80C74F97B99ED6D0 /* PermissionCheckViewTests.swift */,
			);
			path = ViewLogic;
			sourceTree = "<group>";
		};
```

- [ ] **Step 4: 将 TalkFlowTests 组挂载到根组**

找到根组 `A1B2C3D4E5F6A1B2C3D4E509 /* = */`，在其 children 数组中，`A1B2C3D4E5F6A1B2C3D4E510 /* Products */` 之前插入：

```
				AB72CF4CE5954A4597A7D359 /* TalkFlowTests */,
```

即：

```
		A1B2C3D4E5F6A1B2C3D4E509 /* = */ = {
			isa = PBXGroup;
			children = (
				A1B2C3D4E5F6A1B2C3D4E500 /* TalkFlow */,
				AB72CF4CE5954A4597A7D359 /* TalkFlowTests */,
				A1B2C3D4E5F6A1B2C3D4E510 /* Products */,
			);
			sourceTree = "<group>";
		};
```

- [ ] **Step 5: 在 Products 组中添加 xctest 产物引用**

找到 `A1B2C3D4E5F6A1B2C3D4E510 /* Products */`，在其 children 数组中追加：

```
				A9B3802F73E34506A606275E /* TalkFlowTests.xctest */,
```

即：

```
		A1B2C3D4E5F6A1B2C3D4E510 /* Products */ = {
			isa = PBXGroup;
			children = (
				A1B2C3D4E5F6A1B2C3D4E5F8 /* TalkFlow.app */,
				A9B3802F73E34506A606275E /* TalkFlowTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
```

- [ ] **Step 6: 在 PBXNativeTarget section 末尾添加 TalkFlowTests target 定义**

找到 `/* End PBXNativeTarget section */`，在其前插入：

```
		66524544181B4D28810F14C2 /* TalkFlowTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 136AB81AE099413F9909A1D0 /* Build configuration list for PBXNativeTarget "TalkFlowTests" */;
			buildPhases = (
				372DB1C4B3114300BD09FE79 /* Sources */,
			);
			buildRules = (
			);
			dependencies = (
				30DE33FE371E426AB811D225 /* PBXTargetDependency */,
			);
			name = TalkFlowTests;
			productName = TalkFlowTests;
			productReference = A9B3802F73E34506A606275E /* TalkFlowTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

- [ ] **Step 7: 在 PBXProject section 的 targets 数组中注册 TalkFlowTests**

找到 `targets = (`，在其数组末尾（`A1B2C3D4E5F6A1B2C3D4E5F9 /* TalkFlow */,` 之后）追加：

```
				66524544181B4D28810F14C2 /* TalkFlowTests */,
```

- [ ] **Step 8: 在 PBXSourcesBuildPhase 区域添加 TalkFlowTests 的 Sources build phase**

找到 `/* End PBXSourcesBuildPhase section */`，在其前插入：

```
		372DB1C4B3114300BD09FE79 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				B68DF300A22943D9A22E65A4 /* MockMicPermissionIO.swift in Sources */,
				9FC5960652A34BD8ADA6B126 /* XCTestCase+Async.swift in Sources */,
				E84532008AC04E0B963F4BF4 /* MicPermissionStatusTests.swift in Sources */,
				FA75952012F44B3D9DAF335C /* MicPermissionUIStateTests.swift in Sources */,
				D459C9BDCB2E47FE92880B72 /* MicPermissionIOTests.swift in Sources */,
				4CFB696C80C74F97B99ED6DF /* PermissionCheckViewTests.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

- [ ] **Step 9: 在 XCBuildConfiguration 区域添加 TalkFlowTests 的 Debug/Release 配置**

找到 `/* End XCBuildConfiguration section */`，在其前插入：

```
		E177925041864CCA9035D5FD /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.talkflow.tests;
				PRODUCT_NAME = TalkFlowTests;
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/TalkFlow.app/Contents/MacOS/TalkFlow";
			};
			name = Debug;
		};
		E177925041864CCA9035D5FE /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.talkflow.tests;
				PRODUCT_NAME = TalkFlowTests;
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/TalkFlow.app/Contents/MacOS/TalkFlow";
			};
			name = Release;
		};
```

- [ ] **Step 10: 在 XCConfigurationList 区域添加 TalkFlowTests 的配置列表**

找到 `/* End XCConfigurationList section */`，在其前插入：

```
		136AB81AE099413F9909A1D0 /* Build configuration list for PBXNativeTarget "TalkFlowTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				E177925041864CCA9035D5FD /* Debug */,
				E177925041864CCA9035D5FE /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

- [ ] **Step 11: 在 PBXTargetDependency 区域添加依赖（固定位置插入）**

pbxproj 文件目前没有 `PBXTargetDependency` 和 `PBXContainerItemProxy` 区域。需要在 `/* End PBXNativeTarget section */` 之后插入：

```
/* Begin PBXTargetDependency section */
		30DE33FE371E426AB811D225 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = A1B2C3D4E5F6A1B2C3D4E5F9 /* TalkFlow */;
			targetProxy = B5FFE4C23CA6491BBC46872B /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin PBXContainerItemProxy section */
		B5FFE4C23CA6491BBC46872B /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A1B2C3D4E5F6A1B2C3D4E699 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = A1B2C3D4E5F6A1B2C3D4E5F9;
			remoteInfo = TalkFlow;
		};
/* End PBXContainerItemProxy section */
```

插入位置：`/* End PBXNativeTarget section */` 和 `/* Begin PBXProject section */` 之间。

- [ ] **Step 12: 验证 pbxproj 文件格式**

```bash
plutil -lint TalkFlow.xcodeproj/project.pbxproj
```
Expected: `OK`

- [ ] **Step 13: Commit**

```bash
git add TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: add TalkFlowTests target to Xcode project"
```

---

### Task 2: 创建 Mock + Helper 基础设施

**Files:**
- Create: `TalkFlowTests/Mocks/MockMicPermissionIO.swift`
- Create: `TalkFlowTests/Helpers/XCTestCase+Async.swift`

- [ ] **Step 1: 创建 MockMicPermissionIO.swift**

```swift
// TalkFlowTests/Mocks/MockMicPermissionIO.swift
import Foundation
@testable import TalkFlow

/// Mock 实现 MicPermissionIO 协议，用于单元测试
/// 无任何真实副作用，通过 stubbed 值控制行为
final class MockMicPermissionIO: MicPermissionIO {
    var stubbedStatus: MicPermissionStatus = .notDetermined
    var performActionCallCount = 0
    var performActionReceivedStatuses: [MicPermissionStatus] = []

    func currentStatus() -> MicPermissionStatus {
        stubbedStatus
    }

    func performAction(for status: MicPermissionStatus) async -> MicPermissionStatus {
        performActionCallCount += 1
        performActionReceivedStatuses.append(status)
        return stubbedStatus
    }
}
```

- [ ] **Step 2: 创建 XCTestCase+Async.swift**

```swift
// TalkFlowTests/Helpers/XCTestCase+Async.swift
import XCTest

extension XCTestCase {
    /// 对 async 表达式做相等断言的便捷方法
    func assertAsync<T: Equatable>(
        timeout: TimeInterval = 1.0,
        _ expression: @escaping () async -> T,
        equals expected: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let result = await expression()
        XCTAssertEqual(result, expected, file: file, line: line)
    }
}
```

- [ ] **Step 3: 验证文件编译（通过 test 命令）**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' 2>&1 | tail -5
```
Expected: 测试 target 编译成功，0 个测试（尚无测试方法）

- [ ] **Step 4: Commit**

```bash
git add TalkFlowTests/
git commit -m "feat: add MockMicPermissionIO and async test helper"
```

---

### Task 3: 纯函数测试 — MicPermissionStatus → UIState 映射

**Files:**
- Create: `TalkFlowTests/Pure/MicPermissionStatusTests.swift`
- Create: `TalkFlowTests/Pure/MicPermissionUIStateTests.swift`

- [ ] **Step 1: 创建 MicPermissionStatusTests.swift（先写测试，TDD）**

```swift
// TalkFlowTests/Pure/MicPermissionStatusTests.swift
import XCTest
@testable import TalkFlow

/// 穷尽测试 MicPermissionStatus 枚举的 produceUIState 映射
final class MicPermissionStatusTests: XCTestCase {

    // MARK: - authorized

    func test_authorized_shouldProduceAuthorizedLabel() {
        let state = produceUIState(from: .authorized)
        XCTAssertEqual(state.label, "✅ 麦克风权限：已启用")
    }

    func test_authorized_shouldHideButton() {
        let state = produceUIState(from: .authorized)
        XCTAssertFalse(state.buttonVisible)
    }

    func test_authorized_shouldNotNeedSystemSettings() {
        let state = produceUIState(from: .authorized)
        XCTAssertFalse(state.needsSystemSettings)
    }

    // MARK: - notDetermined

    func test_notDetermined_shouldProduceRequestLabel() {
        let state = produceUIState(from: .notDetermined)
        XCTAssertEqual(state.label, "🎤 需要麦克风权限来录制语音")
    }

    func test_notDetermined_shouldShowButton() {
        let state = produceUIState(from: .notDetermined)
        XCTAssertTrue(state.buttonVisible)
    }

    func test_notDetermined_shouldNotNeedSystemSettings() {
        let state = produceUIState(from: .notDetermined)
        XCTAssertFalse(state.needsSystemSettings)
    }

    // MARK: - denied

    func test_denied_shouldProduceDeniedLabel() {
        let state = produceUIState(from: .denied)
        XCTAssertEqual(state.label, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_denied_shouldShowButton() {
        let state = produceUIState(from: .denied)
        XCTAssertTrue(state.buttonVisible)
    }

    func test_denied_shouldNeedSystemSettings() {
        let state = produceUIState(from: .denied)
        XCTAssertTrue(state.needsSystemSettings)
    }
}
```

- [ ] **Step 2: 运行测试，预期全部通过（被测函数已存在）**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/MicPermissionStatusTests 2>&1 | grep -E "(Test Case|passed|failed)"
```
Expected: 9 个测试全部 PASS

- [ ] **Step 3: 创建 MicPermissionUIStateTests.swift（静态预置值测试）**

```swift
// TalkFlowTests/Pure/MicPermissionUIStateTests.swift
import XCTest
@testable import TalkFlow

/// 验证 MicPermissionUIState 静态预置值的完整性
final class MicPermissionUIStateTests: XCTestCase {

    // MARK: - .authorized 预置值

    func test_authorizedPreset_label_shouldBeAuthorized() {
        XCTAssertEqual(MicPermissionUIState.authorized.label, "✅ 麦克风权限：已启用")
    }

    func test_authorizedPreset_buttonVisible_shouldBeFalse() {
        XCTAssertFalse(MicPermissionUIState.authorized.buttonVisible)
    }

    func test_authorizedPreset_buttonTitle_shouldBeEmpty() {
        XCTAssertEqual(MicPermissionUIState.authorized.buttonTitle, "")
    }

    func test_authorizedPreset_needsSystemSettings_shouldBeFalse() {
        XCTAssertFalse(MicPermissionUIState.authorized.needsSystemSettings)
    }

    // MARK: - .notDetermined 预置值

    func test_notDeterminedPreset_label_shouldBeRequest() {
        XCTAssertEqual(MicPermissionUIState.notDetermined.label, "🎤 需要麦克风权限来录制语音")
    }

    func test_notDeterminedPreset_buttonVisible_shouldBeTrue() {
        XCTAssertTrue(MicPermissionUIState.notDetermined.buttonVisible)
    }

    func test_notDeterminedPreset_buttonTitle_shouldBeGrant() {
        XCTAssertEqual(MicPermissionUIState.notDetermined.buttonTitle, "授予麦克风权限")
    }

    func test_notDeterminedPreset_needsSystemSettings_shouldBeFalse() {
        XCTAssertFalse(MicPermissionUIState.notDetermined.needsSystemSettings)
    }

    // MARK: - .denied 预置值

    func test_deniedPreset_label_shouldBeDenied() {
        XCTAssertEqual(MicPermissionUIState.denied.label, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_deniedPreset_buttonVisible_shouldBeTrue() {
        XCTAssertTrue(MicPermissionUIState.denied.buttonVisible)
    }

    func test_deniedPreset_buttonTitle_shouldBeOpenSettings() {
        XCTAssertEqual(MicPermissionUIState.denied.buttonTitle, "打开系统设置")
    }

    func test_deniedPreset_needsSystemSettings_shouldBeTrue() {
        XCTAssertTrue(MicPermissionUIState.denied.needsSystemSettings)
    }
}
```

- [ ] **Step 4: 运行测试**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/MicPermissionUIStateTests 2>&1 | grep -E "(Test Case|passed|failed)"
```
Expected: 12 个测试全部 PASS

- [ ] **Step 5: Commit**

```bash
git add TalkFlowTests/Pure/
git commit -m "feat: add pure function tests for MicPermission status and UI state"
```

---

### Task 4: IO 层测试 — MicPermissionIO Mock 验证

**Files:**
- Create: `TalkFlowTests/IO/MicPermissionIOTests.swift`

- [ ] **Step 1: 创建 MicPermissionIOTests.swift**

```swift
// TalkFlowTests/IO/MicPermissionIOTests.swift
import XCTest
@testable import TalkFlow

/// 通过 MockMicPermissionIO 验证 IO 协议行为
/// 测试 Mock 本身是否按约定工作
final class MicPermissionIOTests: XCTestCase {

    // MARK: - currentStatus()

    func test_currentStatus_shouldReturnStubbedValue() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        XCTAssertEqual(mock.currentStatus(), .authorized)
    }

    func test_currentStatus_whenNotDetermined_shouldReturnNotDetermined() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        XCTAssertEqual(mock.currentStatus(), .notDetermined)
    }

    func test_currentStatus_whenDenied_shouldReturnDenied() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        XCTAssertEqual(mock.currentStatus(), .denied)
    }

    // MARK: - performAction(for:) — 调用计数与参数记录

    func test_performAction_shouldIncrementCallCount() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        _ = await mock.performAction(for: .denied)
        XCTAssertEqual(mock.performActionCallCount, 1)
        _ = await mock.performAction(for: .denied)
        XCTAssertEqual(mock.performActionCallCount, 2)
    }

    func test_performAction_shouldRecordReceivedStatus() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        _ = await mock.performAction(for: .notDetermined)
        XCTAssertEqual(mock.performActionReceivedStatuses, [.notDetermined])
        _ = await mock.performAction(for: .denied)
        XCTAssertEqual(mock.performActionReceivedStatuses, [.notDetermined, .denied])
    }

    func test_performAction_shouldReturnStubbedStatus() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let result = await mock.performAction(for: .notDetermined)
        XCTAssertEqual(result, .authorized)
    }

    // MARK: - performAction(for:) — 各分支路径验证

    func test_performAction_whenAuthorized_shouldNotChangeState() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let result = await mock.performAction(for: .authorized)
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }

    func test_performAction_whenNotDetermined_shouldSimulateRequestAccess() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let result = await mock.performAction(for: .notDetermined)
        XCTAssertEqual(result, .notDetermined)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }

    func test_performAction_whenDenied_shouldSimulateOpenPreferences() async {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let result = await mock.performAction(for: .denied)
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }
}
```

- [ ] **Step 2: 运行测试**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/MicPermissionIOTests 2>&1 | grep -E "(Test Case|passed|failed)"
```
Expected: 9 个测试全部 PASS

- [ ] **Step 3: Commit**

```bash
git add TalkFlowTests/IO/
git commit -m "feat: add IO layer tests with MockMicPermissionIO"
```

---

### Task 5: View 逻辑测试 — PermissionCheckView 数据映射

**Files:**
- Create: `TalkFlowTests/ViewLogic/PermissionCheckViewTests.swift`

- [ ] **Step 1: 分析 PermissionCheckView 中可测试的纯数据映射逻辑**

`impureRender()` 的映射逻辑：
- `status == .authorized` → label 颜色 `.systemGreen`，否则 `.secondaryLabelColor`
- `produceUIState(from:)` 决定 label 文本、button 标题、button 是否隐藏

测试策略：注入 Mock IO，调用 `setUp()` 触发 render，断言 NSView 子视图状态。

- [ ] **Step 2: 创建 PermissionCheckViewTests.swift**

```swift
// TalkFlowTests/ViewLogic/PermissionCheckViewTests.swift
import XCTest
import AppKit
@testable import TalkFlow

/// View 逻辑测试：验证数据 → UI 映射，不测 Autolayout/像素
final class PermissionCheckViewTests: XCTestCase {

    // MARK: - authorized 状态

    func test_render_whenAuthorized_shouldShowAuthorizedLabel() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "✅ 麦克风权限：已启用")
    }

    func test_render_whenAuthorized_shouldSetGreenColor() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .systemGreen)
    }

    func test_render_whenAuthorized_shouldHideButton() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .authorized
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertTrue(button?.isHidden ?? false)
    }

    // MARK: - notDetermined 状态

    func test_render_whenNotDetermined_shouldShowRequestLabel() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "🎤 需要麦克风权限来录制语音")
    }

    func test_render_whenNotDetermined_shouldShowSecondaryLabelColor() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .secondaryLabelColor)
    }

    func test_render_whenNotDetermined_shouldShowGrantButton() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertEqual(button?.title, "授予麦克风权限")
        XCTAssertFalse(button?.isHidden ?? true)
    }

    // MARK: - denied 状态

    func test_render_whenDenied_shouldShowDeniedLabel() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.stringValue, "⚠️ 麦克风权限已被拒绝，请在系统设置中开启")
    }

    func test_render_whenDenied_shouldShowSecondaryLabelColor() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let label = view.subviews.compactMap { $0 as? NSTextField }.first
        XCTAssertEqual(label?.textColor, .secondaryLabelColor)
    }

    func test_render_whenDenied_shouldShowOpenSettingsButton() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .denied
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertEqual(button?.title, "打开系统设置")
        XCTAssertFalse(button?.isHidden ?? true)
    }

    // MARK: - IO 交互验证

    func test_buttonClick_shouldCallPerformAction() {
        let mock = MockMicPermissionIO()
        mock.stubbedStatus = .notDetermined
        let view = PermissionCheckView(frame: .zero, io: mock)
        view.setUp()

        let button = view.subviews.compactMap { $0 as? NSButton }.first
        button?.performClick(nil)

        // performClick 触发 impureButtonClicked，其中 async 调用需要等待
        let expectation = XCTestExpectation(description: "performAction called")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if mock.performActionCallCount > 0 {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mock.performActionCallCount, 1)
    }

    // MARK: - IO 注入验证

    func test_defaultInit_shouldUseDefaultMicPermissionIO() {
        let view = PermissionCheckView(frame: .zero)
        // 默认构造不应崩溃
        XCTAssertNotNil(view)
    }
}
```

- [ ] **Step 2: 运行测试**

```bash
xcodebuild test -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/PermissionCheckViewTests 2>&1 | grep -E "(Test Case|passed|failed)"
```
Expected: 11 个测试全部 PASS

- [ ] **Step 3: Commit**

```bash
git add TalkFlowTests/ViewLogic/
git commit -m "feat: add PermissionCheckView logic tests"
```

---

### Task 6: Makefile + Pre-Commit Hook

**Files:**
- Create: `Makefile`
- Create: `.git/hooks/pre-commit`

- [ ] **Step 1: 创建 Makefile**

```makefile
.PHONY: test coverage lint

test:
	xcodebuild test \
		-scheme TalkFlow \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES

coverage:
	xcodebuild test \
		-scheme TalkFlow \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES \
		-resultBundlePath /tmp/TalkFlow_coverage.xcresult \
		-quiet
	@echo "📊 Coverage:"
	@xcrun xccov view --report /tmp/TalkFlow_coverage.xcresult

lint:
	@echo "🔍 swiftlint not configured — add .swiftlint.yml to enable"
```

- [ ] **Step 2: 创建 Pre-Commit Hook**

```bash
#!/bin/bash
# TalkFlow pre-commit hook: 拒绝未通过测试的提交

set -e

echo "🧪 Running tests before commit..."

xcodebuild test \
    -scheme TalkFlow \
    -destination 'platform=macOS' \
    -quiet

echo ""
echo "✅ All tests passed."
```

```bash
# 安装 hook
chmod +x .git/hooks/pre-commit
```

- [ ] **Step 3: 验证 Makefile**

```bash
make test 2>&1 | tail -20
```
Expected: 所有测试 PASS，显示 "** TEST SUCCEEDED **"

- [ ] **Step 4: Commit**

```bash
git add Makefile .git/hooks/pre-commit
git commit -m "feat: add Makefile and pre-commit test hook"
```

---

### Task 7: 全量覆盖率验证

**Files:** 无新建，验证已有文件

- [ ] **Step 1: 运行全量测试并生成覆盖率**

```bash
xcodebuild test \
    -scheme TalkFlow \
    -destination 'platform=macOS' \
    -enableCodeCoverage YES \
    -resultBundlePath /tmp/TalkFlow_coverage.xcresult
```

- [ ] **Step 2: 查看覆盖率**

```bash
xcrun xccov view --report /tmp/TalkFlow_coverage.xcresult
```

- [ ] **Step 3: 验证覆盖率阈值**

| 检查项 | 阈值 | 验证方式 |
|--------|------|----------|
| 整体行覆盖率 | ≥90% | 查看 xccov 输出的 total line coverage |
| `Utils/MicPermission.swift` | =100% | 该文件只有纯函数和数据类型，应全覆盖 |
| `IO/MicPermissionIO.swift` | =100% | Mock 测试覆盖所有分支 |
| `Views/PermissionCheckView.swift` | ≥80% | View 测试覆盖数据映射逻辑 |

- [ ] **Step 4: 记录覆盖率基准**

```bash
xcrun xccov view --report --json /tmp/TalkFlow_coverage.xcresult > docs/superpowers/coverage-baseline.json
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/coverage-baseline.json
git commit -m "chore: record initial test coverage baseline"
```
