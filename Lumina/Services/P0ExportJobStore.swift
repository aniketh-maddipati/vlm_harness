import Foundation
import CryptoKit
import Darwin

/// One locked destination job. The manifest is the authority for process-crash
/// recovery; atomic replacement is not a promise of power-loss durability.
nonisolated final class P0ExportJobStore {
    enum Failure: LocalizedError {
        case invalidPlan, emptySet, busy, unsafePath, io, conflict, sourceChanged
        var errorDescription: String? {
            switch self {
            case .invalidPlan: return "Export settings or saved job are invalid."
            case .emptySet: return "Keep a photograph before exporting."
            case .busy: return "This export is already running."
            case .unsafePath: return "The export folder or filename changed."
            case .io: return "The export could not be saved. Check the destination."
            case .conflict: return "An existing output does not match this export."
            case .sourceChanged: return "The original changed. Start a new export."
            }
        }
    }
    enum State: String, Codable, Sendable { case pending, rendering, ready, completed, failed, cancelled }
    struct Entry: Codable, Sendable {
        var state: State = .pending
        var temporaryName: String?
        var sourceHash: String?
        var outputHash: String?
        var error: String?
    }
    struct Manifest: Codable, Sendable {
        var version = 1
        let plan: P0ExportPlan
        var entries: [Entry]
    }
    struct Summary: Sendable {
        let root: URL
        let jobID: UUID
        let shootID: UUID
        let completed: Int
        let failed: Int
        let cancelled: Int
        let pending: Int
        let interruption: String?
        let firstFailure: String?
        var total: Int { completed + failed + cancelled + pending }
        var allCompleted: Bool { total > 0 && completed == total && interruption == nil }
    }

    let root: URL
    private let directoryFD: Int32
    private let lockFD: Int32
    private(set) var manifest: Manifest

    static func create(plan: P0ExportPlan, destination: URL) throws -> P0ExportJobStore {
        let root = destination.appendingPathComponent("Lumina-Export-" + plan.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return try P0ExportJobStore(root: root, initial: Manifest(plan: plan, entries: plan.items.map { _ in Entry() }))
    }

    init(root: URL, initial: Manifest? = nil) throws {
        self.root = root.standardizedFileURL
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.unsafePath }
        let lock = openat(fd, ".export.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { close(fd); throw Failure.io }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { close(lock); close(fd); throw Failure.busy }
        directoryFD = fd
        lockFD = lock
        do {
            manifest = try initial ?? JSONDecoder().decode(Manifest.self, from: Self.read(fd: fd, name: "export.json"))
        } catch {
            flock(lock, LOCK_UN); close(lock); close(fd)
            throw error
        }
        // All properties are now initialized: deinit owns cleanup if validation
        // or initial persistence throws, avoiding a second close of reused FDs.
        try validate()
        if initial != nil { try save(manifest) }
    }
    deinit { flock(lockFD, LOCK_UN); close(lockFD); close(directoryFD) }

    private func validate() throws {
        let p = manifest.plan
        guard manifest.version == 1, p.settings.isValid, !p.items.isEmpty,
              p.items.count == manifest.entries.count,
              root.lastPathComponent == "Lumina-Export-" + p.id.uuidString,
              Set(p.items.map(\.assetID)).count == p.items.count,
              Set(p.items.map(\.filename)).count == p.items.count else { throw Failure.invalidPlan }
        for item in p.items {
            guard Self.safeName(item.filename), !item.filename.hasPrefix("."),
                  item.filename.hasSuffix(p.settings.format == .jpeg ? ".jpg" : ".tif"),
                  item.sourcePath.hasPrefix("/") else { throw Failure.unsafePath }
        }
        try checkRoot()
    }
    static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
    func checkRoot() throws {
        var held = stat(); var current = stat()
        guard fstat(directoryFD, &held) == 0, lstat(root.path, &current) == 0,
              current.st_mode & S_IFMT == S_IFDIR, held.st_dev == current.st_dev, held.st_ino == current.st_ino else { throw Failure.unsafePath }
    }
    private static func read(fd: Int32, name: String) throws -> Data {
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { throw Failure.io }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 16_000_000 else { throw Failure.unsafePath }
        return try FileHandle(fileDescriptor: file, closeOnDealloc: false).readToEnd() ?? Data()
    }
    private func save(_ next: Manifest) throws {
        try checkRoot()
        let bytes = try JSONEncoder().encode(next)
        guard bytes.count <= 16_000_000 else { throw Failure.invalidPlan }
        let name = ".manifest-" + UUID().uuidString
        let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.io }
        defer { close(fd); unlinkat(directoryFD, name, 0) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: bytes)
        guard renameat(directoryFD, name, directoryFD, "export.json") == 0 else { throw Failure.io }
    }
    func update(_ index: Int, _ change: (inout Entry) -> Void) throws {
        var next = manifest
        change(&next.entries[index])
        try save(next)
        manifest = next
    }
    /// Encoders return verified bytes; all filesystem writes remain descriptor-relative.
    func publish(_ index: Int, bytes: Data) throws {
        try checkRoot()
        guard manifest.entries[index].state == .rendering else { throw Failure.invalidPlan }
        let name = ".item-" + UUID().uuidString + ".partial"
        try update(index) { $0.temporaryName = name }
        let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.conflict }
        defer { close(fd) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: bytes)
        let checksum = Self.digest(bytes)
        try update(index) { $0.state = .ready; $0.outputHash = checksum; $0.error = nil }
        // Verify the directory entry still denotes the file we created.
        var held = stat(); var current = stat()
        guard fstat(fd, &held) == 0, fstatat(directoryFD, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_mode & S_IFMT == S_IFREG, held.st_dev == current.st_dev, held.st_ino == current.st_ino,
              try hashOutput(name) == checksum else { throw Failure.conflict }
        guard renameatx_np(directoryFD, name, directoryFD, manifest.plan.items[index].filename, UInt32(RENAME_EXCL)) == 0 else { throw Failure.conflict }
        try update(index) { $0.state = .completed; $0.temporaryName = nil }
    }
    private func removeTemporary(_ index: Int) throws {
        guard let name = manifest.entries[index].temporaryName else { return }
        guard Self.safeName(name), name.hasPrefix(".item-"), name.hasSuffix(".partial") else { throw Failure.unsafePath }
        var info = stat()
        if fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard info.st_mode & S_IFMT == S_IFREG, unlinkat(directoryFD, name, 0) == 0 else { throw Failure.unsafePath }
        } else if errno != ENOENT { throw Failure.io }
    }
    private func hashOutput(_ name: String) throws -> String {
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.io }
        defer { close(fd) }
        return try Self.hashDescriptor(fd)
    }
    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    func recover() throws {
        try checkRoot()
        for index in manifest.entries.indices {
            let entry = manifest.entries[index]
            let name = manifest.plan.items[index].filename
            var info = stat()
            let exists = fstatat(directoryFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0
            if exists {
                guard info.st_mode & S_IFMT == S_IFREG,
                      (entry.state == .ready || entry.state == .completed), let checksum = entry.outputHash,
                      try hashOutput(name) == checksum else { throw Failure.conflict }
                try update(index) { $0.state = .completed; $0.error = nil }
            } else {
                guard errno == ENOENT else { throw Failure.io }
                if entry.state == .completed { throw Failure.conflict }
                try removeTemporary(index)
                try update(index) { $0.state = .pending; $0.outputHash = nil; $0.error = nil; $0.temporaryName = nil }
            }
        }
    }
    func cancelRemainder() throws {
        var next = manifest
        for i in next.entries.indices where next.entries[i].state == .pending {
            next.entries[i].state = .cancelled
        }
        try save(next); manifest = next
    }
    func summary(interruption: String? = nil) -> Summary {
        let states = manifest.entries.map(\.state)
        return Summary(root: root, jobID: manifest.plan.id, shootID: manifest.plan.shootID,
                       completed: states.filter { $0 == .completed }.count,
                       failed: states.filter { $0 == .failed }.count,
                       cancelled: states.filter { $0 == .cancelled }.count,
                       pending: states.filter { $0 == .pending || $0 == .rendering || $0 == .ready }.count,
                       interruption: interruption,
                       firstFailure: manifest.entries.indices.first(where: { manifest.entries[$0].state == .failed }).map {
                           manifest.plan.items[$0].filename + ": " + (manifest.entries[$0].error ?? "Export failed.")
                       })
    }
    static func hash(_ url: URL) throws -> String {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.io }
        defer { close(fd) }
        return try hashDescriptor(fd)
    }
    private static func hashDescriptor(_ fd: Int32) throws -> String {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafePath }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
