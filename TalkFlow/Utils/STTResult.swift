import Foundation

// MARK: - ADT

enum STTResult: Equatable {
    case silence
    case speech(text: String, language: String)
    case failure(STTError)
}

// MARK: - 错误类型

enum STTError: Error, Equatable {
    case modelNotReady
    case audioDecodeFailed
    case inferenceFailed(String)
}
