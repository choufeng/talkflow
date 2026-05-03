import AppKit
import Carbon
import os.log

// MARK: - 日志

private let log = OSLog(subsystem: "im.xiajia.TalkFlow", category: "Hotkey")

private func hotkeyLog(_ msg: String) {
    os_log("%{public}@", log: log, type: .info, msg)
    print("[TalkFlow.Hotkey] \(msg)")
}

// MARK: - 协议抽象

protocol HotkeyIO {
    /// ⚠️ 从 UserDefaults 加载已保存的快捷键绑定
    func loadBinding() -> HotkeyBinding?

    /// ⚠️ 保存快捷键绑定到 UserDefaults
    func saveBinding(_ binding: HotkeyBinding)

    /// ⚠️ 清除保存的快捷键绑定
    func clearBinding()

    /// ⚠️ 注册全局快捷键 → 返回是否成功
    func registerHotkey(_ binding: HotkeyBinding) -> Bool

    /// ⚠️ 注销当前全局快捷键
    func unregisterHotkey()

    /// ⚠️ 开始录制快捷键（本地事件监听），捕获后回调 onCaptured
    func startRecording(onCaptured: @escaping (HotkeyBinding) -> Void)

    /// ⚠️ 停止录制
    func stopRecording()
}

// MARK: - ⚠️ Carbon 全局快捷键 IO 实现

/// 基于 Carbon RegisterEventHotKey 的全局快捷键实现
/// 包含：UserDefaults 存储 + 系统级注册 + 本地录制
final class CarbonHotkeyIO: HotkeyIO {

    private let storageKey = "TalkFlow_HotkeyBinding"

    // Carbon 热键引用
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // 录制状态
    private var recordingMonitor: Any?
    private let hotkeyID = EventHotKeyID(signature: 0x54464C4F, id: 1) // "TFLO"

    deinit {
        stopRecording()
        unregisterHotkey()
    }

    // MARK: - 存储

    func loadBinding() -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            hotkeyLog("未找到已保存的快捷键绑定")
            return nil
        }
        do {
            let binding = try JSONDecoder().decode(HotkeyBinding.self, from: data)
            hotkeyLog("加载已保存的快捷键: \(formatHotkey(binding))")
            return binding
        } catch {
            hotkeyLog("⚠️ 快捷键绑定解码失败: \(error.localizedDescription)")
            return nil
        }
    }

    func saveBinding(_ binding: HotkeyBinding) {
        do {
            let data = try JSONEncoder().encode(binding)
            UserDefaults.standard.set(data, forKey: storageKey)
            hotkeyLog("保存快捷键: \(formatHotkey(binding))")
        } catch {
            hotkeyLog("⚠️ 快捷键绑定编码失败: \(error.localizedDescription)")
        }
    }

    func clearBinding() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        hotkeyLog("清除已保存的快捷键")
    }

    // MARK: - 全局注册

    func registerHotkey(_ binding: HotkeyBinding) -> Bool {
        // 先注销旧的热键
        unregisterHotkey()

        let modifiers = UInt32(binding.modifiers)
        let keyCode = UInt32(binding.keyCode)

        hotkeyLog("正在注册全局快捷键: \(formatHotkey(binding)) (keyCode=\(keyCode), modifiers=0x\(String(modifiers, radix: 16)))")

        // 安装事件处理器（仅首次）
        if eventHandlerRef == nil {
            var handlerRef: EventHandlerRef?
            var eventSpec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(
                GetEventMonitorTarget(),
                CarbonHotkeyIO.eventHandlerCallback,
                1,
                &eventSpec,
                selfPtr,
                &handlerRef
            )
            if status != noErr {
                hotkeyLog("❌ 安装事件处理器失败 (OSStatus: \(status))")
                return false
            }
            eventHandlerRef = handlerRef
            hotkeyLog("事件处理器安装成功")
        }

        // 注册热键
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetEventMonitorTarget(),
            0,
            &ref
        )
        if status != noErr {
            hotkeyLog("❌ RegisterEventHotKey 失败 (OSStatus: \(status))")
            return false
        }
        hotkeyRef = ref
        hotkeyLog("✅ 全局快捷键注册成功")
        return true
    }

    func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
            hotkeyLog("已注销全局快捷键")
        }
    }

    // MARK: - 录制

    func startRecording(onCaptured: @escaping (HotkeyBinding) -> Void) {
        stopRecording()
        hotkeyLog("开始录制快捷键...")

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let carbonMods = nseventModifiersToCarbon(event.modifierFlags)
            // 要求至少一个修饰键 + 一个非修饰键
            guard carbonMods != 0 else { return event }
            let binding = HotkeyBinding(keyCode: event.keyCode, modifiers: carbonMods)
            hotkeyLog("捕获快捷键: \(formatHotkey(binding))")

            self.stopRecording()
            onCaptured(binding)
            return nil // 吞掉事件，不传递
        }
    }

    func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
            hotkeyLog("停止录制")
        }
    }

    // MARK: - Carbon 回调

    private static let eventHandlerCallback: EventHandlerUPP = { _, event, userData in
        guard let userData = userData else { return noErr }
        let io = Unmanaged<CarbonHotkeyIO>.fromOpaque(userData).takeUnretainedValue()
        hotkeyLog("🔥 全局快捷键触发！")
        // 触发转写逻辑（此处由 AppDelegate 订阅）
        NotificationCenter.default.post(name: .talkFlowHotkeyTriggered, object: nil)
        return noErr
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let talkFlowHotkeyTriggered = Notification.Name("TalkFlowHotkeyTriggered")
}
