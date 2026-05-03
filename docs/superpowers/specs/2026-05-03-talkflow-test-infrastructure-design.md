# TalkFlow 测试基础设施设计

> 日期：2026-05-03
> 分支：`feat/test-infrastructure`

## 1. 目标

从零搭建分层测试体系，覆盖单元测试 + IO 层集成测试 + View 逻辑测试，配合覆盖率门禁与 CI 强制执行机制。

## 2. 测试框架

- **XCTest**（Apple 原生，零外部依赖）
- 利用现有 `MicPermissionIO` 协议抽象做 Mock 注入

## 3. 目录结构

```
TalkFlow/
├── TalkFlow.xcodeproj
├── TalkFlow/                          ← 主 target（不变）
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── Utils/MicPermission.swift
│   ├── IO/MicPermissionIO.swift
│   └── Views/PermissionCheckView.swift
└── TalkFlowTests/                     ← 新增
    ├── Pure/
    │   ├── MicPermissionStatusTests.swift
    │   └── MicPermissionUIStateTests.swift
    ├── IO/
    │   └── MicPermissionIOTests.swift
    ├── ViewLogic/
    │   └── PermissionCheckViewTests.swift
    ├── Mocks/
    │   └── MockMicPermissionIO.swift
    └── Helpers/
        └── XCTestCase+Async.swift
```

- 单一 test target：`TalkFlowTests`
- 测试通过 `@testable import TalkFlow` 访问主模块

## 4. 测试模式与约定

### 4.1 纯函数测试（Pure/）

- 模式：给定输入 → 断言输出。无 Mock、无 setup、无 tearDown
- 命名：`test_<输入场景>_should<预期结果>`
- ADT 枚举穷尽所有 case
- 覆盖率目标：**100%**

### 4.2 IO 层测试（IO/）

- 模式：Mock 实现协议 → 注入被测对象 → 验证行为
- Mock 记录调用次数、参数、无真实副作用
- 覆盖率目标：**100%**

### 4.3 View 逻辑测试（ViewLogic/）

- 仅测数据→UI 映射逻辑，不测像素/布局/Autolayout
- 注入 Mock IO，验证 label 文本、颜色、button 可见性
- 覆盖率目标：**≥80%**

### 4.4 Async 辅助

- 提供 `XCTestCase+Async` 扩展，封装 `async` 测试断言

### 4.5 文件约束

- 文件头注释 `// TalkFlowTests/<Layer>/`
- 单测文件不超过 200 行
- 禁止 `sleep()`、不可靠时序假设

## 5. 覆盖率门禁

| 检查项 | 阈值 | 违反行为 |
|--------|------|----------|
| 整体行覆盖率 | ≥90% | CI 失败，拒绝合并 |
| `Utils/` 目录 | =100% | CI 失败 |
| `IO/` 目录 | =100% | CI 失败 |
| `Views/` 目录 | ≥80% | CI 失败 |

## 6. CI 集成

### 6.1 测试命令

```bash
xcodebuild test -scheme TalkFlow -enableCodeCoverage YES
```

### 6.2 Pre-Commit Hook

```bash
xcodebuild test -scheme TalkFlow -quiet
```
测试失败 → 拒绝提交。

### 6.3 Makefile

```makefile
test:
	xcodebuild test -scheme TalkFlow -enableCodeCoverage YES

coverage:
	xcodebuild test -scheme TalkFlow -enableCodeCoverage YES
	xcrun xccov view --report --only-targets build/Logs/Test/*.xcresult

lint:
	swiftlint --strict
```

## 7. 现有代码可测性评估

- `MicPermissionIO` 协议已存在 → Mock 注入零改动
- `produceUIState(from:)` 已是纯函数 → 直接可测
- `PermissionCheckView` 通过构造器注入 IO → 可测
- 无需因可测性重构现有代码
