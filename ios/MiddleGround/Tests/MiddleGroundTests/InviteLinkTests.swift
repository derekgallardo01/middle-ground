import XCTest
@testable import MiddleGround

/// Reading an invite code out of a link, and — more importantly — refusing to read one out of
/// anything else.
///
/// The code used to travel only as prose in a message, which the recipient had to notice, copy,
/// and retype after an App Store detour. Carrying it in the link removes all of that, and makes
/// the parser the thing standing between somebody and a group they never asked to join.
final class InviteLinkTests: XCTestCase {
    private func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            XCTFail("not a URL: \(string)")
            return URL(string: "https://example.com")!
        }
        return url
    }

    func testReadsTheCodeFromAnInviteLink() {
        XCTAssertEqual(
            Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/MG24KT")),
            "MG24KT"
        )
    }

    /// The link is built by `AppConfiguration.inviteURL`, so the two have to agree — a change to
    /// either alone would leave every invite opening a page that cannot help.
    func testTheLinkTheAppSharesIsOneItCanRead() {
        let shared = AppConfiguration.inviteURL(code: "MG7QP2")
        XCTAssertEqual(Relationship.inviteCode(fromLink: shared), "MG7QP2")
    }

    func testACodeIsNormalisedTheSameWayTypedInputIs() {
        XCTAssertEqual(
            Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/mg24kt")),
            "MG24KT"
        )
    }

    // MARK: - What it must refuse

    /// Every other page on the site is read by people who do not have the app. Claiming them
    /// would send somebody reading the privacy policy into the App Store instead.
    func testOtherPagesAreNotInvites() {
        for path in ["privacy", "terms", "support", "changelog", ""] {
            XCTAssertNil(
                Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/\(path)")),
                "/\(path) is not an invite"
            )
        }
    }

    func testAnotherHostIsRefused() {
        XCTAssertNil(
            Relationship.inviteCode(fromLink: url("https://seekmiddleground.evil.com/join/MG24KT"))
        )
        XCTAssertNil(Relationship.inviteCode(fromLink: url("https://example.com/join/MG24KT")))
    }

    func testPlainHTTPIsRefused() {
        XCTAssertNil(Relationship.inviteCode(fromLink: url("http://seekmiddleground.com/join/MG24KT")))
    }

    func testATrailOfExtraSegmentsIsRefused() {
        XCTAssertNil(
            Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/MG24KT/extra"))
        )
    }

    func testAMalformedCodeIsRefused() {
        // Too short, too long, and empty. A code is exactly six characters, so anything else was
        // either mistyped or is not a code at all — and guessing is how somebody lands in the
        // wrong group.
        XCTAssertNil(Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/MG24")))
        XCTAssertNil(Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/MG24KTXX")))
        XCTAssertNil(Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/")))
    }

    /// The alphabet excludes I, L, O, 0 and 1 because they are misread; a link containing them
    /// is not a code this app ever issued.
    func testCharactersOutsideTheAlphabetAreRefused() {
        XCTAssertNil(Relationship.inviteCode(fromLink: url("https://seekmiddleground.com/join/OIL011")))
    }
}
