# Graph Report - .  (2026-05-03)

## Corpus Check
- Corpus is ~9,731 words - fits in a single context window. You may not need a graph.

## Summary
- 126 nodes · 168 edges · 13 communities detected
- Extraction: 68% EXTRACTED · 32% INFERRED · 0% AMBIGUOUS · INFERRED: 53 edges (avg confidence: 0.81)
- Token cost: 35,000 input · 8,000 output

## Community Hubs (Navigation)
- [[_COMMUNITY_IO 层测试套件|IO 层测试套件]]
- [[_COMMUNITY_函数式编程原则|函数式编程原则]]
- [[_COMMUNITY_UI State 静态预置测试|UI State 静态预置测试]]
- [[_COMMUNITY_覆盖率基线与计划文档|覆盖率基线与计划文档]]
- [[_COMMUNITY_权限状态映射测试|权限状态映射测试]]
- [[_COMMUNITY_View 逻辑测试|View 逻辑测试]]
- [[_COMMUNITY_View 层实现|View 层实现]]
- [[_COMMUNITY_App 入口与代理|App 入口与代理]]
- [[_COMMUNITY_IO 层默认实现|IO 层默认实现]]
- [[_COMMUNITY_ADT 数据类型|ADT 数据类型]]
- [[_COMMUNITY_测试辅助工具|测试辅助工具]]
- [[_COMMUNITY_管道与高阶函数|管道与高阶函数]]
- [[_COMMUNITY_不可变数据|不可变数据]]

## God Nodes (most connected - your core abstractions)
1. `MockMicPermissionIO` - 23 edges
2. `PermissionCheckView` - 20 edges
3. `MicPermissionUIStateTests` - 14 edges
4. `PermissionCheckViewTests` - 13 edges
5. `MicPermissionIOTests` - 11 edges
6. `MicPermissionStatusTests` - 11 edges
7. `produceUIState()` - 11 edges
8. `测试基础设施设计` - 9 edges
9. `AppDelegate` - 8 edges
10. `TalkFlow` - 8 edges

## Surprising Connections (you probably didn't know these)
- `纯函数抽象铁律` --informs--> `测试基础设施设计`  [INFERRED]
  AGENTS.md → docs/superpowers/specs/2026-05-03-talkflow-test-infrastructure-design.md
- `AppIcon 应用图标资源` --asset_of--> `TalkFlow`  [EXTRACTED]
  TalkFlow/Assets.xcassets/AppIcon.appiconset → README.md
- `Mock 注入模式` --uses--> `IO 协议抽象`  [INFERRED]
  docs/superpowers/specs/2026-05-03-talkflow-test-infrastructure-design.md → AGENTS.md
- `纯函数抽象铁律` --implements--> `函数式编程范式`  [EXTRACTED]
  AGENTS.md → README.md
- `7 任务分步实现计划` --implements--> `测试基础设施设计`  [INFERRED]
  docs/superpowers/plans/2026-05-03-talkflow-test-infrastructure.md → docs/superpowers/specs/2026-05-03-talkflow-test-infrastructure-design.md

## Hyperedges (group relationships)
- **函数式编程三大原则** — agents_pure_function_abstraction, agents_side_effect_isolation, agents_immutable_data [INFERRED 0.85]
- **测试质量门禁体系** — spec_coverage_gate, spec_precommit_hook, spec_makefile [EXTRACTED 1.00]

## Communities

### Community 0 - "IO 层测试套件"
Cohesion: 0.15
Nodes (3): MicPermissionIOTests, MicPermissionIO, MockMicPermissionIO

### Community 1 - "函数式编程原则"
Cohesion: 0.12
Nodes (17): 代数数据类型 ADT, 构造与副作用分离, 穷尽模式匹配, IO 协议抽象, 纯函数抽象铁律, 引用透明性, 副作用隔离, AppIcon 应用图标资源 (+9 more)

### Community 2 - "UI State 静态预置测试"
Cohesion: 0.13
Nodes (2): MicPermissionUIStateTests, XCTestCase

### Community 3 - "覆盖率基线与计划文档"
Cohesion: 0.15
Nodes (13): IO/MicPermissionIO.swift 28.2% 覆盖, Utils/MicPermission.swift 100% 覆盖, 整体覆盖率 74.4%, Views/PermissionCheckView.swift 100% 覆盖, Subagent-Driven 开发模式, 7 任务分步实现计划, TDD 测试驱动开发, 覆盖率门禁 CI (+5 more)

### Community 4 - "权限状态映射测试"
Cohesion: 0.29
Nodes (2): MicPermissionStatusTests, produceUIState()

### Community 5 - "View 逻辑测试"
Cohesion: 0.2
Nodes (1): PermissionCheckViewTests

### Community 6 - "View 层实现"
Cohesion: 0.33
Nodes (2): NSView, PermissionCheckView

### Community 7 - "App 入口与代理"
Cohesion: 0.28
Nodes (3): NSApplicationDelegate, NSObject, AppDelegate

### Community 8 - "IO 层默认实现"
Cohesion: 0.43
Nodes (3): DefaultMicPermissionIO, MicPermissionIO, micPermissionStatus()

### Community 9 - "ADT 数据类型"
Cohesion: 0.29
Nodes (6): Equatable, MicPermissionStatus, authorized, denied, notDetermined, MicPermissionUIState

### Community 10 - "测试辅助工具"
Cohesion: 0.67
Nodes (1): XCTestCase

### Community 11 - "管道与高阶函数"
Cohesion: 1.0
Nodes (2): 高阶函数优先, 管道式流程处理

### Community 13 - "不可变数据"
Cohesion: 1.0
Nodes (1): 不可变数据

## Knowledge Gaps
- **27 isolated node(s):** `authorized`, `notDetermined`, `denied`, `MicPermissionUIState`, `麦克风权限自动检测与引导` (+22 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `UI State 静态预置测试`** (15 nodes): `MicPermissionUIStateTests`, `.test_authorizedPreset_buttonTitle_shouldBeEmpty()`, `.test_authorizedPreset_buttonVisible_shouldBeFalse()`, `.test_authorizedPreset_label_shouldBeAuthorized()`, `.test_authorizedPreset_needsSystemSettings_shouldBeFalse()`, `.test_deniedPreset_buttonTitle_shouldBeOpenSettings()`, `.test_deniedPreset_buttonVisible_shouldBeTrue()`, `.test_deniedPreset_label_shouldBeDenied()`, `.test_deniedPreset_needsSystemSettings_shouldBeTrue()`, `.test_notDeterminedPreset_buttonTitle_shouldBeGrant()`, `.test_notDeterminedPreset_buttonVisible_shouldBeTrue()`, `.test_notDeterminedPreset_label_shouldBeRequest()`, `.test_notDeterminedPreset_needsSystemSettings_shouldBeFalse()`, `MicPermissionUIStateTests.swift`, `XCTestCase`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `权限状态映射测试`** (12 nodes): `MicPermissionStatusTests`, `.test_authorized_shouldHideButton()`, `.test_authorized_shouldNotNeedSystemSettings()`, `.test_authorized_shouldProduceAuthorizedLabel()`, `.test_denied_shouldNeedSystemSettings()`, `.test_denied_shouldProduceDeniedLabel()`, `.test_denied_shouldShowButton()`, `.test_notDetermined_shouldNotNeedSystemSettings()`, `.test_notDetermined_shouldProduceRequestLabel()`, `.test_notDetermined_shouldShowButton()`, `MicPermissionStatusTests.swift`, `produceUIState()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `View 逻辑测试`** (10 nodes): `PermissionCheckViewTests.swift`, `PermissionCheckViewTests`, `.test_buttonClick_shouldCallPerformAction()`, `.test_defaultInit_shouldUseDefaultMicPermissionIO()`, `.test_render_whenAuthorized_shouldHideButton()`, `.test_render_whenAuthorized_shouldSetGreenColor()`, `.test_render_whenAuthorized_shouldShowAuthorizedLabel()`, `.test_render_whenDenied_shouldShowOpenSettingsButton()`, `.test_render_whenNotDetermined_shouldShowRequestLabel()`, `.test_render_whenNotDetermined_shouldShowSecondaryLabelColor()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `View 层实现`** (9 nodes): `NSView`, `PermissionCheckView.swift`, `PermissionCheckView`, `.impureButtonClicked()`, `.impureObserveAppActivation()`, `.impureRender()`, `.impureSetupUI()`, `.init()`, `.setUp()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `测试辅助工具`** (3 nodes): `XCTestCase`, `.assertAsync()`, `XCTestCaseAsync.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `管道与高阶函数`** (2 nodes): `高阶函数优先`, `管道式流程处理`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `不可变数据`** (1 nodes): `不可变数据`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PermissionCheckView` connect `View 层实现` to `IO 层测试套件`, `View 逻辑测试`, `App 入口与代理`?**
  _High betweenness centrality (0.174) - this node is a cross-community bridge._
- **Why does `produceUIState()` connect `权限状态映射测试` to `ADT 数据类型`, `View 层实现`?**
  _High betweenness centrality (0.101) - this node is a cross-community bridge._
- **Are the 19 inferred relationships involving `MockMicPermissionIO` (e.g. with `.test_currentStatus_shouldReturnStubbedValue()` and `.test_currentStatus_whenNotDetermined_shouldReturnNotDetermined()`) actually correct?**
  _`MockMicPermissionIO` has 19 INFERRED edges - model-reasoned connections that need verification._
- **Are the 12 inferred relationships involving `PermissionCheckView` (e.g. with `.test_render_whenAuthorized_shouldShowAuthorizedLabel()` and `.test_render_whenAuthorized_shouldSetGreenColor()`) actually correct?**
  _`PermissionCheckView` has 12 INFERRED edges - model-reasoned connections that need verification._
- **What connects `authorized`, `notDetermined`, `denied` to the rest of the system?**
  _27 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `函数式编程原则` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._
- **Should `UI State 静态预置测试` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._