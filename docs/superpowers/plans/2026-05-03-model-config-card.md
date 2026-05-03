# 模型配置卡片 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在主窗口新增「模型」卡片 — Vertex AI 配置 + ADC 自动检测 + 连接测试

**Architecture:** 独立 `ModelSettingsView` 作为 CardView 内容，`ADCParser` 纯函数解析 + `ADCLoaderIO` 副作用读文件，连接测试复用现有 `JWTTokenProvider` + `VertexAIIO`

**Tech Stack:** Swift, AppKit (NSPopUpButton/NSTextField/NSButton), Foundation, async/await

---

## 变更文件

| 操作 | 文件 | 职责 |
|------|------|------|
| 新建 | `TalkFlow/Utils/ADCParser.swift` | `ADCParsedInfo` struct + `parseADC` 纯函数 |
| 新建 | `TalkFlow/IO/ADCLoaderIO.swift` | `impureLoadADCFromDefaultPath()` 副作用 |
| 新建 | `TalkFlow/Views/ModelSettingsView.swift` | 卡片内容视图 |
| 新建 | `TalkFlowTests/Utils/ADCParserTests.swift` | ADC 解析测试 |
| 修改 | `TalkFlow/IO/ProviderIO.swift` | ProviderError.displayMessage 扩展 |
| 修改 | `TalkFlow/AppDelegate.swift` | 新增模型卡片 |
| 修改 | `TalkFlow.xcodeproj/project.pbxproj` | 注册新文件 |

---

### Task 1: ADCParsedInfo 模型 + parseADC 纯函数

**Files:**
- Create: `TalkFlow/Utils/ADCParser.swift`
- Create: `TalkFlowTests/Utils/ADCParserTests.swift`

- [ ] **Step 1: 编写失败测试**

```swift
// TalkFlowTests/Utils/ADCParserTests.swift
import XCTest
@testable import TalkFlow

final class ADCParserTests: XCTestCase {

    // MARK: - 有效 ADC JSON（含 project_id）

    func testParseADC_validFullJSON_returnsParsedInfo() throws {
        let json: [String: Any] = [
            "client_email": "test@developer.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n",
            "token_uri": "https://oauth2.googleapis.com/token",
            "project_id": "my-project",
        ]
        let result = try parseADC(from: json)
        XCTAssertEqual(result.clientEmail, "test@developer.gserviceaccount.com")
        XCTAssertEqual(result.privateKey, "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n")
        XCTAssertEqual(result.tokenURI, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(result.projectID, "my-project")
    }

    // MARK: - 有效 ADC JSON（不含 project_id）

    func testParseADC_validJSONWithoutProjectID_returnsParsedInfoWithNilProjectID() throws {
        let json: [String: Any] = [
            "client_email": "test@developer.gserviceaccount.com",
            "private_key": "-----BEGIN PRIVATE KEY-----\nxyz\n-----END PRIVATE KEY-----\n",
            "token_uri": "https://oauth2.googleapis.com/token",
        ]
        let result = try parseADC(from: json)
        XCTAssertEqual(result.clientEmail, "test@developer.gserviceaccount.com")
        XCTAssertEqual(result.privateKey, "-----BEGIN PRIVATE KEY-----\nxyz\n-----END PRIVATE KEY-----\n")
        XCTAssertEqual(result.tokenURI, "https://oauth2.googleapis.com/token")
        XCTAssertNil(result.projectID)
    }

    // MARK: - 缺失必填字段

    func testParseADC_missingClientEmail_throws() {
        let json: [String: Any] = [
            "private_key": "k",
            "token_uri": "https://example.com",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "client_email")
        }
    }

    func testParseADC_missingPrivateKey_throws() {
        let json: [String: Any] = [
            "client_email": "x@x.com",
            "token_uri": "https://example.com",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "private_key")
        }
    }

    func testParseADC_missingTokenURI_throws() {
        let json: [String: Any] = [
            "client_email": "x@x.com",
            "private_key": "k",
        ]
        XCTAssertThrowsError(try parseADC(from: json)) { error in
            guard case ADCParseError.missingField(let field) = error else {
                return XCTFail("Expected missingField error")
            }
            XCTAssertEqual(field, "token_uri")
        }
    }
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/ADCParserTests 2>&1 | tail -5
```
预期: `cannot find 'ADCParserTests' in scope` 或类似编译错误

- [ ] **Step 3: 添加测试文件到 Xcode 项目**

在 `project.pbxproj` 的 TalkFlowTests PBXGroup 中添加 `ADCParserTests.swift` 引用。

- [ ] **Step 4: 实现 ADCParsedInfo + parseADC**

```swift
// TalkFlow/Utils/ADCParser.swift
import Foundation

// MARK: - ADC 解析结果

/// Application Default Credentials 解析结果
/// projectID 可选 — ADC 文件不一定包含
struct ADCParsedInfo: Equatable {
    let clientEmail: String
    let privateKey: String
    let tokenURI: String
    let projectID: String?
}

// MARK: - 错误

enum ADCParseError: Error, Equatable {
    case invalidJSON
    case missingField(String)
}

// MARK: - 纯函数解析

/// 从 ADC JSON 字典解析 ADCParsedInfo（纯函数，无副作用）
func parseADC(from json: [String: Any]) throws -> ADCParsedInfo {
    guard let clientEmail = json["client_email"] as? String else {
        throw ADCParseError.missingField("client_email")
    }
    guard let privateKey = json["private_key"] as? String else {
        throw ADCParseError.missingField("private_key")
    }
    guard let tokenURI = json["token_uri"] as? String else {
        throw ADCParseError.missingField("token_uri")
    }

    let projectID = json["project_id"] as? String

    return ADCParsedInfo(
        clientEmail: clientEmail,
        privateKey: privateKey,
        tokenURI: tokenURI,
        projectID: projectID
    )
}
```

- [ ] **Step 5: 运行测试验证通过**

```bash
cd /Users/jia.xia/development/TalkFlow && xcodebuild test -project TalkFlow.xcodeproj -scheme TalkFlow -destination 'platform=macOS' -only-testing:TalkFlowTests/ADCParserTests 2>&1 | tail -3
```
预期: `** TEST SUCCEEDED **`

- [ ] **Step 6: 注册源文件到 Xcode 项目**

在 `project.pbxproj` 中添加 `ADCParser.swift` 的 PBXFileReference、PBXBuildFile、PBXGroup 条目。

- [ ] **Step 7: 全量测试 + 提交**

```bash
cd /Users/jia.xia/development/TalkFlow && make test 2>&1 | tail -3
git add TalkFlow/Utils/ADCParser.swift TalkFlowTests/Utils/ADCParserTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ADCParsedInfo + parseADC 纯函数解析 ADC JSON"
```

---

### Task 2: ADCLoaderIO — 读 ADC 文件

**Files:**
- Create: `TalkFlow/IO/ADCLoaderIO.swift`

- [ ] **Step 1: 实现 impureLoadADCFromDefaultPath**

```swift
// TalkFlow/IO/ADCLoaderIO.swift
import Foundation

// MARK: - ADC 文件加载（副作用）

/// 从默认路径 ~/.config/gcloud/application_default_credentials.json 加载 ADC
/// 文件不存在或解析失败 → nil
func impureLoadADCFromDefaultPath() -> ADCParsedInfo? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let adcPath = home.appendingPathComponent(".config/gcloud/application_default_credentials.json")

    guard FileManager.default.fileExists(atPath: adcPath.path) else {
        print("[ADC] ADC 文件不存在: \(adcPath.path)")
        return nil
    }

    let data: Data
    do {
        data = try Data(contentsOf: adcPath)
    } catch {
        print("[ADC] 读取 ADC 文件失败: \(error.localizedDescription)")
        return nil
    }

    let json: [String: Any]
    do {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[ADC] ADC JSON 格式错误")
            return nil
        }
        json = dict
    } catch {
        print("[ADC] ADC JSON 解析失败: \(error.localizedDescription)")
        return nil
    }

    do {
        return try parseADC(from: json)
    } catch {
        print("[ADC] ADC 解析失败: \(error)")
        return nil
    }
}
```

- [ ] **Step 2: 注册到 Xcode 项目**

在 `project.pbxproj` 中添加 `ADCLoaderIO.swift` 的 PBXFileReference、PBXBuildFile、PBXGroup 条目（放入 `TalkFlow/IO/` group）。

- [ ] **Step 3: 编译验证 + 提交**

```bash
cd /Users/jia.xia/development/TalkFlow && make test 2>&1 | tail -3
git add TalkFlow/IO/ADCLoaderIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ADCLoaderIO 从默认路径加载 ADC 文件"
```

---

### Task 3: ProviderError.displayMessage 扩展

**Files:**
- Modify: `TalkFlow/IO/ProviderIO.swift`

- [ ] **Step 1: 添加 displayMessage 计算属性**

在 `TalkFlow/IO/ProviderIO.swift` 的 `ProviderError` enum 定义后添加：

```swift
// MARK: - ProviderError 显示文本

extension ProviderError {
    /// 面向用户的错误描述
    var displayMessage: String {
        switch self {
        case .authenticationFailed(let msg):
            return "认证失败: \(msg)"
        case .networkError(let msg):
            return "网络错误: \(msg)"
        case .apiError(let code, let msg):
            return "API 错误 (\(code)): \(msg)"
        case .responseParsingFailed(let msg):
            return "响应解析失败: \(msg)"
        }
    }
}
```

- [ ] **Step 2: 编译验证 + 提交**

```bash
cd /Users/jia.xia/development/TalkFlow && make test 2>&1 | tail -3
git add TalkFlow/IO/ProviderIO.swift
git commit -m "feat: ProviderError.displayMessage 扩展"
```

---

### Task 4: ModelSettingsView 卡片内容视图

**Files:**
- Create: `TalkFlow/Views/ModelSettingsView.swift`

- [ ] **Step 1: 实现 ModelSettingsView**

```swift
// TalkFlow/Views/ModelSettingsView.swift
import AppKit

// MARK: - 模型服务商

enum ModelProvider: String, CaseIterable {
    case vertexAI = "Vertex AI"
}

// MARK: - 连接测试状态

enum ConnectionTestStatus: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

// MARK: - 模型设置视图

/// 模型卡片内容 — 下拉选择 + Vertex AI 配置 + 连接测试
/// init 仅赋值（rule 16），setUp() 显式触发副作用
final class ModelSettingsView: NSView {

    // MARK: - 可变状态

    private var selectedProvider: ModelProvider = .vertexAI
    private var adcInfo: ADCParsedInfo? = nil
    private var connectionStatus: ConnectionTestStatus = .idle
    private var isTesting = false

    // MARK: - 子视图

    private let providerLabel = NSTextField(labelWithString: "模型服务:")
    private let providerDropdown = NSPopUpButton()

    // Vertex AI 配置容器（条件显示）
    private let vertexAIContainer = NSView()
    private let vertexAISeparator = NSBox()
    private let projectIDLabel = NSTextField(labelWithString: "Project ID:")
    private let projectIDField = NSTextField()
    private let modelNameLabel = NSTextField(labelWithString: "模型名称:")
    private let modelNameField = NSTextField()
    private let testButton = NSButton(title: "测试连接", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

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
        impureDetectADC()
        impureRender()
    }

    // MARK: - ⚠️ UI 构建

    private func impureSetupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        // — 模型服务选择 —
        providerLabel.font = NSFont.systemFont(ofSize: 13)
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(providerLabel)

        providerDropdown.addItems(withTitles: ModelProvider.allCases.map(\.rawValue))
        providerDropdown.font = NSFont.systemFont(ofSize: 13)
        providerDropdown.target = self
        providerDropdown.action = #selector(impureProviderChanged)
        providerDropdown.translatesAutoresizingMaskIntoConstraints = false
        addSubview(providerDropdown)

        // — Vertex AI 配置区 —
        vertexAIContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vertexAIContainer)

        vertexAISeparator.boxType = .separator
        vertexAISeparator.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(vertexAISeparator)

        projectIDLabel.font = NSFont.systemFont(ofSize: 12)
        projectIDLabel.textColor = .secondaryLabelColor
        projectIDLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(projectIDLabel)

        projectIDField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        projectIDField.isEditable = true
        projectIDField.placeholderString = "输入 Google Cloud Project ID"
        projectIDField.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(projectIDField)

        modelNameLabel.font = NSFont.systemFont(ofSize: 12)
        modelNameLabel.textColor = .secondaryLabelColor
        modelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(modelNameLabel)

        modelNameField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        modelNameField.isEditable = true
        modelNameField.placeholderString = "gemini-2.0-flash-001"
        modelNameField.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(modelNameField)

        testButton.bezelStyle = .rounded
        testButton.font = NSFont.systemFont(ofSize: 13)
        testButton.target = self
        testButton.action = #selector(impureTestConnection)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(testButton)

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        vertexAIContainer.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // 顶层：providerLabel + providerDropdown
            providerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            providerLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            providerLabel.centerYAnchor.constraint(equalTo: providerDropdown.centerYAnchor),

            providerDropdown.leadingAnchor.constraint(equalTo: providerLabel.trailingAnchor, constant: 12),
            providerDropdown.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            providerDropdown.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            // vertexAIContainer
            vertexAIContainer.topAnchor.constraint(equalTo: providerDropdown.bottomAnchor, constant: 12),
            vertexAIContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            vertexAIContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            vertexAIContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 分隔线
            vertexAISeparator.topAnchor.constraint(equalTo: vertexAIContainer.topAnchor),
            vertexAISeparator.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            vertexAISeparator.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),

            // Project ID
            projectIDLabel.topAnchor.constraint(equalTo: vertexAISeparator.bottomAnchor, constant: 8),
            projectIDLabel.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),

            projectIDField.topAnchor.constraint(equalTo: projectIDLabel.bottomAnchor, constant: 4),
            projectIDField.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            projectIDField.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),

            // 模型名称
            modelNameLabel.topAnchor.constraint(equalTo: projectIDField.bottomAnchor, constant: 12),
            modelNameLabel.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),

            modelNameField.topAnchor.constraint(equalTo: modelNameLabel.bottomAnchor, constant: 4),
            modelNameField.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            modelNameField.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),

            // 测试按钮
            testButton.topAnchor.constraint(equalTo: modelNameField.bottomAnchor, constant: 12),
            testButton.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),

            // 状态标签
            statusLabel.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: vertexAIContainer.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: vertexAIContainer.trailingAnchor),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: vertexAIContainer.bottomAnchor),
        ])
    }

    // MARK: - ⚠️ ADC 检测

    private func impureDetectADC() {
        guard let adc = impureLoadADCFromDefaultPath() else {
            print("[ModelSettings] ADC 未检测到")
            adcInfo = nil
            return
        }
        adcInfo = adc
        print("[ModelSettings] ADC 检测成功 — clientEmail: \(adc.clientEmail)")

        if let pid = adc.projectID {
            projectIDField.stringValue = pid
            projectIDField.isEditable = false
        } else {
            projectIDField.placeholderString = "未检测到 — 请手动输入 Project ID"
        }
    }

    // MARK: - ⚠️ 事件处理

    @objc private func impureProviderChanged() {
        guard let title = providerDropdown.selectedItem?.title,
              let provider = ModelProvider(rawValue: title) else { return }
        selectedProvider = provider
        impureRender()
    }

    @objc private func impureTestConnection() {
        guard !isTesting else { return }

        let projectID = projectIDField.stringValue.trimmingCharacters(in: .whitespaces)
        let modelName = modelNameField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !projectID.isEmpty, !modelName.isEmpty else {
            connectionStatus = .failure("请填写 Project ID 和模型名称")
            impureRender()
            return
        }

        guard let adc = adcInfo else {
            connectionStatus = .failure("未检测到 ADC 凭据，请运行 gcloud auth application-default login")
            impureRender()
            return
        }

        isTesting = true
        connectionStatus = .testing
        impureRender()

        let sa = ServiceAccount(
            projectID: projectID,
            privateKey: adc.privateKey,
            clientEmail: adc.clientEmail,
            tokenURI: adc.tokenURI
        )
        let tokenProvider = JWTTokenProvider(sa: sa)
        let provider = VertexAIIO(
            tokenProvider: tokenProvider,
            projectID: projectID,
            location: "us-central1",
            model: modelName,
            promptConfig: PromptConfig(defaultPrompt: "", userSupplement: "")
        )

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let request = ChatRequest(messages: [ChatMessage(role: .user, content: "hi")])
                let response = try await provider.send(request)
                await MainActor.run {
                    self.isTesting = false
                    self.connectionStatus = .success("✅ 连接成功")
                    self.impureRender()
                    print("[ModelSettings] 连接测试成功 — 响应: \(response.content.prefix(50))")
                }
            } catch let error as ProviderError {
                await MainActor.run {
                    self.isTesting = false
                    self.connectionStatus = .failure("❌ \(error.displayMessage)")
                    self.impureRender()
                }
            } catch {
                await MainActor.run {
                    self.isTesting = false
                    self.connectionStatus = .failure("❌ 未知错误: \(error.localizedDescription)")
                    self.impureRender()
                }
            }
        }
    }

    // MARK: - ⚠️ 渲染

    private func impureRender() {
        let showVertexAI = selectedProvider == .vertexAI
        vertexAIContainer.isHidden = !showVertexAI

        switch connectionStatus {
        case .idle:
            statusLabel.stringValue = ""
            statusLabel.textColor = .secondaryLabelColor
            testButton.isEnabled = true
            testButton.title = "测试连接"
        case .testing:
            statusLabel.stringValue = "⏳ 正在测试连接..."
            statusLabel.textColor = .secondaryLabelColor
            testButton.isEnabled = false
            testButton.title = "测试中..."
        case .success(let msg):
            statusLabel.stringValue = msg
            statusLabel.textColor = .systemGreen
            testButton.isEnabled = true
            testButton.title = "测试连接"
        case .failure(let msg):
            statusLabel.stringValue = msg
            statusLabel.textColor = .systemRed
            testButton.isEnabled = true
            testButton.title = "测试连接"
        }
    }
}
```

- [ ] **Step 2: 注册到 Xcode 项目**

在 `project.pbxproj` 中添加 `ModelSettingsView.swift` 的 PBXFileReference、PBXBuildFile、PBXGroup 条目（放入 `TalkFlow/Views/` group）。

- [ ] **Step 3: 编译验证 + 提交**

```bash
cd /Users/jia.xia/development/TalkFlow && make test 2>&1 | tail -3
git add TalkFlow/Views/ModelSettingsView.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: ModelSettingsView 模型卡片视图（下拉 + 配置 + 连接测试）"
```

---

### Task 5: AppDelegate 集成模型卡片

**Files:**
- Modify: `TalkFlow/AppDelegate.swift`

- [ ] **Step 1: 在 AppDelegate 中添加模型卡片**

在 `impureShowMainWindow()` 方法的 `transcriptionCard` 约束后添加：

```swift
// 模型配置卡片
let modelView = ModelSettingsView()
modelView.setUp()
let modelCard = CardView(title: "模型", contentView: modelView)
modelCard.setUp()
rootView.addSubview(modelCard)
```

并在约束数组中 `transcriptionCard` 约束后添加：

```swift
// 模型卡片：位于转写卡片下方
modelCard.topAnchor.constraint(equalTo: transcriptionCard.bottomAnchor, constant: 16),
modelCard.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
modelCard.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
modelCard.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -20),
```

- [ ] **Step 2: 编译验证 + 提交**

```bash
cd /Users/jia.xia/development/TalkFlow && make test 2>&1 | tail -3
git add TalkFlow/AppDelegate.swift
git commit -m "feat: AppDelegate 集成模型配置卡片"
```

---
