# Pipeline 状态浮窗升级 — 设计文档

## 目标

将录音阶段专用的浮动状态窗，扩展为覆盖"录音 → 转写 → 粘贴失败"三阶段的状态指示器。风格参照 TalkShow 项目。

## 架构

### 新增类型

```swift
enum PipelinePhase {
    case recording      // 🔴 计时 + REC
    case transcribing   // 转写中动画
    case pasteFailed    // ⚠️ 粘贴失败提示
}
```

### 组件变更

| 当前 | 改为 | 变更说明 |
|---|---|---|
| `RecordingStatusView` | `PipelineStatusView` | 增加 `render(phase:)` 多态渲染 |
| `RecordingStatusWindow` | `PipelineStatusWindow` | `show(phase:)` 替代 `show()`，内部管理定时器生命周期 |

### 视图设计

所有阶段共享：
- 药丸形状（`cornerRadius: 22`）
- 深色毛玻璃底色（`rgba(30,30,30,0.92)` + `blur(20px)`）
- 右侧 ✕ 关闭按钮
- 等宽字体（SF Mono）

#### `.recording`

```
┌─────────────────────────┐
│ ◉ 00:12  REC        ╳  │
└─────────────────────────┘
```
- 红色呼吸圈动画（SF Symbol `circle.fill` + opacity CABasicAnimation）
- 等宽计时器（`00:00` 格式）
- "REC" 标签
- ✕ 按钮 → 取消录音

#### `.transcribing`

```
┌─────────────────────────┐
│ ◌ 转写中...         ╳  │
└─────────────────────────┘
```
- 旋转进度指示器（`NSProgressIndicator` small，indeterminate）
- "转写中..." 青色文字
- ✕ 按钮 → 中止转写（取消 task）

#### `.pasteFailed`

```
┌───────────────────────────────────┐
│ ⚠ 自动粘贴失败，请手动粘贴    ╳  │
└───────────────────────────────────┘
```
- 琥珀色警告图标（SF Symbol `exclamationmark.triangle`）
- 琥珀色提示文字
- ✕ 按钮 → 立即关闭
- **3 秒后自动淡出消失**

### `PipelineStatusWindow` 公共接口

```swift
final class PipelineStatusWindow {
    func show(phase: PipelinePhase)   // 创建/更新面板
    func updateTime(_ ti: TimeInterval) // 仅 recording 有效
    func dismiss()                     // 淡出 + close
}
```

- `show(phase:)` 若面板已显示则切换内容，否则创建新面板
- `.recording` 时启动 `Timer.scheduledTimer(0.1s)` 计时
- 非 `.recording` 阶段自动停计时器
- `dismiss()` 设置 alpha=0 动画 200ms 后 close

### AppDelegate 集成点

| 管道事件 | 浮窗动作 |
|---|---|
| `impureStartRecording` | `statusWindow.show(.recording)` |
| `impureStopRecording` | `statusWindow.show(.transcribing)` |
| `.speech` + 粘贴成功 | `statusWindow.dismiss()` |
| `.speech` + 粘贴失败 | `statusWindow.show(.pasteFailed)` → 3 秒后 `dismiss()` |
| `.silence` | `statusWindow.dismiss()` |
| `.failure` | `statusWindow.show(.pasteFailed)` → 3 秒后 `dismiss()` |
| `impureCancelRecording` | `statusWindow.dismiss()` |
| ✕ 按钮点击（recording） | `impureCancelRecording()` |
| ✕ 按钮点击（transcribing） | 取消转写 task + `dismiss()` |

## 转写中止

`.transcribing` 阶段点击 ✕ 需要中止异步转写任务。方案：

- `onRecordingComplete` 闭包内使用 `Task { ... }`，保存为 `var sttTask: Task<Void, Never>?`
- ✕ 按钮回调调用 `sttTask?.cancel()` + `dismiss()`

## 测试策略

- `PipelineStatusView` 为纯视图，手动测试（NSView 不便单元测试）
- `PipelinePhase` enum 穷尽性 switch 编译期验证
- AppDelegate 集成点通过运行验证
- 3 秒自动消失用 `asyncAfter` 实现，行为简单无需专项测试

## 不改动的部分

- `PipelineStatusView` 保持 `init` 纯净，`setUp()` 触发副作用（遵循 rule 16）
- NSPanel floating 属性、level、collectionBehavior 沿用现有配置
- 不引入额外协议抽象（单文件范围内简单够用）
