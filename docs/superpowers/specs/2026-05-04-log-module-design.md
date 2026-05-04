# 日志模块设计

日期：2026-05-04

## 概述

为 TalkFlow 增加日志模块，将现有 `print()` 调用替换为结构化日志写入，并提供日志查看器 UI。同时新增启动时自动清理两周前日志和录音文件的机制。

## 需求

1. 日志写入项目根目录下 `logs/` 文件夹（实际路径为 `~/Library/Application Support/TalkFlow/Logs/`）
2. 双文件滚动策略：始终写入 `latest.log`，跨天归档为 `YYYY-MM-DD.log`
3. 四级日志：`debug`、`info`、`warning`、`error`
4. JSON Lines 存储格式
5. 日志查看器：新窗口，左右分栏（左列表右详情），checkbox 勾选 + 批量复制
6. 主窗体底部新增日志卡片，显示错误/警告计数
7. 启动时清理 14 天前的日志文件（按文件名日期）和录音文件（按文件名日期）

## 数据模型

### LogEntry (`Utils/LogEntry.swift`)

```swift
enum LogLevel: String, Codable, CaseIterable {
    case debug, info, warning, error
}

struct LogEntry: Codable, Equatable {
    let timestamp: Date
    let level: LogLevel
    let tag: String       // e.g. "Pipeline", "STT", "ADC"
    let message: String
}
```

JSON Lines 存储格式：
```json
{"timestamp":"2026-05-04T08:32:01.234Z","level":"info","tag":"Pipeline","message":"开始 STT 转写..."}
```

## 架构

所有副作用集中在 IO 层，纯数据模型在 Utils 层。

### IO 层

#### LogFileIO (`IO/LogFileIO.swift`)

协议：
```swift
protocol LogFileIO {
    var logsDirectory: URL { get }
    func append(_ entry: LogEntry)
    func entries(from file: URL) -> [LogEntry]
    func logFiles() -> [URL]
    func rotateIfNeeded()
    func cleanOldLogs(before days: Int)
}
```

实现 `DefaultLogFileIO`：
- `logsDirectory` → `~/Library/Application Support/TalkFlow/Logs/`
- `append` → 检查跨天，是则 rotate → 追加 JSON 行 + `\n`
- `rotate` → `latest.log` 重命名为 `YYYY-MM-DD.log`，新建 `latest.log`
- `entries` → 逐行解析 JSON，跳过无效行
- `logFiles` → 扫描目录，`latest.log` 排最前，其余按日期降序
- `cleanOldLogs` → 按文件名日期筛选，`FileManager.removeItem`

#### LoggerIO (`IO/LoggerIO.swift`)

协议：
```swift
protocol LoggerIO {
    func log(_ level: LogLevel, tag: String, _ message: String)
}

extension LoggerIO {
    func debug(tag: String, _ msg: String)
    func info(tag: String, _ msg: String)
    func warning(tag: String, _ msg: String)
    func error(tag: String, _ msg: String)
}
```

实现 `FileLoggerIO`：组合 `LogFileIO`，构造 `LogEntry`，调 `append`。

工厂函数：
```swift
func impureMakeLogger() -> LoggerIO {
    FileLoggerIO(fileIO: DefaultLogFileIO())
}
```

#### 清理函数 (`IO/FilePathIO.swift`)

```swift
func cleanOldRecordings(fileIO: FilePathIO, before days: Int)
```

- 按文件名日期（`recordingFilename` 格式：`yyyy-MM-dd'T'HH-mm-ss_xxx.m4a`）提取日期
- 与截止日期比较，删除过期文件
- 参数化天数，配合日志清理在 AppDelegate 启动时调用

### Views 层

#### LogCardView (`Views/LogCardView.swift`)

- 复用 `CardView`，标题"日志"
- 内容区显示最近错误数/警告数（运行时从 `LogFileIO` 获取）
- "打开"按钮 → 打开 `LogViewerWindow`

#### LogViewerWindow (`Views/LogViewerWindow.swift`)

- 独立 `NSWindow`，含 `LogEntryListView`（左）和 `LogEntryDetailView`（右）
- 窗口关闭时终止，不常驻
- 类似 `PipelineStatusWindow` 的管理模式

#### LogEntryListView (`Views/LogEntryListView.swift`)

- 顶部：`NSPopUpButton` 切换文件（`latest.log` + 归档文件列表），默认 `latest.log`
- 级别筛选：四色 toggle 按钮（debug/info/warning/error），默认全选
- 列表：`NSTableView`，列 = [checkbox, 级别图标, 时间, 标签, 消息摘要]
- 底部工具栏："复制勾选 (N)" + "全选" + 条目计数
- 复制逻辑：勾选条目按时间排序 → 拼接纯文本 → `NSPasteboard.general.setString`

#### LogEntryDetailView (`Views/LogEntryDetailView.swift`)

- 级别 badge
- 完整时间戳
- 标签 + 来源文件名
- `NSTextView` 展示消息体（支持选择/复制长文本）

### AppDelegate 改动

1. 持有 `private let logger: LoggerIO = impureMakeLogger()`
2. 替换所有 `print("[Tag] ...")` → `logger.info(tag: "Tag", "...")`（按语义分配级别）
3. `applicationDidFinishLaunching` 末尾新增清理调用：
   ```swift
   let logFileIO = DefaultLogFileIO()
   logFileIO.cleanOldLogs(before: 14)
   let filePathIO = AppSupportFilePathIO()
   cleanOldRecordings(fileIO: filePathIO, before: 14)
   ```
4. 主窗体底部新增 `LogCardView`

## print() 到日志级别的映射

| 原 print 模式 | 级别 | 示例 |
|--------------|------|------|
| 流程追踪、正常完成 | `info` | `[Pipeline] 开始 STT 转写...`、`润色完成` |
| 失败、异常、降级 | `error` | `[Pipeline] 润色失败`、`STT 失败` |
| 静音、跳过 | `info` | `静音 — 跳过粘贴` |
| 调试细节（推理 token 数等） | `debug` | `[STT] 推理: 45 token IDs` |
| 降级/溶断（非致命） | `warning` | `润色失败，降级使用原文`（区分超时等预期内失败） |

## 文件结构

```
TalkFlow/
├── Utils/
│   └── LogEntry.swift          (新增)
├── IO/
│   ├── LogFileIO.swift         (新增)
│   ├── LoggerIO.swift          (新增)
│   └── FilePathIO.swift        (修改: 新增 cleanOldRecordings)
├── Views/
│   ├── LogCardView.swift       (新增)
│   ├── LogViewerWindow.swift   (新增)
│   ├── LogEntryListView.swift  (新增)
│   └── LogEntryDetailView.swift (新增)
└── AppDelegate.swift           (修改)
```

## 测试要点

- `LogEntry` Codable 往返
- `LogFileIO` 文件追加、滚动、清理
- `cleanOldRecordings` 按文件名日期过滤
- 日志级别便捷方法调用
- 文件日期提取纯函数（从文件名解析日期）
