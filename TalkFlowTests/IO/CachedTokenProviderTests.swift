import XCTest
@testable import TalkFlow

final class CachedTokenProviderTests: XCTestCase {

    // MARK: - 缓存命中：不调 inner

    func test_getAccessToken_returnsCachedToken_whenCacheValid() async throws {
        let mock = MockTokenProviderIO()
        mock.stubbedToken = "token-1"

        let cached = CachedTokenProvider(inner: mock)

        let first = try await cached.getAccessToken()
        XCTAssertEqual(first, "token-1")
        XCTAssertEqual(mock.getTokenCallCount, 1)

        let second = try await cached.getAccessToken()
        XCTAssertEqual(second, "token-1")
        XCTAssertEqual(mock.getTokenCallCount, 1)
    }

    // MARK: - 缓存过期：重新调 inner

    func test_getAccessToken_refreshes_whenCacheExpired() async throws {
        let mock = MockTokenProviderIO()
        mock.stubbedToken = "token-1"

        let cached = CachedTokenProvider(inner: mock, ttl: 0)

        _ = try await cached.getAccessToken()
        XCTAssertEqual(mock.getTokenCallCount, 1)

        mock.stubbedToken = "token-2"
        let second = try await cached.getAccessToken()
        XCTAssertEqual(second, "token-2")
        XCTAssertEqual(mock.getTokenCallCount, 2)
    }

    // MARK: - 错误透传

    func test_getAccessToken_throws_whenInnerThrows() async {
        let mock = MockTokenProviderIO()
        mock.stubbedError = .authenticationFailed("bad sa")

        let cached = CachedTokenProvider(inner: mock)

        do {
            _ = try await cached.getAccessToken()
            XCTFail("Expected authenticationFailed")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .authenticationFailed("bad sa"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        mock.stubbedError = nil
        mock.stubbedToken = "recovered"
        let recovered = try? await cached.getAccessToken()
        XCTAssertEqual(recovered, "recovered")
    }
}
