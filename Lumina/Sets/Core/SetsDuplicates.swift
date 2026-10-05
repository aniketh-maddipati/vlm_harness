import CryptoKit
import Foundation

/// Confirms the page's duplicate candidates without changing either source. The page has already
/// matched the frame metadata; native compares sizes before streaming the complete files through
/// SHA-256 so a metadata collision cannot silently discard a photo.
nonisolated enum SetsDuplicates {
    struct Candidate {
        let a: URL
        let b: URL
    }

    enum Answer: Equatable {
        case same
        case different
        case unreadable(String)
    }

    /// File operations are injected so tests can prove that size mismatches are not opened and
    /// that a file shared by several candidates is hashed only once.
    struct Calls {
        var size: (URL) throws -> Int64
        var hash: (URL, () -> Bool) throws -> String

        static let system = Calls(
            size: { url in
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = attributes[.size] as? NSNumber else {
                    throw Failure("unreadable")
                }
                return size.int64Value
            },
            hash: hashFile)
    }

    private struct Failure: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    private struct Cancelled: Error {}

    private enum Cached<Value> {
        case value(Value)
        case error(String)
    }

    /// Answers candidates in their input order. Cancellation preserves completed answers and marks
    /// the candidate in progress, plus every candidate after it, as cancelled.
    static func confirm(_ pairs: [Candidate], isCancelled: () -> Bool) -> [Answer] {
        confirm(pairs, isCancelled: isCancelled, calls: .system)
    }

    static func confirm(_ pairs: [Candidate], isCancelled: () -> Bool, calls: Calls) -> [Answer] {
        var sizes: [URL: Cached<Int64>] = [:]
        var hashes: [URL: Cached<String>] = [:]
        var answers: [Answer] = []

        func cancelRemainder() -> [Answer] {
            answers + Array(repeating: .unreadable("cancelled"), count: pairs.count - answers.count)
        }

        func size(of url: URL) -> Cached<Int64> {
            if let cached = sizes[url] { return cached }
            do {
                let value = Cached.value(try calls.size(url))
                sizes[url] = value
                return value
            } catch {
                let value = Cached<Int64>.error(reason(for: error))
                sizes[url] = value
                return value
            }
        }

        func hash(of url: URL) throws -> Cached<String> {
            if let cached = hashes[url] { return cached }
            guard !isCancelled() else { throw Cancelled() }
            do {
                let value = Cached.value(try calls.hash(url, isCancelled))
                hashes[url] = value
                return value
            } catch is Cancelled {
                throw Cancelled()
            } catch {
                let value = Cached<String>.error(reason(for: error))
                hashes[url] = value
                return value
            }
        }

        for pair in pairs {
            if isCancelled() { return cancelRemainder() }
            if pair.a == pair.b {
                answers.append(.same)
                continue
            }

            let aSize = size(of: pair.a)
            if isCancelled() { return cancelRemainder() }
            let bSize = size(of: pair.b)
            switch (aSize, bSize) {
            case (.error(let reason), _), (_, .error(let reason)):
                answers.append(.unreadable(reason))
                continue
            case (.value(let a), .value(let b)) where a != b:
                answers.append(.different)
                continue
            default:
                break
            }

            do {
                let aHash = try hash(of: pair.a)
                if isCancelled() { return cancelRemainder() }
                let bHash = try hash(of: pair.b)
                switch (aHash, bHash) {
                case (.error(let reason), _), (_, .error(let reason)):
                    answers.append(.unreadable(reason))
                case (.value(let a), .value(let b)):
                    answers.append(a == b ? .same : .different)
                }
            } catch is Cancelled {
                return cancelRemainder()
            } catch {
                answers.append(.unreadable(reason(for: error)))
            }
        }
        return answers
    }

    /// Number of card frames already represented in the shoot by case-insensitive name and size.
    static func already(names: [(name: String, size: Int)], inShoot: [(name: String, size: Int)]) -> Int {
        let shoot = Set(inShoot.map { Key(name: $0.name, size: $0.size) })
        return names.reduce(into: 0) { count, item in
            if shoot.contains(Key(name: item.name, size: item.size)) { count += 1 }
        }
    }

    private struct Key: Hashable {
        let name: String
        let size: Int

        init(name: String, size: Int) {
            self.name = name.lowercased()
            self.size = size
        }
    }

    private static func hashFile(_ url: URL, isCancelled: () -> Bool) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        while true {
            guard !isCancelled() else { throw Cancelled() }
            guard let data = try file.read(upToCount: 4 << 20), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func reason(for error: Error) -> String {
        if let failure = error as? Failure { return failure.reason }
        return SetsFileOps.reason(error)
    }
}
