// TalkFlowTests/Helpers/XCTestCaseAsync.swift
import XCTest

extension XCTestCase {
    /// 对 async 表达式做相等断言的便捷方法
    func assertAsync<T: Equatable>(
        timeout _: TimeInterval = 1.0,
        _ expression: @escaping () async -> T,
        equals expected: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let result = await expression()
        XCTAssertEqual(result, expected, file: file, line: line)
    }
}
