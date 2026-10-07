import XCTest
@testable import NewRepoCore

final class RepoNameValidatorTests: XCTestCase {
    func testValidNames() {
        for name in ["repo", "my-repo", "my_repo", "my.repo", ".github", "A1-b2_c3.d4", String(repeating: "a", count: 100)] {
            XCTAssertEqual(RepoNameValidator.validate(name), .valid, name)
        }
    }

    func testEmpty() {
        XCTAssertEqual(RepoNameValidator.validate(""), .empty)
    }

    func testInvalidNames() {
        for name in ["my repo", "repo!", "café", "a/b", ".", "..", "repo.git", "Repo.GIT", String(repeating: "a", count: 101)] {
            guard case .invalid = RepoNameValidator.validate(name) else {
                return XCTFail("\(name) should be invalid")
            }
        }
    }

    func testSuggestions() {
        XCTAssertEqual(RepoNameValidator.suggestion(for: "My Cool Repo!"), "My-Cool-Repo")
        XCTAssertEqual(RepoNameValidator.suggestion(for: "  spaced  out  "), "spaced-out")
        XCTAssertEqual(RepoNameValidator.suggestion(for: "thing.git"), "thing")
        XCTAssertNil(RepoNameValidator.suggestion(for: "already-valid"))
        XCTAssertNil(RepoNameValidator.suggestion(for: "!!!"))
    }
}
