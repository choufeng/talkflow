# 快捷键录音 → 转写 → 自动粘贴 设计文档

**日期**: 2026-05-03  
**分支**: `feature/connect`  
**状态**: 待实现

## 目标

用户按下全局快捷键 → 开始录音 → 再次按下结束录音 → SenseVoice 本地转写 → 写入剪贴板 → 自动 Cmd+V 粘贴到当前焦点应用。形成"免动手语音输入到任意文本框"的闭环。

## 前置条件

- ONNX 模型文件 `model_quant.onnx` 已下载至 `TalkFlow/Resources/sensevoice/`（由 `scripts/download-stt-model.sh` 完成）
- `.gitignore` 排除 `model_quant.onnx`（230MB，不纳入版本控制）
- 辅助功能权限已授权（粘贴依赖 `CGEventPost`）

---

## 架构

### 现有管道（已实现）

```
全局快捷键(CarbonHotkeyIO) → Notification
  → AppDelegate.impureHandleHotkeyTrigger
    → 状态机 toggle(RecordingPhase)
      → AudioRecorderIO 录音
      → FilePathIO 文件路径
    → onRecordingComplete(url)
      → SenseVoiceEngineIO.transcribe(url)
      → STTResult.speech → NSPasteboard.general.setString
```

### 新增：PasteIO

```
STTResult.speech(text) →
  1. NSPasteboard.general.setString(text)  // 已有
  2. pasteIO.paste()                       // 新增
    → CGEvent 模拟 Cmd+V
    → 文本粘贴至焦点应用
```

---

## 组件设计

### PasteIO 协议

**文件**: `TalkFlow/IO/PasteIO.swift`

```swift
protocol PasteIO {
    /// 执行粘贴操作（模拟 Cmd+V）
    /// ⚠️ 副作用：发送系统级键盘事件，依赖辅助功能权限
    func paste() -> Bool
}
```

- 返回 `true` 表示事件发送成功（不保证目标应用接收）
- 返回 `false` 表示发送失败（通常因辅助功能权限未授权）

### CGEventPasteIO 实现

**文件**: `TalkFlow/IO/PasteIO.swift`（同文件）

```swift
final class CGEventPasteIO: PasteIO {
    func paste() -> Bool {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        let postDown = down?.post(tap: .cgAnnotatedSessionEventTap)
        let postUp = up?.post(tap: .cgAnnotatedSessionEventTap)
        return (postDown == .success) && (postUp == .success)
    }
}
```

- `0x09` = kVK_ANSI_V（Cmd+V 的 V 键码）
- `tap: .cgAnnotatedSessionEventTap` = 最低权限级别即可发送
- 返回值来自 `CGEventPost` 的 `CGError`

### MockPasteIO

**文件**: `TalkFlowTests/Mocks/MockPasteIO.swift`

```swift
final class MockPasteIO: PasteIO {
    var shouldSucceed = true
    var pasteCallCount = 0

    func paste() -> Bool {
        pasteCallCount += 1
        return shouldSucceed
    }
}
```

### AppDelegate 修改

**文件**: `TalkFlow/AppDelegate.swift`

新增属性：
```swift
private let pasteIO: PasteIO = CGEventPasteIO()
```

修改 `impureSetupSTT` 中的 `onRecordingComplete` 回调 — `.speech` 分支：
```swift
case .speech(let text, let language):
    print("[STT] \(language): \(text)")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    let pasted = self.pasteIO.paste()
    print("[Paste] \(pasted ? "✅" : "❌") pasted to active app")
```

`.silence` 和 `.failure` 分支不变。

---

## 管道流程

```
用户按下快捷键(toggle 1)
  → RecordingPhase.recording(startedAt)
  → AVAudioRecorderIO.startRecording(to: nextRecordingURL())
  → RecordingStatusWindow.show()
  → 显示录音状态 + ESC 取消

用户按下快捷键(toggle 2)
  → 防抖检查(0.5s)
  → RecordingPhase.idle
  → AVAudioRecorderIO.stopRecording()
  → 检查录音时长 >= 1.0s
  → RecordingStatusWindow.dismiss()
  → onRecordingComplete(url)

onRecordingComplete:
  → SenseVoiceEngineIO.transcribe(url) async
  → switch result:
    case .speech(text, language):
      → NSPasteboard.general.setString(text)
      → CGEventPasteIO.paste() → Cmd+V
      → 日志: ✅ pasted
    case .silence:
      → 日志: Silence — ignored
    case .failure(let error):
      → 日志: Error: \(error)
```

---

## 错误处理与边界

| 场景 | 行为 |
|---|---|
| 辅助功能未授权 | `paste()` 返回 false，文本在剪贴板，用户手动 Cmd+V |
| 剪贴板为空时触发粘贴 | 无害空操作 |
| 连续快速触发 | 防抖 0.5s，每轮独立 |
| STT 返回 `.silence` | 不写剪贴板，不粘贴 |
| STT 返回 `.failure` | 不写剪贴板，不粘贴 |
| `paste()` 失败 | 文本已在剪贴板，用户可手动 Cmd+V |

---

## 文件变更清单

| 文件 | 操作 |
|---|---|
| `TalkFlow/IO/PasteIO.swift` | 新增（协议 + 实现） |
| `TalkFlowTests/IO/PasteIOTests.swift` | 新增（单元测试） |
| `TalkFlowTests/Mocks/MockPasteIO.swift` | 新增（Mock） |
| `TalkFlow/AppDelegate.swift` | 修改（注入 pasteIO，.speech 分支追加粘贴） |

---

## 测试计划

### PasteIOTests（6 个用例）

1. `test_paste_success` — Mock 返回 true
2. `test_paste_failure` — Mock 返回 false
3. `test_pipeline_pasteCalledAfterSTTSpeech` — 验证 .speech 分支后粘贴被调用
4. `test_pipeline_pasteNotCalledOnSilence` — 静音不触发粘贴
5. `test_pipeline_pasteNotCalledOnFailure` — STT 失败不触发粘贴
6. `test_pipeline_clipboardWrittenBeforePaste` — 验证剪贴板先于粘贴写入

---

## 项目铁律合规检查

- ✅ IO 协议隔离副作用（PasteIO）
- ✅ 纯数据类型不变（无改动）
- ✅ 副作用标记明确（`paste()` 标注 ⚠️）
- ✅ 构造无副作用（CGEventPasteIO init 仅赋值）
- ✅ Mock 可替换实现
- ✅ 已有防抖逻辑不变
