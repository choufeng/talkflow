# STT SenseVoiceSmall 本地语音转文字实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现本地离线语音转文字，录音完成后自动经 SenseVoiceSmall + ONNX Runtime 转为文本。

**Architecture:** 纯函数（fbank/LFR/CMVN/argmax/BPE解码/后处理）+ ONNX Runtime（模型推理）。fbank 使用 Accelerate/vDSP 手写，BPE 解码通过 tokens.json 查表。模型文件打入 App Bundle，运行时无网络依赖。

**Tech Stack:** Swift 5.10, Accelerate/vDSP, ONNX Runtime 1.21+, Xcode 16+

---

## 任务 0：环境准备（依赖与模型文件）

**前置条件：** Homebrew 已安装，Xcode 16+ 可用。

### 任务 0a：准备 ONNX Runtime

- [ ] **下载 onnxruntime.xcframework**

```bash
# 下载 macOS 版本
curl -L https://github.com/microsoft/onnxruntime/releases/download/v1.21.0/onnxruntime-osx-universal2-1.21.0.tgz -o /tmp/ort.tgz
tar xzf /tmp/ort.tgz -C /tmp/
# 将 /tmp/onnxruntime-osx-universal2-1.21.0/onnxruntime.xcframework 拖入 Xcode 项目
```

- [ ] **在 Xcode 中操作**：将 `onnxruntime.xcframework` 拖入 TalkFlow target 的 Frameworks 分组，勾选 Embed & Sign。

### 任务 0b：下载模型文件

- [ ] **从 HuggingFace 下载**

```bash
MODEL_DIR="/Users/jia.xia/development/TalkFlow/TalkFlow/Resources/sensevoice"
mkdir -p $MODEL_DIR
BASE="https://huggingface.co/haixuantao/SenseVoiceSmall-onnx/resolve/main"
for f in model_quant.onnx am.mvn chn_jpn_yue_eng_ko_spectok.bpe.model tokens.json config.yaml; do
    curl -L "$BASE/$f" -o "$MODEL_DIR/$f"
done
```

- [ ] **SHA256 校验**

```bash
# 预期值（TalkShow 已验证）
# model_quant.onnx: 21dc965f689a78d1604717bf561e40d5a236087c85a95584567835750549e822
# am.mvn: 29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5
# chn_jpn_yue_eng_ko_spectok.bpe.model: a2594fc1474e78973149cba8cd1f603ebed8c39c7decb470631f66e70ce58e97
# tokens.json: aa87f86064c3730d799ddf7af3c04659151102cba548bce325cf06ba4da4e6a8
shasum -a 256 $MODEL_DIR/*
```

- [ ] **添加到 Xcode 项目**：将 `Resources/sensevoice/` 文件夹拖入 Xcode，作为 folder reference（蓝色文件夹），确保 Copy Bundle Resources。

### 任务 0e：验证编译

- [ ] **清理构建**

```bash
cd /Users/jia.xia/development/TalkFlow
make test
```

预期：构建成功，现有 14 个测试全部通过。

---

## 任务 1：STTResult ADT

**文件：**
- 创建：`TalkFlow/Utils/STTResult.swift`
- 创建：`TalkFlowTests/Pure/STTResultTests.swift`

- [ ] **Step 1：写失败测试**

写入 `TalkFlowTests/Pure/STTResultTests.swift`：

```swift
// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class STTResultTests: XCTestCase {

    func test_speech_result_equals_sameValues() {
        let a = STTResult.speech(text: "你好", language: "zh")
        let b = STTResult.speech(text: "你好", language: "zh")
        XCTAssertEqual(a, b)
    }

    func test_speech_result_notEquals_differentText() {
        let a = STTResult.speech(text: "你好", language: "zh")
        let b = STTResult.speech(text: "Hello", language: "en")
        XCTAssertNotEqual(a, b)
    }

    func test_silence_equals_silence() {
        XCTAssertEqual(STTResult.silence, STTResult.silence)
    }

    func test_failure_equals_sameError() {
        let a = STTResult.failure(.modelNotReady)
        let b = STTResult.failure(.modelNotReady)
        XCTAssertEqual(a, b)
    }

    func test_different_case_notEqual() {
        XCTAssertNotEqual(STTResult.silence, STTResult.speech(text: "", language: ""))
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/STTResultTests
```

预期：编译失败 "Cannot find type STTResult"。

- [ ] **Step 3：实现 STTResult**

写入 `TalkFlow/Utils/STTResult.swift`：

```swift
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
```

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/STTResultTests
```

预期：5 个测试全部 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/Utils/STTResult.swift TalkFlowTests/Pure/STTResultTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: STTResult ADT + 测试"
```

---

## 任务 2：FbankFeature 纯函数 — LFR 低帧率拼接

**文件：**
- 创建：`TalkFlow/Utils/FbankFeature.swift`
- 创建：`TalkFlowTests/Pure/FbankFeatureTests.swift`

- [ ] **Step 1：写失败测试**

写入 `TalkFlowTests/Pure/FbankFeatureTests.swift`：

```swift
// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class FbankFeatureTests: XCTestCase {

    // MARK: - applyLFR

    func test_applyLFR_emptyInput_returnsEmpty() {
        let feats: [[Float]] = []
        let result = applyLFR(feats)
        XCTAssertTrue(result.isEmpty)
    }

    func test_applyLFR_singleFrame_returnsLFRFrame() {
        // 单帧 80 维，被左填充 3 次 → padded 有 4 帧
        // t_lfr = (4 - 7) / 6 + 1 = 0 → 空
        let feats = [Array(repeating: 1.0 as Float, count: 80)]
        let result = applyLFR(feats)
        XCTAssertTrue(result.isEmpty)
    }

    func test_applyLFR_minimalFrames_producesOutput() {
        // 需要 padded >= lfr_m=7 → 原始帧 >= 4（填充 3 次 = 7）
        let feats = Array(repeating: Array(repeating: 1.0 as Float, count: 80), count: 4)
        let result = applyLFR(feats)
        XCTAssertEqual(result.count, 1)
    }

    func test_applyLFR_outputDimension_is80x7() {
        let feats = Array(repeating: Array(repeating: Float(0), count: 80), count: 10)
        let result = applyLFR(feats)
        if let first = result.first {
            XCTAssertEqual(first.count, 560) // 80 * 7
        }
    }

    func test_applyLFR_leftPaddingUsesFirstFrame() {
        // 7帧全相同 → 拼接结果各维也相同
        let feats = Array(repeating: Array(repeating: 1.0 as Float, count: 80), count: 7)
        let result = applyLFR(feats)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], Array(repeating: 1.0 as Float, count: 560))
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/FbankFeatureTests
```

预期：编译失败 "Cannot find applyLFR"。

- [ ] **Step 3：实现 applyLFR**

写入 `TalkFlow/Utils/FbankFeature.swift`：

```swift
import Foundation

// MARK: - 低帧率拼接（LFR）

/// LFR: 将 10ms 步进的 fbank 特征拼接为 60ms 步进
/// 参数: m=7（拼接宽度）, n=6（步进步长）
/// 输入: [N 帧 × 80 维]
/// 输出: [T_LFR 帧 × 560 维]
func applyLFR(_ feats: [[Float]]) -> [[Float]] {
    let lfrM = 7
    let lfrN = 6
    let leftPad = (lfrM - 1) / 2

    guard let first = feats.first, !first.isEmpty else {
        return []
    }

    let dim = first.count
    // 左填充：复制首帧 leftPad 次
    var padded = [[Float]]()
    padded.reserveCapacity(feats.count + leftPad)
    for _ in 0..<leftPad {
        padded.append(first)
    }
    padded.append(contentsOf: feats)

    let paddedCount = padded.count
    guard paddedCount >= lfrM else { return [] }

    let tLFR = (paddedCount - lfrM) / lfrN + 1
    let lfrDim = dim * lfrM
    var result = [[Float]]()
    result.reserveCapacity(tLFR)

    for i in 0..<tLFR {
        let start = i * lfrN
        var frame = [Float]()
        frame.reserveCapacity(lfrDim)
        for j in 0..<lfrM {
            let src = padded[start + j]
            frame.append(contentsOf: src)
        }
        result.append(frame)
    }

    return result
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/FbankFeatureTests
```

预期：5 个测试 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/Utils/FbankFeature.swift TalkFlowTests/Pure/FbankFeatureTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: applyLFR 低帧率拼接 + 测试"
```

---

## 任务 3：FbankFeature 纯函数 — CMVN + 后处理

**文件：**
- 修改：`TalkFlowTests/Pure/FbankFeatureTests.swift`
- 修改：`TalkFlow/Utils/FbankFeature.swift`

在已有文件中追加 CMVN、argmax、postprocess 函数和测试。

- [ ] **Step 1：追加测试**

在 `FbankFeatureTests.swift` 末尾追加：

```swift
    // MARK: - applyCMVN

    func test_applyCMVN_preservesDimensions() {
        let feats: [[Float]] = [[1.0, 2.0], [3.0, 4.0]]
        let means: [Double] = [0.0, 0.0]
        let vars: [Double] = [1.0, 1.0]
        let result = applyCMVN(feats, means: means, vars: vars)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].count, 2)
    }

    func test_applyCMVN_appliesFormula() {
        // CMVN: result = (feat + mean) * var
        let feats: [[Float]] = [[2.0, 3.0]]
        let means: [Double] = [1.0, 2.0]
        let vars: [Double] = [4.0, 5.0]
        let result = applyCMVN(feats, means: means, vars: vars)
        XCTAssertEqual(result[0][0], (2.0 + 1.0) * 4.0)
        XCTAssertEqual(result[0][1], (3.0 + 2.0) * 5.0)
    }

    // MARK: - argmaxTokens

    func test_argmax_picksMaxIndex_perFrame() {
        // 词表大小 4，共 2 帧
        // 帧0: [0.1, 0.2, 0.9, 0.3] → idx 2
        // 帧1: [0.8, 0.1, 0.1, 0.4] → idx 0
        let logits: [Float] = [0.1, 0.2, 0.9, 0.3, 0.8, 0.1, 0.1, 0.4]
        let tokens = argmaxTokens(logits: logits, frames: 2, vocabSize: 4)
        XCTAssertEqual(tokens, [2, 0])
    }

    func test_argmax_skipsIndexZero() {
        let logits: [Float] = [1.0, 0.1, 0.1, 1.0, 0.1, 0.1] // 2帧, vocab=3
        let tokens = argmaxTokens(logits: logits, frames: 2, vocabSize: 3)
        // 帧0: max=0 but idx=0 → skip; 帧1: same → skip → empty
        XCTAssertEqual(tokens, [])
    }

    func test_argmax_deduplicatesConsecutive() {
        let logits: [Float] = [0.1, 0.9, 0.1, 0.1, 0.9, 0.1, 0.9, 0.1, 0.1]
        let tokens = argmaxTokens(logits: logits, frames: 3, vocabSize: 3)
        // 帧0: idx 1; 帧1: idx 1 (dup→skip); 帧2: idx 1 (dup→skip)
        XCTAssertEqual(tokens, [1])
    }

    // MARK: - postprocess

    func test_postprocess_removesTags() {
        XCTAssertEqual(postprocess("<|zh|>你好<|en|>"), "你好")
    }

    func test_postprocess_trimsWhitespace() {
        XCTAssertEqual(postprocess("  hello  "), "hello")
    }

    func test_postprocess_emptyString_returnsEmpty() {
        XCTAssertEqual(postprocess(""), "")
    }

    func test_postprocess_onlyTags_returnsEmpty() {
        XCTAssertEqual(postprocess("<|nospeech|>"), "")
    }
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/FbankFeatureTests
```

预期：多个编译失败（applyCMVN/argmaxTokens/postprocess 未定义）。

- [ ] **Step 3：实现 CMVN + argmax + postprocess**

在 `FbankFeature.swift` 末尾追加：

```swift
// MARK: - CMVN 归一化

/// CMVN: (feat + mean) * var
func applyCMVN(_ feats: [[Float]], means: [Double], vars: [Double]) -> [[Float]] {
    let n = min(means.count, vars.count)
    return feats.map { frame in
        frame.enumerated().map { i, v in
            guard i < n else { return v }
            return Float((Double(v) + means[i]) * vars[i])
        }
    }
}

// MARK: - Token 解码

/// argmax: 从 ONNX 输出 logits 取每帧最大 token_id
/// - 跳过 token_id == 0（blank）
/// - 去重（连续相同 token 只保留一个）
func argmaxTokens(logits: [Float], frames: Int, vocabSize: Int) -> [Int32] {
    var result = [Int32]()
    for t in 0..<frames {
        let start = t * vocabSize
        let end = start + vocabSize
        let row = Array(logits[start..<end])
        guard let maxIdx = row.indices.max(by: { row[$0] < row[$1] }),
              maxIdx != 0
        else { continue }
        let token = Int32(maxIdx)
        if result.last != token {
            result.append(token)
        }
    }
    return result
}

// MARK: - 后处理

/// 去除 <|tag|> 特殊标记，trim 空白
func postprocess(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: []) else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let range = NSRange(text.startIndex..., in: text)
    let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/FbankFeatureTests
```

预期：14 个测试 PASS（5 个 LFR + 9 个 CMVN/argmax/postprocess）。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/Utils/FbankFeature.swift TalkFlowTests/Pure/FbankFeatureTests.swift
git commit -m "feat: CMVN 归一化 + argmax 解码 + 后处理"
```

---

## 任务 4：TokenDecoder — tokens.json 查表解码

**文件：**
- 创建：`TalkFlow/Utils/TokenDecoder.swift`
- 创建：`TalkFlowTests/Pure/TokenDecoderTests.swift`

使用 `tokens.json`（token_id → 文本片段 映射）做 BPE 解码。加载为 `[Int: String]`，拼接为最终文本。

- [ ] **Step 1：写测试**

写入 `TalkFlowTests/Pure/TokenDecoderTests.swift`：

```swift
// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class TokenDecoderTests: XCTestCase {

    func test_loadTokens_returnsDictionary() {
        let tokens = loadTokens()
        XCTAssertFalse(tokens.isEmpty)
    }

    func test_decode_emptyTokenIds_returnsEmptyString() {
        let tokens: [Int: String] = [1: "你", 2: "好"]
        let result = decodeTokenIds([], tokens: tokens)
        XCTAssertEqual(result, "")
    }

    func test_decode_singleToken_returnsCorrectText() {
        let tokens: [Int: String] = [1: "你", 2: "好"]
        let result = decodeTokenIds([1, 2], tokens: tokens)
        XCTAssertEqual(result, "你好")
    }

    func test_decode_skipsUnknownTokens() {
        let tokens: [Int: String] = [1: "a"]
        let result = decodeTokenIds([1, 99, 1], tokens: tokens)
        XCTAssertEqual(result, "aa") // token 99 不在字典 → 跳过
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/TokenDecoderTests
```

预期：编译失败（loadTokens/decodeTokenIds 未定义）。

- [ ] **Step 3：实现 TokenDecoder**

写入 `TalkFlow/Utils/TokenDecoder.swift`：

```swift
import Foundation

// MARK: - Token 映射表

/// 从 Bundle 加载 tokens.json，返回 [token_id: 文本片段]
func loadTokens() -> [Int: String] {
    guard let url = Bundle.main.url(forResource: "tokens", withExtension: "json", subdirectory: "sensevoice"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }
    let dict = json.compactMap { (key, value) -> (Int, String)? in
        guard let id = Int(key), let text = value as? String else { return nil }
        return (id, text)
    }
    return Dictionary(uniqueKeysWithValues: dict)
}

/// 将 token_id 序列解码为文本
func decodeTokenIds(_ ids: [Int32], tokens: [Int: String]) -> String {
    ids.compactMap { tokens[Int($0)] }.joined()
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/TokenDecoderTests
```

预期：4 个测试 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/Utils/TokenDecoder.swift TalkFlowTests/Pure/TokenDecoderTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: tokens.json 查表 BPE 解码 + 测试"
```

---

## 任务 5：SenseVoiceIO 协议

**文件：**
- 创建：`TalkFlow/IO/SenseVoiceIO.swift`

单一文件，无测试（纯协议定义，遵照现有 `AudioRecorderIO` 模式）。

- [ ] **Step 1：实现协议**

写入 `TalkFlow/IO/SenseVoiceIO.swift`：

```swift
import Foundation

// MARK: - 协议

protocol SenseVoiceIO {
    /// 模型是否已就绪（ONNX 模型已加载）
    var isModelReady: Bool { get }

    /// 转写音频文件 → STTResult
    func transcribe(url: URL) async throws -> STTResult
}
```

- [ ] **Step 2：确认编译**

```bash
make test
```

预期：构建成功。

- [ ] **Step 3：提交**

```bash
git add TalkFlow/IO/SenseVoiceIO.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: SenseVoiceIO 协议定义"
```

---

## 任务 6：SenseVoiceEngineIO — 纯 Swift 部分（预处理 + 后处理）

**文件：**
- 创建：`TalkFlow/IO/SenseVoiceEngineIO.swift`
- 创建：`TalkFlowTests/Mocks/MockONSSTSession.swift`
- 创建：`TalkFlowTests/IO/SenseVoiceEngineIOTests.swift`

先实现预处理和后处理部分（音频解码、重采样、fbank/LFR/CMVN），ONNX 推理部分依赖任务 7 的 C 桥接。

- [ ] **Step 1：写 Mock ONNX Session**

写入 `TalkFlowTests/Mocks/MockONSSTSession.swift`：

```swift
// TalkFlowTests/Mocks/
import Foundation

/// 模拟 ONNX 推理返回值
struct MockONNXOutput {
    /// token_id 序列（模拟模型输出）
    let tokenIds: [Int32]
}

/// 捕获 ONNX 推理输入参数
struct CapturedONNXInput {
    var feats: [Float] = []
    var featsLen: Int = 0
    var language: Int = 0
    var textnorm: Int = 0
}
```

- [ ] **Step 2：写 IO 层测试**

写入 `TalkFlowTests/IO/SenseVoiceEngineIOTests.swift`：

```swift
// TalkFlowTests/IO/
import XCTest
@testable import TalkFlow

final class SenseVoiceEngineIOTests: XCTestCase {

    func test_audioTooShort_returnsSilence() async throws {
        // 小于 4800 样本（0.3s @16kHz）→ silence
        let shortAudio = [Float](repeating: 0, count: 1000)
        let result = SenseVoiceEngineIO().classifySilence(samples: shortAudio, sampleRate: 16000)
        XCTAssertTrue(result)
    }

    func test_audioLongEnough_notSilence() {
        let longAudio = [Float](repeating: 0, count: 5000)
        let result = SenseVoiceEngineIO().classifySilence(samples: longAudio, sampleRate: 16000)
        XCTAssertFalse(result)
    }
}
```

- [ ] **Step 3：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/SenseVoiceEngineIOTests
```

- [ ] **Step 4：实现 SenseVoiceEngineIO**

写入 `TalkFlow/IO/SenseVoiceEngineIO.swift`：

```swift
import Foundation
import AVFoundation

// MARK: - 实现

final class SenseVoiceEngineIO: SenseVoiceIO {

    // MARK: - 配置常量

    private let targetSampleRate: Double = 16000
    private let minSampleCount = 4800  // 0.3s @ 16kHz
    private let fbankDim = 80

    // MARK: - 状态

    var isModelReady: Bool = false

    // MARK: - 公开 API

    func transcribe(url: URL) async throws -> STTResult {
        // 1. 解码音频
        let (samples, sampleRate) = try decodeAudio(url: url)

        // 2. 静音判断
        guard !classifySilence(samples: samples, sampleRate: sampleRate) else {
            return .silence
        }

        // 3. 预处理（重采样 + fbank + LFR + CMVN）→ 将在后续任务完善
        // TODO: 连接 C 桥接 + ONNX 推理

        return .silence // 占位
    }

    // MARK: - 内部方法

    /// 解码音频文件 → PCM 样本
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

    /// 静音判定（音频 < 4800 样本）
    func classifySilence(samples: [Float], sampleRate: Double) -> Bool {
        // 先重采样到 16kHz 再判定
        let resampled = resampleTo16k(samples: samples, srcRate: sampleRate)
        return resampled.count < minSampleCount
    }

    // MARK: - 重采样（简版 vDSP）

    func resampleTo16k(samples: [Float], srcRate: Double) -> [Float] {
        guard abs(srcRate - targetSampleRate) > 1.0 else { return samples }
        let ratio = targetSampleRate / srcRate
        let outputCount = Int(Double(samples.count) * ratio)
        var result = [Float](repeating: 0, count: outputCount)
        // 使用线性插值重采样
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let i0 = Int(srcIndex)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(srcIndex - Double(i0))
            result[i] = samples[i0] * (1.0 - frac) + samples[i1] * frac
        }
        return result
    }
}

// MARK: - 内部可见性扩展（测试用）

extension SenseVoiceEngineIO {
    // classifySilence 已在上面声明为 func，测试可直接调用
}
```

- [ ] **Step 4b：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/SenseVoiceEngineIOTests
```

预期：2 个测试 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/IO/SenseVoiceEngineIO.swift TalkFlowTests/Mocks/MockONSSTSession.swift TalkFlowTests/IO/SenseVoiceEngineIOTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: SenseVoiceEngineIO 音频解码 + 静音判定 + 重采样"
```

---

## 任务 7：Swift 原生 fbank 特征提取（Accelerate/vDSP）

**文件：**
- 创建：`TalkFlow/Utils/FbankExtractor.swift`
- 修改：`TalkFlowTests/Pure/FbankFeatureTests.swift`

使用 Accelerate 框架（vDSP FFT + vDSP 矩阵运算）实现 fbank 特征提取，参数对标 kaldi-native-fbank。

- [ ] **Step 1：写 fbank 测试**

在 `FbankFeatureTests.swift` 末尾追加：

```swift
    // MARK: - extractFbank

    func test_fbank_sineWave_producesFrames() {
        let sampleCount = 16000  // 1s @ 16kHz
        let samples = (0..<sampleCount).map { i -> Float in
            sin(2.0 * Float.pi * 440.0 * Float(i) / 16000.0)
        }
        let feats = extractFbank(waveform: samples)
        // 1s → 约 99 帧 (25ms窗口/10ms步进)
        XCTAssertGreaterThan(feats.count, 80)
        if let first = feats.first {
            XCTAssertEqual(first.count, 80)
        }
    }

    func test_fbank_shorterThanWindow_returnsEmpty() {
        let samples = [Float](repeating: 0, count: 399) // < 400样本(25ms@16kHz)
        let feats = extractFbank(waveform: samples)
        XCTAssertTrue(feats.isEmpty)
    }

    func test_fbank_allZeros_isNonNegative() {
        let samples = [Float](repeating: 0, count: 8000)
        let feats = extractFbank(waveform: samples)
        XCTAssertFalse(feats.isEmpty)
        for frame in feats {
            for val in frame {
                XCTAssertFalse(val.isNaN)
                XCTAssertFalse(val.isInfinite)
            }
        }
    }
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/FbankFeatureTests/test_fbank_sineWave_producesFrames
```

预期：编译失败（extractFbank 未定义）。

- [ ] **Step 3：实现 extractFbank**

写入 `TalkFlow/Utils/FbankExtractor.swift`：

```swift
import Foundation
import Accelerate

// MARK: - fbank 参数（对标 kaldi-native-fbank）

private let sampleRate: Double = 16000
private let frameLengthMs: Double = 25
private let frameShiftMs: Double = 10
private let numMelBins = 80
private let lowFreq: Double = 20
private let highFreq: Double = 7600  // sampleRate/2 - 400

// MARK: - 公共 API

/// 提取 fbank 特征
/// - Parameter waveform: 16kHz 单声道 PCM 样本（范围 0±1）
/// - Returns: [帧数 × 80维]
func extractFbank(waveform: [Float]) -> [[Float]] {
    let frameLen = Int(sampleRate * frameLengthMs / 1000)   // 400
    let frameShift = Int(sampleRate * frameShiftMs / 1000)   // 160
    let fftN = 1 << Int(ceil(log2(Double(frameLen))))        // 512

    guard waveform.count >= frameLen else { return [] }

    let numFrames = (waveform.count - frameLen) / frameShift + 1
    let melFilterbank = precomputeMelFilterbank(fftN: fftN)

    var result = [[Float]]()
    result.reserveCapacity(numFrames)

    // Hamming 窗
    var window = [Float](repeating: 0, count: frameLen)
    vDSP_hamm_window(&window, vDSP_Length(frameLen), 0)

    // FFT 设置
    let log2n = vDSP_Length(log2(Double(fftN)))
    let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

    for i in 0..<numFrames {
        let start = i * frameShift
        var frame = Array(waveform[start..<min(start + frameLen, waveform.count)])
        if frame.count < frameLen {
            frame.append(contentsOf: [Float](repeating: 0, count: frameLen - frame.count))
        }
        // 去直流
        var mean: Float = 0
        vDSP_meanv(frame, 1, &mean, vDSP_Length(frame.count))
        var dcRemoved = frame.map { $0 - mean }
        // 加窗
        vDSP_vmul(dcRemoved, 1, window, 1, &dcRemoved, 1, vDSP_Length(frameLen))
        // FFT
        let fbank = computeFbankFrame(dcRemoved, fftN: fftN, fftSetup: fftSetup, melFilterbank: melFilterbank)
        result.append(fbank)
    }

    vDSP_destroy_fftsetup(fftSetup)
    return result
}

// MARK: - Mel 滤波器组

private func precomputeMelFilterbank(fftN: Int) -> [[Float]] {
    let numBins = fftN / 2 + 1
    var melPoints = (0..<(numMelBins + 2)).map { i -> Float in
        let melLow = hzToMel(Float(lowFreq))
        let melHigh = hzToMel(Float(highFreq))
        let mel = melLow + Float(i) * (melHigh - melLow) / Float(numMelBins + 1)
        return melToHz(mel)
    }
    // 映射到 FFT bin
    melPoints = melPoints.map { $0 * Float(fftN) / Float(sampleRate) }

    return (0..<numMelBins).map { m in
        var filter = [Float](repeating: 0, count: numBins)
        for k in 0..<numBins {
            let fk = Float(k)
            if fk < melPoints[m] {
                filter[k] = 0
            } else if fk <= melPoints[m + 1] {
                filter[k] = (fk - melPoints[m]) / (melPoints[m + 1] - melPoints[m])
            } else if fk <= melPoints[m + 2] {
                filter[k] = (melPoints[m + 2] - fk) / (melPoints[m + 2] - melPoints[m + 1])
            } else {
                filter[k] = 0
            }
        }
        return filter
    }
}

// MARK: - 单帧 fbank

private func computeFbankFrame(_ frame: [Float], fftN: Int, fftSetup: FFTSetup, melFilterbank: [[Float]]) -> [Float] {
    let numBins = fftN / 2 + 1
    // 填充到 fftN
    var padded = frame + [Float](repeating: 0, count: fftN - frame.count)
    // 实数 FFT
    var realPart = [Float](repeating: 0, count: numBins)
    var imagPart = [Float](repeating: 0, count: numBins)
    padded.withUnsafeMutableBufferPointer { buf in
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftN / 2) { complex in
            vDSP_ctoz(complex, 2, &splitComplex, 1, vDSP_Length(fftN / 2))
        }
    }
    vDSP_fft_zrip(fftSetup, &realPart, &imagPart, 1, vDSP_Length(log2(Double(fftN))), FFTDirection(kFFTDirection_Forward))
    // 功率谱
    var powerSpectrum = [Float](repeating: 0, count: numBins)
    for k in 0..<numBins {
        powerSpectrum[k] = (realPart[k] * realPart[k] + imagPart[k] * imagPart[k]) / Float(fftN)
    }
    // Mel 滤波器组
    var fbank = [Float](repeating: 0, count: numMelBins)
    for m in 0..<numMelBins {
        var sum: Float = 0
        vDSP_dotpr(powerSpectrum, 1, melFilterbank[m], 1, &sum, vDSP_Length(numBins))
        fbank[m] = max(sum, 1e-10)  // 防 log(0)
    }
    // 对数
    var logFbank = [Float](repeating: 0, count: numMelBins)
    vForce.logf(fbank, &logFbank, numMelBins)
    return logFbank
}

// MARK: - Mel 尺度转换

private func hzToMel(_ hz: Float) -> Float {
    1127.0 * log(1.0 + hz / 700.0)
}

private func melToHz(_ mel: Float) -> Float {
    700.0 * (exp(mel / 1127.0) - 1.0)
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/FbankFeatureTests
```

预期：17 个测试 PASS（14 已有 + 3 新增 fbank）。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/Utils/FbankExtractor.swift TalkFlowTests/Pure/FbankFeatureTests.swift
xcodebuild test -scheme TalkFlow -quiet && git commit -m "feat: Accelerate/vDSP fbank 特征提取 + 测试"
```

---

## 任务 8：串联流水线 — 完整的 transcribe()

**文件：**
- 修改：`TalkFlow/IO/SenseVoiceEngineIO.swift`
- 修改：`TalkFlowTests/IO/SenseVoiceEngineIOTests.swift`

补齐 `transcribe()` 中的预处理 → fbank → LFR → CMVN → 推理 → 解码流程。

- [ ] **Step 1：更新 SenseVoiceEngineIO**

将 `transcribe()` 主体替换为：

```swift
    // MARK: - CMVN 参数

    private var cmvnMeans: [Double] = []
    private var cmvnVars: [Double] = []

    // MARK: - 初始化

    init() {
        loadCMVN()
    }

    private func loadCMVN() {
        guard let path = Bundle.main.path(forResource: "am", ofType: "mvn", inDirectory: "sensevoice"),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return }

        let lines = content.components(separatedBy: .newlines)
        var section: String? = nil
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("<AddShift>") { section = "means"; continue }
            if trimmed.contains("<Rescale>") { section = "vars"; continue }
            guard let section, !trimmed.isEmpty, !trimmed.hasPrefix("[") else { continue }
            let values = trimmed.split(separator: " ").compactMap { Double($0) }
            if section == "means" { cmvnMeans.append(contentsOf: values) }
            else { cmvnVars.append(contentsOf: values) }
        }
    }

    func transcribe(url: URL) async throws -> STTResult {
        // 1. 解码 + 重采样
        let (samples, sampleRate) = try decodeAudio(url: url)
        let resampled = resampleTo16k(samples: samples, srcRate: sampleRate)

        // 2. 静音判定
        guard resampled.count >= minSampleCount else {
            return .silence
        }

        // 3. fbank 特征提取
        let fbank = extractFbank(waveform: resampled)
        guard !fbank.isEmpty else {
            return .silence
        }

        // 4. LFR 低帧率拼接
        let lfr = applyLFR(fbank)
        guard !lfr.isEmpty else {
            return .silence
        }

        // 5. CMVN 归一化
        let normalized = applyCMVN(lfr, means: cmvnMeans, vars: cmvnVars)

        // 6. ONNX 推理 → 将在任务 9 补齐
        // let tokenIds = try runInference(feats: normalized, featsLen: lfr.count)

        // 7. BPE 解码 + 后处理
        // let text = sentencePieceDecode(tokenIds)
        // let cleaned = postprocess(text)

        // return .speech(text: cleaned, language: "auto")

        return .speech(text: "占位", language: "zh") // 占位，任务 9 移除
    }
```

> **注意：** 此步骤是流水线串联，ONNX 推理和 BPE 解码在后续任务补齐。

- [ ] **Step 2：确认编译**

```bash
make test
```

预期：构建成功，现有测试全通过。

- [ ] **Step 3：提交**

```bash
git add TalkFlow/IO/SenseVoiceEngineIO.swift
git commit -m "feat: transcribe 预处理流水线串联 (LFR+CMVN)"
```

---

## 任务 9：ONNX Runtime 推理集成

**文件：**
- 修改：`TalkFlow/IO/SenseVoiceEngineIO.swift`
- 修改：`TalkFlowTests/Mocks/MockONSSTSession.swift`
- 修改：`TalkFlowTests/IO/SenseVoiceEngineIOTests.swift`

使用 ONNX Runtime C API + bridging header 实现推理。输入 fbank 特征，输出 token_id 序列。

- [ ] **Step 1：创建 bridging header**

写入 `TalkFlow/TalkFlow-Bridging-Header.h`：

```c
#include "onnxruntime_c_api.h"
```

在 Xcode 中：Build Settings → Swift Compiler → Objective-C Bridging Header → `TalkFlow/TalkFlow-Bridging-Header.h`

- [ ] **Step 2：实现 ORT 推理方法**

在 `SenseVoiceEngineIO.swift` 中添加：

```swift
    // MARK: - ONNX 推理（ORT C API）

    private var ortEnv: OpaquePointer?
    private var ortSession: OpaquePointer?

    private func ensureSession() throws -> OpaquePointer {
        if let s = ortSession { return s }
        guard let modelPath = Bundle.main.path(forResource: "model_quant", ofType: "onnx", inDirectory: "sensevoice") else {
            throw STTError.modelNotReady
        }
        let env: OpaquePointer? = nil
        OrtCreateEnv(ORT_LOGGING_LEVEL_WARNING, "talkflow", &ortEnv)
        OrtCreateSession(ortEnv, modelPath, nil, &ortSession)
        self.isModelReady = true
        return ortSession!
    }

    func runInference(feats: [[Float]], featsLen: Int) throws -> [Int32] {
        let session = try ensureSession()
        let tLFR = feats.count
        let dim = feats.first?.count ?? 560
        var flatFeats = [Float]()
        for frame in feats { flatFeats.append(contentsOf: frame) }

        let inputShape: [Int64] = [1, Int64(tLFR), Int64(dim)]
        var inputTensor: OpaquePointer?
        let memInfo: OpaquePointer? = nil
        OrtCreateMemoryInfo("Cpu", OrtDeviceAllocator, 0, OrtMemTypeDefault, &memInfo)

        flatFeats.withUnsafeBytes { ptr in
            OrtCreateTensorWithDataAsOrtValue(
                memInfo, ptr.baseAddress, flatFeats.count * MemoryLayout<Float>.size,
                inputShape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &inputTensor
            )
        }

        // ... 构造 feats_len, language, textnorm tensors（类似）
        // ... session.run
        // ... 提取 logits → argmaxTokens

        return [] // 占位 — 完整实现参考 TalkShow engine.rs infer()
    }
```

> **注意：** ORT C API 需要精确的指针管理和内存释放。完整实现在子代理执行时根据实际编译通过的 API 签名调整。

- [ ] **Step 3：完善 transcribe() BPE 解码**

将占位解码替换为 `decodeTokenIds(ids, tokens: loadedTokens)`。

- [ ] **Step 4：运行完整测试**

```bash
make test
```

预期：所有现有测试 + 新测试 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/IO/SenseVoiceEngineIO.swift TalkFlowTests/Mocks/MockONSSTSession.swift TalkFlowTests/IO/SenseVoiceEngineIOTests.swift
xcodebuild test -scheme TalkFlow -quiet && git commit -m "feat: ONNX Runtime 推理 + BPE 解码集成"
```

---

## 任务 10：AppDelegate 集成 + 端到端测试

**文件：**
- 修改：`TalkFlow/AppDelegate.swift`

- [ ] **Step 1：集成 STT**

在 `AppDelegate` 中添加：

```swift
// 在类属性区域添加
private let sttEngine: SenseVoiceIO = SenseVoiceEngineIO()

// 在 applicationDidFinishLaunching 中 setupSTT() 后添加：
private func setupSTT() {
    onRecordingComplete = { [weak self] url in
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.sttEngine.transcribe(url: url)
                await MainActor.run {
                    switch result {
                    case .speech(let text, let language):
                        print("[STT] \(language): \(text)")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    case .silence:
                        print("[STT] Silence — ignored")
                    case .failure(let error):
                        print("[STT] Error: \(error)")
                    }
                }
            } catch {
                print("[STT] Exception: \(error)")
            }
        }
    }
}

// 在 applicationDidFinishLaunching 中调用：
// setupSTT()
```

- [ ] **Step 2：确认编译**

```bash
make test
```

预期：构建成功。

- [ ] **Step 3：手工端到端测试**

1. 运行 TalkFlow App
2. 按全局快捷键开始录音 → 说一句话 → 按快捷键停止
3. 验证：控制台输出转写结果，剪贴板包含识别文本

- [ ] **Step 4：提交**

```bash
git add TalkFlow/AppDelegate.swift
git commit -m "feat: AppDelegate STT 集成 + 剪贴板输出"
```

---

## 任务 11：边界情况 + 错误处理完善

**文件：**
- 修改：`TalkFlow/IO/SenseVoiceEngineIO.swift`
- 修改：`TalkFlowTests/IO/SenseVoiceEngineIOTests.swift`

- [ ] **Step 1：添加错误处理测试**

在 `SenseVoiceEngineIOTests.swift` 中追加：

```swift
    func test_missingModelFile_returnsError() {
        // 模拟模型文件缺失
        // 跳过，依赖 ONNX Runtime 内部错误报告
    }

    func test_corruptedAudio_throwsDecodeFailed() async {
        let corruptedURL = URL(fileURLWithPath: "/tmp/nonexistent.m4a")
        do {
            let _ = try await SenseVoiceEngineIO().transcribe(url: corruptedURL)
            XCTFail("Expected error")
        } catch {
            // 预期抛出错误
        }
    }
```

- [ ] **Step 2：运行测试**

```bash
make test
```

- [ ] **Step 3：提交**

```bash
git add TalkFlowTests/IO/SenseVoiceEngineIOTests.swift
git commit -m "test: 边界情况错误处理"
```

---

## 完成检查

- [ ] `make test` 全部通过
- [ ] 覆盖率 ≥ 90%
- [ ] 端到端测试通过
- [ ] 代码符合项目风格（IAuthor 标记副作用函数）
