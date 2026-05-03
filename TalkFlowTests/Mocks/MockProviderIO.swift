import Foundation
@testable import TalkFlow

final class MockProviderIO: ProviderIO {

    var sendCallCount = 0
    var sendLastRequest: ChatRequest?

    var stubbedResponse: ChatResponse?
    var stubbedError: ProviderError?

    func send(_ request: ChatRequest) async throws -> ChatResponse {
        sendCallCount += 1
        sendLastRequest = request

        if let error = stubbedError {
            throw error
        }

        guard let response = stubbedResponse else {
            throw ProviderError.networkError("Mock: 未预设返回值")
        }

        return response
    }
}
