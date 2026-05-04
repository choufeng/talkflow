import Foundation
import AVFoundation

// MARK: - 实现

struct SenseVoiceEngineIO: SenseVoiceIO {

    // MARK: - 配置常量

    private let targetSampleRate: Double = 16000
    private let minSampleCount = 4800

    // MARK: - 不可变状态

    let isModelReady: Bool = false
    let cmvnMeans: [Double]
    let cmvnVars: [Double]
    let tokens: [Int: String]

    // MARK: - 公开 API

    func transcribe(url: URL) async throws -> STTResult {
        let (samples, sampleRate) = try decodeAudio(url: url)
        let log = impureMakeLogger()
        log.debug(tag: "STT", "解码: \(samples.count) samples @ \(sampleRate)Hz")
        let resampled = resampleTo16k(samples: samples, srcRate: sampleRate)
        log.debug(tag: "STT", "重采样: \(resampled.count) samples @ 16000Hz")

        guard !classifySilence(samples: resampled) else {
            log.info(tag: "STT", "静音判定: 采样数 \(resampled.count) < 4800")
            return .silence
        }

        let fbank = extractFbank(waveform: resampled)
        log.debug(tag: "STT", "Fbank: \(fbank.count) frames x \(fbank.first?.count ?? 0) dims")
        guard !fbank.isEmpty else { log.debug(tag: "STT", "Fbank isEmpty"); return .silence }

        let lfr = applyLFR(fbank)
        log.debug(tag: "STT", "LFR: \(lfr.count) frames x \(lfr.first?.count ?? 0) dims")
        guard !lfr.isEmpty else { log.debug(tag: "STT", "LFR isEmpty"); return .silence }

        let normalized = applyCMVN(lfr, means: cmvnMeans, vars: cmvnVars)
        log.debug(tag: "STT", "CMVN done, starting inference...")

        let tokenIds = try runInference(feats: normalized, featsLen: Int32(lfr.count))
        log.debug(tag: "STT", "推理: \(tokenIds.count) token IDs")
        let text = decodeTokenIds(tokenIds, tokens: tokens)
        log.info(tag: "STT", "解码: \"\(text)\"")
        let cleaned = postprocess(text)
        log.debug(tag: "STT", "后处理: \"\(cleaned)\"")

        return cleaned.isEmpty ? .silence : .speech(text: cleaned, language: "auto")
    }

    // MARK: - 纯函数：音频解码（副作用明确：文件 IO）

    func decodeAudio(url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw STTError.audioDecodeFailed
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw STTError.audioDecodeFailed
        }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        return (samples, format.sampleRate)
    }

    // MARK: - 纯函数

    func classifySilence(samples: [Float]) -> Bool {
        samples.count < minSampleCount
    }

    func resampleTo16k(samples: [Float], srcRate: Double) -> [Float] {
        guard abs(srcRate - targetSampleRate) > 1.0 else { return samples }
        let ratio = targetSampleRate / srcRate
        let outputCount = Int(Double(samples.count) * ratio)
        var result = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let i0 = Int(srcIndex)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(srcIndex - Double(i0))
            result[i] = samples[i0] * (1.0 - frac) + samples[i1] * frac
        }
        return result
    }

    // MARK: - ONNX 推理（C 桥接）

    func runInference(feats: [[Float]], featsLen: Int32) throws -> [Int32] {
        guard let modelPath = Bundle.main.path(
            forResource: "model_quant", ofType: "onnx", inDirectory: "sensevoice"
        ) else {
            throw STTError.modelNotReady
        }

        // 初始化 ORT
        var env: OpaquePointer?
        var session: OpaquePointer?
        var memInfo: OpaquePointer?
        defer {
            TalkFlowOrtReleaseSession(session)
            TalkFlowOrtReleaseMemInfo(memInfo)
            TalkFlowOrtReleaseEnv(env)
        }

        let status = TalkFlowOrtInit(modelPath, &env, &session, &memInfo)
        guard status == nil, let session, let memInfo else {
            throw STTError.inferenceFailed("ORT init failed")
        }

        let tLFR = feats.count
        let dim = feats.first?.count ?? 560
        let flatFeats = feats.flatMap { $0 }

        // 创建输入 tensors
        var shape: [Int64] = [1, Int64(tLFR), Int64(dim)]
        var featsTensor: OpaquePointer?
        let _ = shape.withUnsafeMutableBufferPointer { sPtr in
            flatFeats.withUnsafeBufferPointer { dPtr in
                TalkFlowOrtCreateFloatTensor(dPtr.baseAddress, sPtr.baseAddress, 3, memInfo, &featsTensor)
            }
        }
        guard let featsTensor else { throw STTError.inferenceFailed("feats tensor failed") }
        defer { TalkFlowOrtReleaseValue(featsTensor) }

        var lenData = featsLen
        var lenShape: [Int64] = [1]
        var featsLenTensor: OpaquePointer?
        let _ = lenShape.withUnsafeMutableBufferPointer { sPtr in
            withUnsafePointer(to: &lenData) { TalkFlowOrtCreateInt32Tensor($0, sPtr.baseAddress, 1, memInfo, &featsLenTensor) }
        }
        guard let featsLenTensor else { throw STTError.inferenceFailed("feats_len failed") }
        defer { TalkFlowOrtReleaseValue(featsLenTensor) }

        var langData: Int32 = 0
        var langShape: [Int64] = [1]
        var langTensor: OpaquePointer?
        let _ = langShape.withUnsafeMutableBufferPointer { sPtr in
            withUnsafePointer(to: &langData) { TalkFlowOrtCreateInt32Tensor($0, sPtr.baseAddress, 1, memInfo, &langTensor) }
        }
        defer { langTensor.map { TalkFlowOrtReleaseValue($0) } }

        var tnData: Int32 = 14
        var tnShape: [Int64] = [1]
        var tnTensor: OpaquePointer?
        let _ = tnShape.withUnsafeMutableBufferPointer { sPtr in
            withUnsafePointer(to: &tnData) { TalkFlowOrtCreateInt32Tensor($0, sPtr.baseAddress, 1, memInfo, &tnTensor) }
        }
        defer { tnTensor.map { TalkFlowOrtReleaseValue($0) } }

        // Run
        // 实际模型输入/输出名称
        let inNameStrings = ["speech", "speech_lengths", "language", "textnorm"]
        var inNamePtrs = inNameStrings.map { strdup($0) }
        let outNameStrings = ["ctc_logits", "encoder_out_lens"]
        var outNamePtrs = outNameStrings.map { strdup($0) }
        defer { inNamePtrs.forEach { free($0) } }
        defer { outNamePtrs.forEach { free($0) } }

        let inputs: [OpaquePointer?] = [featsTensor, featsLenTensor, langTensor, tnTensor]
        var outputs = [OpaquePointer?](repeating: nil, count: 2)
        let runStatus = inNamePtrs.withUnsafeMutableBufferPointer { iPtrs -> OpaquePointer? in
            outNamePtrs.withUnsafeMutableBufferPointer { oPtrs -> OpaquePointer? in
                let iBase = UnsafeMutableRawPointer(iPtrs.baseAddress!).assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                let oBase = UnsafeMutableRawPointer(oPtrs.baseAddress!).assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                return TalkFlowOrtRun(session, iBase, inputs, 4, oBase, 2, &outputs)
            }
        }
        defer { outputs.forEach { $0.map { TalkFlowOrtReleaseValue($0) } } }
        guard runStatus == nil else {
            throw STTError.inferenceFailed("ORT run failed")
        }

        guard let logitsTensor = outputs[0],
              let outputData = TalkFlowOrtGetFloatData(logitsTensor) else {
            throw STTError.inferenceFailed("No ctc_logits output")
        }

        // SenseVoiceSmall 词表大小 = 25055
        let frames = tLFR
        let vocabSize = 25055
        let total = frames * vocabSize
        let floatPtr = outputData.withMemoryRebound(to: Float.self, capacity: total) { $0 }
        let logits = Array(UnsafeBufferPointer(start: floatPtr, count: total))

        return argmaxTokens(logits: logits, frames: frames, vocabSize: vocabSize)
    }
}

// MARK: - ⚠️ 工厂（副作用：文件 IO）

func impureMakeSenseVoiceEngine() -> SenseVoiceEngineIO {
    let cmvn = impureLoadCMVN()
    let tokens = impureLoadTokens()
    return SenseVoiceEngineIO(cmvnMeans: cmvn.means, cmvnVars: cmvn.vars, tokens: tokens)
}

// MARK: - 纯工厂（测试用）

func makeSenseVoiceEngineForTesting() -> SenseVoiceEngineIO {
    SenseVoiceEngineIO(cmvnMeans: [], cmvnVars: [], tokens: [:])
}

// MARK: - ⚠️ 文件 IO（副作用标记）

private func impureLoadCMVN() -> (means: [Double], vars: [Double]) {
    guard let path = Bundle.main.path(forResource: "am", ofType: "mvn", inDirectory: "sensevoice"),
          let content = try? String(contentsOfFile: path, encoding: .utf8)
    else { return ([], []) }

    let lines = content.components(separatedBy: .newlines)
    var section: String?
    var means = [Double]()
    var vars = [Double]()

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("<AddShift>") { section = "means"; continue }
        if trimmed.contains("<Rescale>") { section = "vars"; continue }
        guard let section, !trimmed.isEmpty, !trimmed.hasPrefix("[") else { continue }
        let values = trimmed.split(separator: " ").compactMap { Double($0) }
        if section == "means" { means.append(contentsOf: values) }
        else { vars.append(contentsOf: values) }
    }
    return (means, vars)
}

private func impureLoadTokens() -> [Int: String] {
    guard let url = Bundle.main.url(forResource: "tokens", withExtension: "json", subdirectory: "sensevoice"),
          let data = try? Data(contentsOf: url)
    else { return [:] }

    // tokens.json 是数组格式: ["<unk>", "<s>", ...]
    if let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
        return array.enumerated().reduce(into: [:]) { dict, pair in
            dict[pair.offset] = pair.element
        }
    }
    return [:]
}
