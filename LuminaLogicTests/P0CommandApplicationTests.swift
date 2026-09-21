import XCTest
@testable import Lumina

final class P0CommandApplicationTests: XCTestCase {
    func testApplyAndUndoCullUseTheSameCommandSemantics() throws {
        let id = UUID()
        let priorDecisionDate = Date(timeIntervalSince1970: 100)
        let commitDate = Date(timeIntervalSince1970: 200)
        var assets = [makeAsset(id: id, cull: .reject, userDecidedAt: priorDecisionDate)]
        var order = FinalSetOrder(assetIDs: [id])
        let recipeBefore = assets[0].recipe
        let command = CullMutationCommand(
            createdAt: commitDate,
            assetID: id,
            before: .reject,
            after: .keep,
            userDecidedAtBefore: priorDecisionDate,
            userDecidedAtAfter: commitDate,
            finalOrderBefore: [id],
            finalOrderAfter: [id]
        )

        XCTAssertTrue(command.apply(to: &assets, finalOrder: &order))
        XCTAssertEqual(assets[0].cull, .keep)
        XCTAssertEqual(assets[0].userDecidedAt, commitDate)
        XCTAssertEqual(assets[0].recipe, recipeBefore)

        XCTAssertTrue(command.revert(in: &assets, finalOrder: &order))
        XCTAssertEqual(assets[0].cull, .reject)
        XCTAssertEqual(assets[0].userDecidedAt, priorDecisionDate)
        XCTAssertEqual(assets[0].recipe, recipeBefore)
        XCTAssertEqual(order.assetIDs, [id])
    }

    func testApplyAndUndoEditUseTheSameCommandSemantics() {
        let id = UUID()
        let before = EditRecipe(exposure: 0.2)
        let after = before.updating {
            $0.exposure = 0.8
            $0.contrast = 12
        }
        var assets = [makeAsset(id: id, cull: .keep, recipe: before)]
        let command = EditMutationCommand(assetID: id, before: before, after: after)

        XCTAssertTrue(command.apply(to: &assets))
        XCTAssertEqual(assets[0].recipe, after)
        XCTAssertEqual(assets[0].cull, .keep)

        XCTAssertTrue(command.revert(in: &assets))
        XCTAssertEqual(assets[0].recipe, before)
        XCTAssertEqual(assets[0].cull, .keep)
    }

    func testRapidCommittedCommandSequenceReversesExactly() {
        let id = UUID()
        var assets = [makeAsset(id: id)]
        var commands: [EditMutationCommand] = []

        for step in 1...100 {
            let before = assets[0].recipe ?? .neutral
            let after = before.updating { $0.exposure = Double(step) / 100 }
            let command = EditMutationCommand(assetID: id, before: before, after: after)
            XCTAssertTrue(command.apply(to: &assets))
            commands.append(command)
        }
        XCTAssertEqual(assets[0].recipe?.exposure, 1)

        for command in commands.reversed() {
            XCTAssertTrue(command.revert(in: &assets))
        }
        XCTAssertNil(assets[0].recipe)
    }

    func testCommittedCommandSurvivesStoreRestart() async throws {
        let priorRoot = UITestSupport.stateDirectoryOverride
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumina-command-restart-\(UUID().uuidString)", isDirectory: true)
        UITestSupport.stateDirectoryOverride = root
        defer {
            UITestSupport.stateDirectoryOverride = priorRoot
            try? FileManager.default.removeItem(at: root)
        }

        let id = UUID()
        var shoot = ShootRecord(name: "command-restart", assets: [makeAsset(id: id)])
        let command = CullMutationCommand(
            assetID: id,
            before: .undecided,
            after: .keep,
            finalOrderBefore: [],
            finalOrderAfter: []
        )
        XCTAssertTrue(command.apply(to: &shoot.assets, finalOrder: &shoot.finalSetOrder))

        try await ShootStore.shared.saveShoot(shoot)
        let reopened = try ShootStore.loadShoot(id: shoot.name)

        XCTAssertEqual(reopened.assets[0].cull, .keep)
        XCTAssertNotNil(reopened.assets[0].userDecidedAt)
    }

    func testCommandApplicationHasNoUIDependency() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Lumina/Models/P0Command.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("ProjectViewModel"))
        XCTAssertFalse(source.contains("P0SessionModel"))
        XCTAssertFalse(source.contains("protocol P0Command"))
    }

    private func makeAsset(
        id: UUID,
        cull: CullDecision = .undecided,
        userDecidedAt: Date? = nil,
        recipe: EditRecipe? = nil
    ) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: id.uuidString,
            source: SourceReference(
                originalPath: "/tmp/\(id.uuidString).raw",
                relativePath: "\(id.uuidString).raw"
            ),
            filename: "\(id.uuidString).raw",
            cull: cull,
            recipe: recipe,
            userDecidedAt: userDecidedAt
        )
    }
}
