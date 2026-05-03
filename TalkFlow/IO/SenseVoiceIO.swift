import Foundation

// MARK: - 协议

protocol SenseVoiceIO {
    /// 模型是否已就绪（ONNX 模型已加载）
    var isModelReady: Bool { get }

    /// 转写音频文件 → STTResult
    func transcribe(url: URL) async throws -> STTResult
}
