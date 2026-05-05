# 提示词评测框架 + 一键优化

**日期**: 2026-05-05  
**状态**: 已批准

## 功能 1：提示词评测框架

### 目标

开发时验证提示词（润色 + 翻译）效果，改动提示词后跑一批测试用例确认无回归。

### 架构

```
TalkFlowTests/PromptEvaluation/
├── RuleEvaluator.swift          # 纯函数：量化指标检查
├── LLMEvaluator.swift           # IO 层：调用 Gemini 语义评判
├── PromptTestCases.swift        # 测试数据集
└── PromptEvaluationTests.swift  # XCTest 入口
```

### 规则层（纯函数）

对输入/输出文本对做量化检测，零成本：

| 指标 | 计算 | 阈值 |
|------|------|------|
| 字数比 | output.charCount / input.charCount | < 0.3 → FAIL |
| 空输出 | output.isEmpty | → FAIL |
| 输出过长 | output.charCount / input.charCount | > 1.5 → FAIL |
| 中文占比 | CJK 字符 / 总字符 | < 0.5 → FAIL（仅润色流程） |

```swift
struct RuleEvalConfig: Codable, Equatable {
    var minCharRatio: Double = 0.3
    var maxCharRatio: Double = 1.5
    var minCJKRatio: Double = 0.5
}

struct RuleEvalResult: Equatable {
    let passed: Bool
    let violations: [String]
}

func evaluateRules(input: String, output: String, config: RuleEvalConfig) -> RuleEvalResult
```

### LLM 评判层（IO）

规则通过后，用 Gemini 评判语义保真度：

```
对以下 STT 润色结果打分（0-10），评判标准：

1. 信息保真度：输出是否保留了输入的全部信息？有无遗漏？
2. 无过度总结：输出是否为逐句对应？有无大幅压缩或概括？
3. 仅执行允许的操作：是否只做了去语气词、修错别字、去口吃？

输入: <原文>
输出: <润色结果>

返回严格 JSON: {"score": <int>, "issues": [<string>], "verdict": "pass"|"fail"}
```

- score >= 7 → pass
- score < 7 → fail，记录 issues

### 测试用例

手工维护的输入文本数组，不设期望输出（由规则 + LLM 评判替代）：

```swift
struct PromptTestCase: Equatable {
    let name: String           // "超长输入", "大量语气词", ...
    let input: String          // 原始文本
    let workflow: Workflow     // .transcription / .translation
}

let defaultTestCases: [PromptTestCase] = [
    PromptTestCase(name: "正常口语", input: "嗯我觉得那个这个方案还行吧", workflow: .transcription),
    PromptTestCase(name: "长段落", input: "嗯大家好那个我今天想跟各位分享一下关于我们最近在做的一个项目的情况怎么说呢这个项目其实从去年年底就开始规划了对吧然后经过几个月的时间我们团队一直在努力推进那个目前来看的话进展还算比较顺利就是还有一些细节的地方需要再打磨一下呃总体来说我对此还是比较有信心的", workflow: .transcription),
    PromptTestCase(name: "大量语气词", input: "嗯那个就是呃怎么说呢反正吧我觉得对吧这个东西啊其实对吧就是那么回事对吧你懂我意思吧嗯啊", workflow: .transcription),
    PromptTestCase(name: "技术术语", input: "嗯我们那个在Kubernetes集群里面用了Istio做那个服务网格然后就是那个Sidecar注入之后发现延迟有点高啊大概就是P99延迟从50毫秒涨到了200毫秒", workflow: .transcription),
    PromptTestCase(name: "翻译用例", input: "嗯我觉得这个产品设计思路还是不错的但是那个细节方面可能还需要再打磨一下比如说用户体验这块", workflow: .translation),
]
```

### 评测流程

```
测试用例 → 跳过 STT，直接用文本 → Vertex AI 执行润色/翻译
       → 规则层检查
         → FAIL → 测试直接失败
         → PASS → LLM 评判层
                → PASS → 用例通过
                → FAIL → 用例失败，输出详情
```

### 关键决策

- **不跑 CI**：依赖 Vertex AI API，耗时 + 成本。单独 test scheme 或 `#if DEBUG` 条件编译
- **复用现有 Provider**：不引入新 LLM 依赖，用 `VertexAIIO` 做评判
- **无黄金输出**：用规则 + 评判替代手工期望值


## 功能 2：提示词一键优化

### 目标

用户在转写/翻译设置卡片中填写补充提示词后，点击"优化并保存"，LLM 优化内容结构后回填输入框并保存。

### UI

```
┌─ 转写 ──────────────────────────┐
│ 润色要求:                     │
│ ┌──────────────────────────┐   │
│ │ 保持口语化风格...        │   │
│ └──────────────────────────┘   │
│ [✨ 优化并保存]                │  ← 新增按钮
└────────────────────────────────┘
```

翻译设置卡片同理。

### 行为

```
点击 → 取输入框当前文本
     → 发 Vertex AI 请求，用优化 prompt 改写
     → 优化结果回填输入框
     → 自动保存到 AppConfig
```

### 优化 Prompt

```
优化以下用户自定义提示词，使其更清晰、无歧义、不矛盾：

原则：
- 结构化：如有多个要求，用编号或分段
- 删除与"去语气词、修错别字、去口吃重复"矛盾的内容
- 删除暗示总结、改写、概括的任何表述
- 如果输入为空或仅有空白，返回空字符串
- 仅输出优化后的提示词文本，不输出解释或任何其他内容

用户原始提示词：
<输入框内容>
```

### 副作用标注

- 按钮旁提示文案："将调用 LLM 优化，可能消耗 API 配额"
- 调用期间按钮禁用并显示加载态
- 失败时不覆盖原有输入框内容，弹错误提示

### 实现位置

- `TranscriptionSettingsView.swift`：新增按钮 + 动作
- `TranslationSettingsView.swift`：新增按钮 + 动作
- 优化调用复用 `VertexAIIO`，新建 `PromptOptimizerIO.swift` 封装优化 prompt
