import Foundation
@testable import TalkFlow

// MARK: - 测试用例

struct PromptTestCase: Equatable {
    let name: String
    let input: String
    let workflow: Workflow

    init(name: String, input: String, workflow: Workflow) {
        self.name = name
        self.input = input
        self.workflow = workflow
    }
}

// MARK: - 默认测试用例集

let defaultPromptTestCases: [PromptTestCase] = [
    PromptTestCase(
        name: "正常口语",
        input: "嗯我觉得那个这个方案还行吧",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "长段落",
        input: "嗯大家好那个我今天想跟各位分享一下关于我们最近在做的一个项目的情况怎么说呢这个项目其实从去年年底就开始规划了对吧然后经过几个月的时间我们团队一直在努力推进那个目前来看的话进展还算比较顺利就是还有一些细节的地方需要再打磨一下呃总体来说我对此还是比较有信心的",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "大量语气词",
        input: "嗯那个就是呃怎么说呢反正吧我觉得对吧这个东西啊其实对吧就是那么回事对吧你懂我意思吧嗯啊",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "技术术语",
        input: "嗯我们那个在Kubernetes集群里面用了Istio做那个服务网格然后就是那个Sidecar注入之后发现延迟有点高啊大概就是P99延迟从50毫秒涨到了200毫秒",
        workflow: .transcription
    ),
    PromptTestCase(
        name: "翻译用例",
        input: "嗯我觉得这个产品设计思路还是不错的但是那个细节方面可能还需要再打磨一下比如说用户体验这块",
        workflow: .translation
    ),
]
