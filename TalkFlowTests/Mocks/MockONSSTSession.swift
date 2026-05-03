// TalkFlowTests/Mocks/
import Foundation

/// 模拟 ONNX 推理返回值
struct MockONNXOutput {
    let tokenIds: [Int32]
}

/// 捕获 ONNX 推理输入参数
struct CapturedONNXInput {
    var feats: [Float] = []
    var featsLen: Int = 0
    var language: Int = 0
    var textnorm: Int = 0
}
