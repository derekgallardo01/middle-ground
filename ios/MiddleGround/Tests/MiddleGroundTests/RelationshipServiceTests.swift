import XCTest
@testable import MiddleGround

/// Covers the pairing flow, which is what unblocks request creation:
/// before a second participant joins, `canSubmit` can never become true.
final class RelationshipServiceTests: XCTestCase {
    private func makeService() -> (RelationshipService, MockRelationshipRepository) {
        let repository = MockRelationshipRepository()
        let service = RelationshipService(repository: repository, userRepository: MockUserRepository())
        return (service, repository)
    }

    func testCreatedRelationshipStartsUnpairedWithAnInviteCode() async throws {
        let (service, _) = makeService()

        let relationship = try await service.createRelationship(type: .couple, ownerID: "owner")

        XCTAssertEqual(relationship.participantIDs, ["owner"])
        XCTAssertFalse(relationship.isPaired)
        XCTAssertEqual(relationship.inviteCode.count, 6)
        XCTAssertNil(relationship.partnerID(excluding: "owner"))
    }

    func testJoiningWithInviteCodeAddsTheSecondParticipant() async throws {
        let (service, _) = makeService()
        let created = try await service.createRelationship(type: .couple, ownerID: "owner")

        let joined = try await service.join(inviteCode: created.inviteCode, userID: "partner")

        XCTAssertTrue(joined.isPaired)
        XCTAssertEqual(joined.participantIDs, ["owner", "partner"])
        XCTAssertEqual(joined.partnerID(excluding: "owner"), "partner")
        XCTAssertEqual(joined.partnerID(excluding: "partner"), "owner")
    }

    func testInviteCodeIsCaseAndPunctuationInsensitive() async throws {
        let (service, _) = makeService()
        let created = try await service.createRelationship(type: .friends, ownerID: "owner")

        let messy = created.inviteCode.lowercased().split(every: 3).joined(separator: "-")
        let joined = try await service.join(inviteCode: messy, userID: "partner")

        XCTAssertEqual(joined.participantIDs, ["owner", "partner"])
    }

    func testUnknownCodeThrows() async throws {
        let (service, _) = makeService()

        do {
            _ = try await service.join(inviteCode: "ZZZZZZ", userID: "partner")
            XCTFail("expected codeNotFound")
        } catch {
            XCTAssertEqual(error as? RelationshipService.PairingError, .codeNotFound)
        }
    }

    func testRedeemingYourOwnCodeThrows() async throws {
        let (service, _) = makeService()
        let created = try await service.createRelationship(type: .couple, ownerID: "owner")

        do {
            _ = try await service.join(inviteCode: created.inviteCode, userID: "owner")
            XCTFail("expected ownCode")
        } catch {
            XCTAssertEqual(error as? RelationshipService.PairingError, .ownCode)
        }
    }

    func testJoiningTwiceThrows() async throws {
        let (service, _) = makeService()
        let created = try await service.createRelationship(type: .couple, ownerID: "owner")
        _ = try await service.join(inviteCode: created.inviteCode, userID: "partner")

        do {
            _ = try await service.join(inviteCode: created.inviteCode, userID: "partner")
            XCTFail("expected alreadyJoined")
        } catch {
            XCTAssertEqual(error as? RelationshipService.PairingError, .alreadyJoined)
        }
    }

    func testDisplayLabelsPreferPartnerNameOverRelationshipType() async throws {
        let (service, repository) = makeService()
        // Relationship.preview pairs User.preview ("Alex") with User.preview2 ("Sam").
        let labels = await service.displayLabels(for: [.preview], currentUserID: User.preview.id)

        XCTAssertEqual(labels[Relationship.preview.id], User.preview2.name)

        // With no partner joined, fall back to the type name rather than showing nothing.
        let solo = try await service.createRelationship(type: .roommates, ownerID: User.preview.id)
        _ = repository
        let soloLabels = await service.displayLabels(for: [solo], currentUserID: User.preview.id)
        XCTAssertEqual(soloLabels[solo.id], RelationshipType.roommates.displayName)
    }

    func testGeneratedCodesAvoidAmbiguousCharacters() {
        let ambiguous = Set("O0I1L")
        for _ in 0..<200 {
            let code = Relationship.generateInviteCode()
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { !ambiguous.contains($0) }, "\(code) contains an ambiguous character")
        }
    }
}

private extension String {
    func split(every stride: Int) -> [String] {
        Swift.stride(from: 0, to: count, by: stride).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: stride, limitedBy: endIndex) ?? endIndex
            return String(self[start..<end])
        }
    }
}
