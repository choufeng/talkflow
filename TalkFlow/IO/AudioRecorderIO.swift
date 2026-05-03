import Foundation
import AVFoundation

// MARK: - 协议

protocol AudioRecorderIO {
    /// 是否正在录音
    var isRecording: Bool { get }
    /// 当前录音目标 URL（停止后可获取保存位置）
    var recordingURL: URL? { get }
    /// 开始录音到目标 URL
    func startRecording(to url: URL) throws
    /// 停止录音 → 返回录音时长（秒）
    func stopRecording() -> TimeInterval
    /// 取消录音（不保存文件）
    func cancelRecording()
}

// MARK: - 实现

final class AVAudioRecorderIO: NSObject, AudioRecorderIO {

    private var recorder: AVAudioRecorder?
    private var recordingStartDate: Date?
    private var _recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    var recordingURL: URL? {
        _recordingURL
    }

    func startRecording(to url: URL) throws {
        if recorder?.isRecording == true {
            recorder?.stop()
        }

        _recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.delegate = self
        let started = rec.record()
        guard started else {
            _recordingURL = nil
            throw RecordingError.couldNotStart
        }
        recorder = rec
        recordingStartDate = Date()
    }

    func stopRecording() -> TimeInterval {
        guard let rec = recorder, let start = recordingStartDate else {
            return 0
        }
        rec.stop()
        recorder = nil
        recordingStartDate = nil
        return durationFrom(startDate: start, endDate: Date())
    }

    func cancelRecording() {
        guard let rec = recorder else { return }
        rec.stop()

        if let url = _recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        recorder = nil
        recordingStartDate = nil
        _recordingURL = nil
    }
}

// MARK: - AVAudioRecorderDelegate

extension AVAudioRecorderIO: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            recordingStartDate = nil
            self.recorder = nil
        }
    }
}

// MARK: - 错误类型

enum RecordingError: Error, Equatable {
    case couldNotStart
}
