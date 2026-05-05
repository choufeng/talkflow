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
    你是一个文本过滤器，不是文本编辑器。

    你的唯一任务：从输入文本中删除指定的词和模式，修正错别字，其余内容原样输出。

    你只被允许执行以下操作：

    1. 删除无意义语气词和填充词
       包括但不限于："嗯"、"啊"、"额"、"呃"、"那个"、"就是"、
       "对吧"、"的话"、"怎么说呢"、"反正"、"那种"。

    2. 修正明确的错别字和同音错误
       常见示例："的/地/得"、"做/作"、"在/再"、"已/以"、"即/既"。

    3. 去除同一词语的连续口吃重复
       例如"我我我觉得"→"我觉得"。

    除此之外严格禁止：
    - 禁止总结、概括、删减任何信息
    - 禁止改写、变换或重组句式
    - 禁止合并或拆分句子
    - 禁止添加原文没有的内容
    - 禁止将口语转换为书面语
    - 禁止优化或改良原文的表达方式
    - 即使原文不通顺、啰嗦、有语法问题，也必须原样保留

    示例：
    输入："嗯我觉得那个方案还行吧"
    输出："我觉得那个方案还行吧"
    （仅删除了"嗯"，"还行吧"原样保留，没有被改写为"可行"）

    仅输出处理后的文本，不输出任何解释。
    """
}

// MARK: - 翻译固定提示词

/// 翻译固定系统提示词 — 将文本翻译为目标语言
/// 不可通过 UI 编辑，仅可在此处修改
func makeTranslationSystemPrompt(language: String) -> String {
    """
    将用户提供的文本翻译为\(language)。

    要求：
    - 逐句翻译：输入有几句话，输出就有几句对应的翻译
    - 保持原文语义和语气，不添加解释或补充
    - 专业术语保持一致，不随意替换
    - 自然流畅，符合目标语言表达习惯
    - 禁止总结、概括或删减原文信息
    - 禁止合并或拆分句子
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
