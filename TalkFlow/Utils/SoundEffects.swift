import AppKit

enum SoundEffect {
    case hotkeyStart
    case cancel
    case complete

    private var systemSoundName: NSSound.Name {
        switch self {
        case .hotkeyStart: return NSSound.Name("Tink")
        case .cancel: return NSSound.Name("Pop")
        case .complete: return NSSound.Name("Frog")
        }
    }

    func play() {
        if let sound = NSSound(named: systemSoundName) {
            sound.play()
        }
    }
}
