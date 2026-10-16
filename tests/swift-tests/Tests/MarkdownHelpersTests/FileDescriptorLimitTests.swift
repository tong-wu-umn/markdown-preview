import Foundation
import XCTest
@testable import MarkdownHelpers

final class FileDescriptorLimitTests: XCTestCase {
    private var original = rlimit()

    override func setUpWithError() throws {
        XCTAssertEqual(getrlimit(RLIMIT_NOFILE, &original), 0)
    }

    override func tearDown() {
        var restore = original
        setrlimit(RLIMIT_NOFILE, &restore)
    }

    func testRaisesLaunchServicesDefaultOf256() throws {
        try setSoftLimit(256)

        let result = FileDescriptorLimit.raiseSoftLimit()

        let expected = min(FileDescriptorLimit.target, original.rlim_max)
        XCTAssertEqual(result, expected)
        XCTAssertEqual(currentSoftLimit(), expected)
    }

    func testNeverLowersAHigherLimit() throws {
        try setSoftLimit(512)

        let result = FileDescriptorLimit.raiseSoftLimit(to: 300)

        XCTAssertEqual(result, 512)
        XCTAssertEqual(currentSoftLimit(), 512)
    }

    private func setSoftLimit(_ value: rlim_t) throws {
        var limit = original
        limit.rlim_cur = value
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            throw XCTSkip("Cannot set RLIMIT_NOFILE soft limit to \(value)")
        }
    }

    private func currentSoftLimit() -> rlim_t {
        var limit = rlimit()
        getrlimit(RLIMIT_NOFILE, &limit)
        return limit.rlim_cur
    }
}
