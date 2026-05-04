import Foundation

/// 提示词配置：默认系统提示词 + 用户补充内容
struct PromptConfig: Codable, Equatable {
    let defaultPrompt: String
    var userSupplement: String
}

// MARK: - 纯函数

/// 合并默认提示词与用户补充
/// - 无补充时仅返回默认提示词
/// - 有补充时以换行拼接
func mergePrompts(_ config: PromptConfig) -> String {
    if config.userSupplement.isEmpty {
        return config.defaultPrompt
    }
    return "\(config.defaultPrompt)\n\(config.userSupplement)"
}

// MARK: - 转写润色固定提示词

/// 转写润色固定系统提示词 — 通用 ASR 后处理规则
/// 不可通过 UI 编辑，仅可在此处修改
func makePolishingSystemPrompt() -> String {
    """
    去除中文口语中常见的无意义语气词和填充词，包括但不限于：
    "嗯"、"啊"、"额"、"呃"、"那个"、"就是"、"然后"、"对吧"、"的话"、"怎么说呢"。
    注意保留有实际语义的词语，例如"然后"在表示时间顺序时应保留。不要改变原文的语义和语气。

    识别并修正文本中的错别字、同音错误和常见输入法导致的文字错误。
    只修正明确的错误，不要对有歧义的内容做主观改动。
    常见的同音错误示例："的/地/得"、"做/作"、"在/再"、"已/以"、"即/既"。
    """
}

// MARK: - 翻译固定提示词

/// 翻译固定系统提示词 — 将文本翻译为目标语言
/// 不可通过 UI 编辑，仅可在此处修改
func makeTranslationSystemPrompt(language: String) -> String {
    """
    将用户提供的文本翻译为\(language)。

    要求：
    - 保持原文语义和语气，不添加额外解释
    - 专业术语保持一致，不随意替换
    - 自然流畅，符合目标语言表达习惯
    - 仅输出翻译结果，不输出原文或其他内容
    """
}

// MARK: - 润色+翻译提示词合并

/// 合并润色提示词与翻译提示词，用于翻译流程的一次 LLM 调用
/// 顺序：润色固定 + 润色补充 + 翻译固定 + 翻译补充
func mergeTranslationPrompts(
    polishConfig: PromptConfig,
    translationConfig: PromptConfig
) -> String {
    let polishPart = mergePrompts(polishConfig)
    let translationPart = mergePrompts(translationConfig)
    return "\(polishPart)\n\(translationPart)"
}
