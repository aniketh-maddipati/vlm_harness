import Foundation

// MARK: - CP2 persistence (journal + open XMP sidecars)

/// Committed decision kinds journaled beside the shoot. Staging is intentionally absent (D13).
enum ShootJournalRecordKind: String, Codable, Sendable, Hashable {
    case cullCommit = "cull.commit"
    case editCommit = "edit.commit"
}

/// One append-only record — never rewritten in place.
struct ShootJournalRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    /// Monotonic per-shoot sequence; assigned by the journal writer.
    var sequence: UInt64
    var recordedAt: Date
    var kind: ShootJournalRecordKind
    var commandID: UUID
    var assetID: UUID
    var cullBefore: CullDecision?
    var cullAfter: CullDecision?
    /// Final-order snapshot after cull commit — replay domain (crash-only startup).
    var finalOrderAfter: [UUID]?
    var editBeforeFingerprint: String?
    var editAfterFingerprint: String?
    /// Committed recipe after edit — replay domain (D13: staging never stored).
    var editAfterRecipe: EditRecipe?

    init(
        id: UUID = UUID(),
        sequence: UInt64,
        recordedAt: Date = Date(),
        kind: ShootJournalRecordKind,
        commandID: UUID,
        assetID: UUID,
        cullBefore: CullDecision? = nil,
        cullAfter: CullDecision? = nil,
        finalOrderAfter: [UUID]? = nil,
        editBeforeFingerprint: String? = nil,
        editAfterFingerprint: String? = nil,
        editAfterRecipe: EditRecipe? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.kind = kind
        self.commandID = commandID
        self.assetID = assetID
        self.cullBefore = cullBefore
        self.cullAfter = cullAfter
        self.finalOrderAfter = finalOrderAfter
        self.editBeforeFingerprint = editBeforeFingerprint
        self.editAfterFingerprint = editAfterFingerprint
        self.editAfterRecipe = editAfterRecipe
    }
}

enum ShootJournalError: Error, Equatable, Sendable {
    case missingShootFolder
    case sequenceRegression(expected: UInt64, found: UInt64)
    case historyRewriteAttempt
    case stagingNotJournaled
    case invalidTrailingLine
}

/// Append-only decision journal — per shoot, beside the shoot folder (D36: no central catalog).
enum ShootDecisionJournal {
    static let directoryName = ".lumina"
    static let fileName = "decisions.journal.jsonl"

    /// Journal lives beside the shoot's photographs — never under Application Support.
    static func journalURL(besideShootFolder rawFolder: URL) -> URL {
        rawFolder
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func appendCullCommit(
        _ command: CullMutationCommand,
        besideShootFolder rawFolder: URL
    ) throws -> ShootJournalRecord {
        let nextSeq = try nextSequence(besideShootFolder: rawFolder)
        let record = ShootJournalRecord(
            sequence: nextSeq,
            kind: .cullCommit,
            commandID: command.id,
            assetID: command.assetID,
            cullBefore: command.before,
            cullAfter: command.after,
            finalOrderAfter: command.finalOrderAfter
        )
        try append(record, besideShootFolder: rawFolder)
        return record
    }

    static func appendEditCommit(
        _ command: EditMutationCommand,
        besideShootFolder rawFolder: URL
    ) throws -> ShootJournalRecord {
        let nextSeq = try nextSequence(besideShootFolder: rawFolder)
        let record = ShootJournalRecord(
            sequence: nextSeq,
            kind: .editCommit,
            commandID: command.id,
            assetID: command.assetID,
            editBeforeFingerprint: command.before.valueFingerprint,
            editAfterFingerprint: command.after.valueFingerprint,
            editAfterRecipe: command.after
        )
        try append(record, besideShootFolder: rawFolder)
        return record
    }

    /// D13 — staging / release-never-commits paths must not reach the journal.
    static func assertStagingNeverJournaled() {
        // Compile-time surface: no staging append API exists on ShootDecisionJournal.
    }

    static func readCommittedRecords(besideShootFolder rawFolder: URL) throws -> [ShootJournalRecord] {
        let url = journalURL(besideShootFolder: rawFolder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var records: [ShootJournalRecord] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for (index, lineSub) in lines.enumerated() {
            let line = String(lineSub)
            if line.isEmpty { continue }
            let isLast = index == lines.count - 1
            guard let lineData = line.data(using: .utf8) else {
                if isLast { continue }
                throw ShootJournalError.invalidTrailingLine
            }
            do {
                let record = try decoder.decode(ShootJournalRecord.self, from: lineData)
                if let prior = records.last?.sequence, record.sequence <= prior {
                    throw ShootJournalError.sequenceRegression(expected: prior + 1, found: record.sequence)
                }
                records.append(record)
            } catch {
                if isLast {
                    // Kill mid-line: ignore incomplete trailing bytes (D35 quit-anywhere).
                    continue
                }
                throw error
            }
        }
        return records
    }

    // MARK: - Internals

    private static func nextSequence(besideShootFolder rawFolder: URL) throws -> UInt64 {
        let existing = try readCommittedRecords(besideShootFolder: rawFolder)
        guard let last = existing.last else { return 1 }
        return last.sequence + 1
    }

    private static func append(_ record: ShootJournalRecord, besideShootFolder rawFolder: URL) throws {
        let dir = rawFolder.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let journalURL = journalURL(besideShootFolder: rawFolder)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var lineData = try encoder.encode(record)
        lineData.append(0x0A) // newline — one complete record per line

        if FileManager.default.fileExists(atPath: journalURL.path),
           let existingData = try? Data(contentsOf: journalURL),
           !existingData.isEmpty {
            let existingText = String(decoding: existingData, as: UTF8.self)
            if existingText.contains("\"sequence\":\(record.sequence)") {
                throw ShootJournalError.historyRewriteAttempt
            }
        }

        if FileManager.default.fileExists(atPath: journalURL.path) {
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.synchronize()
        } else {
            try lineData.write(to: journalURL, options: .atomic)
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.synchronize()
        }
    }
}
