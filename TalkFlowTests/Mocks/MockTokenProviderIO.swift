import Foundation
@testable import TalkFlow

final class MockTokenProviderIO: TokenProviderIO {

    var getTokenCallCount = 0

    var stubbedToken: String?
    var stubbedError: ProviderError?

    func getAccessToken() async throws -> String {
        getTokenCallCount += 1

        if let error = stubbedError {
            throw error
        }

        guard let token = stubbedToken else {
            throw ProviderError.authenticationFailed("Mock: 未预设 token")
        }

        return token
    }
}
