import XCTest
@testable import TalkFlow

final class PromptOptimizerIOTests: XCTestCase {

    func test_optimize_nonEmptyInput_returnsOptimized() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "1. 保持口语化风格\n2. 不要改变语义")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        let result = try await optimizer.optimize("保持口语化风格不要改变语义")

        XCTAssertEqual(result, "1. 保持口语化风格\n2. 不要改变语义")
        XCTAssertEqual(mockProvider.sendCallCount, 1)
    }

    func test_optimize_emptyInput_returnsEmpty() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        let result = try await optimizer.optimize("")

        XCTAssertEqual(result, "")
        XCTAssertEqual(mockProvider.sendCallCount, 1)
    }

    func test_optimize_whitespaceOnly_returnsEmpty() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        let result = try await optimizer.optimize("   ")

        XCTAssertEqual(result, "")
    }

    func test_optimize_promptContainsRawInput() async throws {
        let mockProvider = MockProviderIO()
        mockProvider.stubbedResponse = ChatResponse(content: "优化后")

        let optimizer = PromptOptimizerIO(provider: mockProvider)
        _ = try await optimizer.optimize("我的自定义提示词")

        let req = mockProvider.sendLastRequest
        let content = req?.messages.first?.content ?? ""
        XCTAssertTrue(content.contains("我的自定义提示词"), "应包含用户原始提示词")
    }
}
