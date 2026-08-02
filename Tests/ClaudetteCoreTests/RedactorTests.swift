import XCTest
@testable import ClaudetteCore

final class RedactorTests: XCTestCase {
    func testStripsAnthropicTokens() {
        let input = "request failed: Bearer sk-ant-oat01-Ab9_x-Yz-123 rejected"
        let output = Redactor.scrub(input)
        XCTAssertFalse(output.contains("sk-ant"))
        XCTAssertTrue(output.contains("[token]"))
    }

    func testStripsEmails() {
        let output = Redactor.scrub("user taylor@developerhut.co.za hit an error")
        XCTAssertFalse(output.contains("developerhut"))
        XCTAssertTrue(output.contains("[email]"))
    }

    func testStripsUUIDs() {
        let output = Redactor.scrub("org 6f9619ff-8b86-4d01-b42d-00cf4fc964ff failed")
        XCTAssertFalse(output.contains("6f9619ff"))
        XCTAssertTrue(output.contains("[uuid]"))
    }

    func testReplacesHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let output = Redactor.scrub("open \(home)/Library/Caches/thing failed")
        XCTAssertFalse(output.contains(home))
        XCTAssertTrue(output.contains("~/Library/Caches/thing"))
    }

    func testReplacesForeignUsersPaths() {
        let output = Redactor.scrub("could not read /Users/somebody/dev/x.txt")
        XCTAssertFalse(output.contains("somebody"))
    }

    func testStripsProjectDirectoryNames() {
        let input = "scan failed at ~/.claude/projects/-Users-taylor-secret-startup/9.jsonl"
        let output = Redactor.scrub(input)
        XCTAssertFalse(output.contains("secret-startup"))
        XCTAssertTrue(output.contains("projects/…"))
    }

    func testTruncatesTo2KB() {
        let long = String(repeating: "a", count: 10_000)
        let output = Redactor.scrub(long)
        XCTAssertLessThanOrEqual(output.utf8.count, Redactor.maxLength + 8)
        XCTAssertTrue(output.hasSuffix("…"))
    }

    func testRealisticStackTraceSurvivesNothingSensitive() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let input = """
        Fatal error at \(home)/.claude/projects/-Users-taylor-clientwork/session-abc.jsonl:42
        token=sk-ant-oat01-secretsecret account=taylor@developerhut.co.za \
        org=123e4567-e89b-42d3-a456-426614174000
        """
        let output = Redactor.scrub(input)
        XCTAssertFalse(output.contains("sk-ant"))
        XCTAssertFalse(output.contains("@developerhut"))
        XCTAssertFalse(output.contains("clientwork"))
        XCTAssertFalse(output.contains("123e4567"))
        XCTAssertFalse(output.contains(home))
    }
}
