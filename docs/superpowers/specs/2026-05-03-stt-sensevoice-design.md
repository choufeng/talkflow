# TalkFlow 本地语音转文字（STT）设计

> 日期：2026-05-03
> 分支：`feature/local-voice-recognition`（延续）

## 1. 目标

在现有录音模块基础上，实现本地离线语音转文字（STT），录音完成后自动转为文本。

## 2. 引擎选型

**SenseVoiceSmall + ONNX Runtime**，理由：
- Qwen3-ASR-Flash 是 LLM 构架，不适用于本地桌面端
- Apple Speech Framework 不允许自定义模型
- whisper.cpp 仅支持 Whisper 架构

模型来源：`haixuantao/SenseVoiceSmall-onnx`（HuggingFace），TalkShow 项目已验证。

## 3. 模型文件（共 4 个文件，~242MB）

打入 App Bundle，非运行时下载：

| 文件 | 大小 | 作用 |
|------|------|------|
| `model_quant.onnx` | ~241MB | 量化后的 SenseVoiceSmall ONNX 模型 |
| `am.mvn` | ~11KB | CMVN 归一化参数（均值+方差） |
| `chn_jpn_yue_eng_ko_spectok.bpe.model` | ~378KB | SentencePiece BPE 词表 |
| `tokens.json` | ~352KB | Token 到文本映射 |

文件放入 `Resources/sensevoice/`，运行时直接从 Bundle 读取。

## 4. 运行时依赖

| 依赖 | 集成方式 | 用途 |
|------|----------|------|
| `onnxruntime.xcframework` | 手动管理，拖入 Xcode 项目 | ONNX 模型推理 |
| `kaldi-native-fbank` | C 桥接 + module map | fbank 特征提取 |
| `sentencepiece` | C 桥接 + module map | BPE tokenizer 解码 |

## 5. 目录结构

```
TalkFlow/
├── IO/
│   ├── AudioRecorderIO.swift          ← 已有
│   ├── SenseVoiceIO.swift             ← 新增：协议
│   └── SenseVoiceEngineIO.swift       ← 新增：实现
├── Utils/
│   ├── RecordingState.swift           ← 已有
│   ├── FbankFeature.swift             ← 新增：LFR/CMVN 纯函数
│   ├── TokenDecoder.swift             ← 新增：BPE 解码
│   └── STTResult.swift                ← 新增：ADT
├── STT/
│   ├── NativeFbank/                   ← C 桥接：kaldi-native-fbank
│   │   ├── include/
│   │   │   └── kaldi-native-fbank/csrc/*.h
│   │   ├── libkaldi-native-fbank.a
│   │   └── module.modulemap
│   └── SentencePiece/                 ← C 桥接：sentencepiece
│       ├── include/
│       │   └── sentencepiece/
│       ├── libsentencepiece.a
│       └── module.modulemap
└── Resources/
    ├── sensevoice/
    │   ├── model_quant.onnx
    │   ├── am.mvn
    │   ├── chn_jpn_yue_eng_ko_spectok.bpe.model
    │   └── tokens.json
    └── onnxruntime.xcframework/       ← 手动管理
```

## 6. 协议设计

```swift
protocol SenseVoiceIO {
    var isModelReady: Bool { get }
    func transcribe(url: URL) async throws -> STTResult
}
```

模型就绪状态由引擎内部在 `init` 时通过 `Bundle.module` 加载 `.onnx` 判定，不需要外部干预。

## 7. ADT

```swift
enum STTResult: Equatable {
    case silence                              // 静音（音频 < 4800 样本 = 0.3s）
    case speech(text: String, language: String)
    case failure(STTError)
}

enum STTError: Error, Equatable {
    case modelNotReady
    case audioDecodeFailed
    case inferenceFailed(String)
}
```

## 8. 处理流水线

```
录音文件(.m4a)
  → AVFoundation 解码 PCM
  → vDSP 重采样 16kHz 单声道
  → [C桥接] kaldi-native-fbank 提取 fbank [N帧 × 80维]
  → [纯Swift] LFR(7,6) → [T_LFR × 560维]
  → [纯Swift] CMVN 归一化 (am.mvn 参数)
  → ONNX 推理 (4输入: feats, feats_len, language=0, textnorm=14)
  → argmax 取 token_id 序列
  → [C桥接] sentencepiece BPE 解码
  → [纯Swift] 正则去除 <|tag|> → STTResult
```

- `language=0`：自动检测
- `textnorm=14`：不做文本规整化（保留原始识别结果）
- 音频 < 4800 样本（~0.3s）判定为静音

## 9. C 桥接层

### 9.1 kaldi-native-fbank

仅使用最少 API：

```c
// kaldi-native-fbank/csrc/online-feature.h
void* FbankComputer_New(/* opts */);
void OnlineFeature_AcceptWaveform(void* self, float sampling_rate, float* samples, int32_t n);
int32_t OnlineFeature_NumFrames(void* self);
int32_t OnlineFeature_GetFrame(void* self, int32_t frame, float* output, int32_t dim);
void FbankComputer_Delete(void* self);
```

### 9.2 sentencepiece

仅使用最少 API：

```c
// sentencepiece/src/sentencepiece_processor.h
void* spp_new(void);
int spp_load(void* self, const char* filename);
int spp_decode_ids(void* self, const uint32_t* ids, int len, char** output);
void spp_free_output(char* output);
void spp_delete(void* self);
```

## 10. 纯函数模块

### 10.1 fbank 后处理（LFR + CMVN）

```swift
/// LFR: 低帧率拼接 (m=7, n=6)
func applyLFR(feats: [[Float]]) -> [[Float]]

/// CMVN: 均值方差归一化
func applyCMVN(feats: [[Float]], means: [Double], vars: [Double]) -> [[Float]]
```

### 10.2 Token 解码与后处理

```swift
/// argmax: 从 ONNX 输出 logits 取每帧最大 token
func argmaxTokens(logits: [Float], frames: Int, vocabSize: Int) -> [Int32]

/// 正则去除 <|tag|>
func postprocess(_ text: String) -> String
```

## 11. 集成点

AppDelegate 中，`onRecordingComplete` 回调串联 STT：

```swift
let sttEngine = SenseVoiceEngineIO()

onRecordingComplete = { [weak self] url in
    Task {
        let result = try await sttEngine.transcribe(url: url)
        await MainActor.run {
            switch result {
            case .speech(let text, _):
                // 下一步：展示/复制到剪贴板/传给 LLM
            case .silence:
                // 忽略
            case .failure(let error):
                // 错误处理
            }
        }
    }
}
```

## 12. 测试策略

| 层 | 内容 | 覆盖率 |
|---|---|---|
| `Utils/FbankFeature.swift` | LFR、CMVN | 100% |
| `Utils/TokenDecoder.swift` | argmax、postprocess | 100% |
| `IO/SenseVoiceEngineIO.swift` | Mock ONNX session，验证预处理/后处理 | ≥90% |
| 集成测试 | TalkShow 相同音频端到端对比输出 | 定性通过 |

- Mock 策略：ONNX session 替换为返回固定 token 序列的假 session，验证输入 tensor shape 正确性
- 端到端集成测试以 TalkShow 的输出为 golden reference

## 13. 不在范围内

- 流式/实时转写（当前为整段批处理）
- 模型切换/热更新
- 说话人识别
- 情感/事件检测（SenseVoice 内置能力暂不暴露）
