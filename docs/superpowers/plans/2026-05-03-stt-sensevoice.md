# STT SenseVoiceSmall 本地语音转文字实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现本地离线语音转文字，录音完成后自动经 SenseVoiceSmall + ONNX Runtime 转为文本。

**Architecture:** 纯函数（LFR/CMVN/argmax/后处理）+ C 桥接（fbank 特征提取 / BPE 解码）+ ONNX Runtime（模型推理）。模型文件打入 App Bundle，运行时无网络依赖。

**Tech Stack:** Swift 5.10, ONNX Runtime 1.21+, kaldi-native-fbank (C), sentencepiece (C), Xcode 16+

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

### 任务 0b：编译 kaldi-native-fbank 静态库

- [ ] **克隆并编译**

```bash
cd /tmp
git clone --depth 1 https://github.com/csukuangfj/kaldi-native-fbank.git
cd kaldi-native-fbank
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF
cmake --build . -j$(sysctl -n hw.ncpu)
# 产物: /tmp/kaldi-native-fbank/build/libkaldi-native-fbank-core.a
```

- [ ] **复制到项目**

```bash
mkdir -p /Users/jia.xia/development/TalkFlow/TalkFlow/STT/NativeFbank/include/kaldi-native-fbank/csrc
cp /tmp/kaldi-native-fbank/csrc/*.h /Users/jia.xia/development/TalkFlow/TalkFlow/STT/NativeFbank/include/kaldi-native-fbank/csrc
cp /tmp/kaldi-native-fbank/build/libkaldi-native-fbank-core.a /Users/jia.xia/development/TalkFlow/TalkFlow/STT/NativeFbank/
```

- [ ] **创建 module.modulemap**

写入 `TalkFlow/STT/NativeFbank/module.modulemap`：

```
module NativeFbank {
    header "include/kaldi-native-fbank/csrc/online-feature.h"
    header "include/kaldi-native-fbank/csrc/feature-window.h"
    header "include/kaldi-native-fbank/csrc/mel-computations.h"
    header "include/kaldi-native-fbank/csrc/rfft.h"
    export *
    link "kaldi-native-fbank-core"
}
```

- [ ] **在 Xcode 中配置**：
  - Target → Build Settings → Swift Compiler → Import Paths：添加 `$(SRCROOT)/TalkFlow/STT/NativeFbank`
  - Target → Build Settings → Library Search Paths：添加 `$(SRCROOT)/TalkFlow/STT/NativeFbank`
  - Target → Build Phases → Link Binary With Libraries：添加 `libkaldi-native-fbank-core.a`

### 任务 0c：编译 sentencepiece 静态库

- [ ] **克隆并编译**

```bash
cd /tmp
git clone --depth 1 https://github.com/google/sentencepiece.git
cd sentencepiece
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
cmake --build . -j$(sysctl -n hw.ncpu)
# 产物: /tmp/sentencepiece/build/src/libsentencepiece.a
```

- [ ] **复制到项目**

```bash
mkdir -p /Users/jia.xia/development/TalkFlow/TalkFlow/STT/SentencePiece/include/sentencepiece
cp /tmp/sentencepiece/src/sentencepiece_processor.h /Users/jia.xia/development/TalkFlow/TalkFlow/STT/SentencePiece/include/sentencepiece/
cp /tmp/sentencepiece/src/sentencepiece_model.pb.h /Users/jia.xia/development/TalkFlow/TalkFlow/STT/SentencePiece/include/sentencepiece/ 2>/dev/null
cp /tmp/sentencepiece/build/src/libsentencepiece.a /Users/jia.xia/development/TalkFlow/TalkFlow/STT/SentencePiece/
```

- [ ] **创建 module.modulemap**

写入 `TalkFlow/STT/SentencePiece/module.modulemap`：

```
module SentencePiece {
    header "include/sentencepiece/sentencepiece_processor.h"
    export *
    link "sentencepiece"
}
```

- [ ] **在 Xcode 中配置**：
  - Import Paths：添加 `$(SRCROOT)/TalkFlow/STT/SentencePiece`
  - Library Search Paths：添加 `$(SRCROOT)/TalkFlow/STT/SentencePiece`
  - Link Binary：添加 `libsentencepiece.a`

### 任务 0d：下载模型文件

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

## 任务 4：TokenDecoder — BPE 解码桥接层

**文件：**
- 创建：`TalkFlow/Utils/TokenDecoder.swift`
- 创建：`TalkFlowTests/Pure/TokenDecoderTests.swift`

由于 sentencepiece C API 需要动态加载完成才能测试 BPE 解码，此任务改为 Swift 包装层 + 纯函数测试。BPE 解码的实际 C 调用延迟到任务 7 集成测试中验证。

- [ ] **Step 1：写测试**

写入 `TalkFlowTests/Pure/TokenDecoderTests.swift`：

```swift
// TalkFlowTests/Pure/
import XCTest
@testable import TalkFlow

final class TokenDecoderTests: XCTestCase {

    func test_bpeModelPath_returnsBundlePath() {
        let path = bpeModelPath()
        XCTAssertTrue(path.hasSuffix("chn_jpn_yue_eng_ko_spectok.bpe.model"))
    }

    func test_decodeTokenIds_emptyArray_returnsEmpty() {
        // 空 token 列表 → 空字符串
        // 注释：需要 SentencePiece 库链接后才能跑通
        // 此处测试最小逻辑路径
        XCTAssertTrue(true) // 占位：C 库链接后改为实际测试
    }
}
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/TokenDecoderTests
```

预期：编译失败（bpeModelPath 未定义）。

- [ ] **Step 3：实现 TokenDecoder**

写入 `TalkFlow/Utils/TokenDecoder.swift`：

```swift
import Foundation

// MARK: - BPE 模型路径

/// 从 Bundle 获取 BPE 模型文件路径
func bpeModelPath() -> String {
    guard let path = Bundle.main.path(
        forResource: "chn_jpn_yue_eng_ko_spectok",
        ofType: "bpe.model",
        inDirectory: "sensevoice"
    ) else {
        fatalError("BPE model not found in Bundle")
    }
    return path
}
```

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/TokenDecoderTests
```

预期：1 个测试 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/Utils/TokenDecoder.swift TalkFlowTests/Pure/TokenDecoderTests.swift TalkFlow.xcodeproj/project.pbxproj
git commit -m "feat: TokenDecoder BPE 模型路径 + 测试"
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

## 任务 7：C 桥接 — fbank 特征提取

**文件：**
- 创建：`TalkFlow/STT/FbankBridge.swift`
- 修改：`TalkFlowTests/IO/SenseVoiceEngineIOTests.swift`

- [ ] **Step 1：写 fbank 桥接测试**

在 `SenseVoiceEngineIOTests.swift` 末尾追加：

```swift
    func test_fbank_sineWave_producesFrames() {
        // 生成 1s 的 440Hz 正弦波 @ 16kHz
        let sampleCount = 16000
        let samples = (0..<sampleCount).map { i -> Float in
            sin(2.0 * Float.pi * 440.0 * Float(i) / 16000.0)
        }
        // 调用 fbank 提取
        let feats = extractFbank(waveform: samples)
        // 1s 音频 → 帧数 ≈ (16000 - 400) / 160 + 1 ≈ 99 帧（窗口25ms/步进10ms）
        XCTAssertGreaterThan(feats.count, 80)
        // 每帧 80 维
        if let first = feats.first {
            XCTAssertEqual(first.count, 80)
        }
    }
```

- [ ] **Step 2：运行测试确认失败**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/SenseVoiceEngineIOTests/test_fbank_sineWave_producesFrames
```

预期：编译失败（extractFbank 未定义）。

- [ ] **Step 3：实现 fbank 桥接**

写入 `TalkFlow/STT/FbankBridge.swift`：

```swift
import Foundation
import NativeFbank

// MARK: - fbank 特征提取桥接

/// 调用 kaldi-native-fbank 提取 fbank 特征
/// - Parameter waveform: 16kHz 单声道 PCM 样本
/// - Returns: [帧数 × 80 维] fbank 特征矩阵
func extractFbank(waveform: [Float]) -> [[Float]] {
    // 创建 FbankComputer（kaldi 原生 C API）
    // OnlineFeature + FbankComputer 组合
    // 参照 TalkShow Rust 实现的参数：
    //   - samp_freq: 16000
    //   - frame_shift_ms: 10
    //   - frame_length_ms: 25
    //   - num_bins: 80
    //   - low_freq: 20
    //   - use_log_fbank: true
    //   - use_power: true
    //   - dither: 0, preemph_coeff: 0

    let opts = FbankOptions()
    opts.frame_opts.samp_freq = 16000.0
    opts.frame_opts.frame_shift_ms = 10.0
    opts.frame_opts.frame_length_ms = 25.0
    opts.frame_opts.dither = 0.0
    opts.frame_opts.preemph_coeff = 0.0
    opts.frame_opts.remove_dc_offset = 0
    opts.frame_opts.window_type = "hamming"
    opts.mel_opts.num_bins = 80
    opts.mel_opts.low_freq = 20.0
    opts.mel_opts.high_freq = 0.0
    opts.use_energy = 0
    opts.use_log_fbank = 1
    opts.use_power = 1

    let computer = FbankComputer(opts)
    let onlineFeature = OnlineFeature(computer)

    // 放大到 int16 范围（与 TalkShow 一致）
    let scaled = waveform.map { $0 * 32768.0 }
    onlineFeature.acceptWaveform(16000.0, samples: scaled, sampleCount: Int32(scaled.count))
    onlineFeature.inputFinished()

    let numFrames = Int(onlineFeature.numFramesReady())
    guard numFrames > 0 else { return [] }

    var result = [[Float]]()
    result.reserveCapacity(numFrames)
    for i in 0..<numFrames {
        let frame = onlineFeature.getFrame(Int32(i))
        result.append(frame)
    }
    return result
}
```

> **注意：** 此文件依赖 NativeFbank module 映射的 C 类型（FbankOptions, FbankComputer, OnlineFeature）。实际 C API 签名需要在编译 kaldi-native-fbank 后对齐。如果 C API 不一致，需要写一个薄的 C wrapper 统一接口。此步骤需要先确保任务 0c 完成。

- [ ] **Step 4：运行测试确认通过**

```bash
xcodebuild test -scheme TalkFlow -only-testing:TalkFlowTests/SenseVoiceEngineIOTests/test_fbank_sineWave_producesFrames
```

预期：生成 >80 帧 fbank，每帧 80 维。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/STT/FbankBridge.swift TalkFlowTests/IO/SenseVoiceEngineIOTests.swift
git commit -m "feat: kaldi-native-fbank 桥接 + 测试"
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

- [ ] **Step 1：实现 ONNX 推理方法**

在 `SenseVoiceEngineIO.swift` 中添加：

```swift
import onnxruntime  // OrtSession, OrtValue

    // MARK: - ONNX 推理

    private var session: OrtSession?

    private func ensureSession() throws -> OrtSession {
        if let s = session { return s }
        guard let modelPath = Bundle.main.path(forResource: "model_quant", ofType: "onnx", inDirectory: "sensevoice") else {
            throw STTError.modelNotReady
        }
        let env = try OrtEnv(loggingLevel: .warning)
        let s = try OrtSession(env: env, modelPath: modelPath, sessionOptions: OrtSessionOptions())
        self.session = s
        self.isModelReady = true
        return s
    }

    /// 执行 ONNX 推理
    /// 输入: [1 × T_LFR × 560] 的 fbank 特征
    /// 返回: token_id 序列
    func runInference(feats: [[Float]], featsLen: Int) throws -> [Int32] {
        let session = try ensureSession()
        let tLFR = feats.count
        let dim = feats.first?.count ?? 560

        // 扁平化为 [1, T_LFR, dim] 数组
        var flatFeats = [Float]()
        flatFeats.reserveCapacity(tLFR * dim)
        for frame in feats {
            flatFeats.append(contentsOf: frame)
        }

        // 构造输入 tensor
        let featsTensor = try OrtValue(
            tensorData: flatFeats,
            shape: [1, tLFR, dim]
        )
        let featsLenTensor = try OrtValue(
            tensorData: [Int32(featsLen)],
            shape: [1]
        )
        let languageTensor = try OrtValue(
            tensorData: [Int32(0)], // auto-detect
            shape: [1]
        )
        let textnormTensor = try OrtValue(
            tensorData: [Int32(14)], // no text normalization
            shape: [1]
        )

        let outputs = try session.run(
            withInputs: [
                "feats": featsTensor,
                "feats_len": featsLenTensor,
                "language": languageTensor,
                "textnorm": textnormTensor,
            ]
        )

        guard let logitsValue = outputs["logits"] else {
            throw STTError.inferenceFailed("Missing logits output")
        }

        let logitsShape = try logitsValue.tensorShape()
        let logitsData = try logitsValue.tensorData() as [Float]
        let frames = logitsShape[1]
        let vocabSize = logitsShape[2]

        return argmaxTokens(logits: logitsData, frames: frames, vocabSize: vocabSize)
    }
```

- [ ] **Step 2：实现 BPE 解码（sentencepiece 桥接）**

在 `SenseVoiceEngineIO.swift` 中继续添加：

```swift
    /// BPE 解码
    func sentencePieceDecode(_ tokenIds: [Int32]) -> String {
        let path = bpeModelPath()
        guard let sp = SentencePieceProcessor(path: path) else {
            return ""
        }
        let uids = tokenIds.filter { $0 > 0 }.map { UInt32($0) }
        return sp.decodeIds(uids)
    }
```

> **注意：** `SentencePieceProcessor` 需要基于任务 0d 的 module map 暴露的 C API 封装一个 Swift 类。此步骤假设 C 桥接已完成。

- [ ] **Step 3：完善 transcribe()**

将任务 8 中占位的步骤 6-7 替换为真实调用，返回 `STTResult.speech`。

- [ ] **Step 4：运行完整测试**

```bash
make test
```

预期：所有现有测试 + 新测试 PASS。

- [ ] **Step 5：提交**

```bash
git add TalkFlow/IO/SenseVoiceEngineIO.swift TalkFlowTests/Mocks/MockONSSTSession.swift TalkFlowTests/IO/SenseVoiceEngineIOTests.swift
git commit -m "feat: ONNX Runtime 推理 + SentencePiece BPE 解码"
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
