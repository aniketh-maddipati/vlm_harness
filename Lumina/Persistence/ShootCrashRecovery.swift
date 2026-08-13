import CryptoKit
import Foundation

// MARK: - CP2 crash-only startup (D35 quit-anywhere = crash)

struct CrashRecoveryReport: Equatable, Sendable {
    var appliedRecords: Int
    var restoredCullCommits: Int
    var restoredEditCommits: Int
}

/// Replay committed journal records on every launch — no clean-shutdown flag exists.
enum ShootCrashRecovery {
    /// Crash-only startup path: always replay the beside-shoot journal over shoot state.
    static func replayJournal(
        into shoot: inout ShootRecord,
        besideShootFolder rawFolder: URL
    ) throws -> CrashRecoveryReport {
        let records = try ShootDecisionJournal.readCommittedRecords(besideShootFolder: rawFolder)
        var applied = 0
        var cullCount = 0
        var editCount = 0

        for record in records {
            switch record.kind {
            case .cullCommit:
                guard let after = record.cullAfter,
                      let index = shoot.assets.firstIndex(where: { $0.id == record.assetID }) else {
                    continue
                }
                shoot.assets[index].cull = after
                shoot.assets[index].userDecidedAt = after == .undecided ? nil : record.recordedAt
                if let order = record.finalOrderAfter {
                    shoot.finalSetOrder.assetIDs = order
                }
                cullCount += 1
            case .editCommit:
                guard let index = shoot.assets.firstIndex(where: { $0.id == record.assetID }) else {
                    continue
                }
                if let recipe = record.editAfterRecipe {
                    shoot.assets[index].recipe = recipe.hasSettings ? recipe : nil
                }
                editCount += 1
            }
            applied += 1
        }

        return CrashRecoveryReport(
            appliedRecords: applied,
            restoredCullCommits: cullCount,
            restoredEditCommits: editCount
        )
    }

    /// Filesystem snapshot helper — photograph bytes X must never mutate (D36 / R-M.1).
    static func photographByteHashes(in folder: URL, extensions: Set<String> = ["ARW", "CR3", "NEF", "RAF", "DNG", "HEIC", "JPG", "JPEG"]) -> [String: String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return [:] }
        var out: [String: String] = [:]
        for url in entries where !url.hasDirectoryPath {
            let ext = url.pathExtension.uppercased()
            guard extensions.contains(ext) else { continue }
            if let data = try? Data(contentsOf: url) {
                let digest = SHA256.hash(data: data)
                out[url.lastPathComponent] = digest.map { String(format: "%02x", $0) }.joined()
            }
        }
        return out
    }
}
