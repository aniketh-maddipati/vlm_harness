#!/usr/bin/env swift
/**
 Prompt-9 contract audit — banned-word scan + hi-fi ruling checks.
 Run: swift Scripts/prompt_9_audit.swift
 */
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ relative: String) -> String? {
    try? String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
}

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func pass(_ message: String) {
    print("PASS: \(message)")
}

// MARK: - .cursorrules contract

guard let rules = read(".cursorrules") else { fail(".cursorrules missing") }

if rules.contains("PDF is wrong") || rules.contains("pdf is wrong") {
    fail(".cursorrules still contains deleted PDF-is-wrong ruling")
}
pass("No PDF-is-wrong ruling in .cursorrules")

let requiredRulingSnippets = [
    "`P`, `X`, `⏎`, `⇧⏎`, `A`",
    "All five swallow key-repeat",
    "`design/hifi.pdf` is the visual authority",
    "`design/copy-contract.txt`",
    "Default scope = the row",
    "Each additional ⇧⏎ widens exactly one ring",
    "**Develop** is the sanctioned physical word",
    "multi-select (drag-box + ⇧-arrows)",
    "cross-row / shoot-wide propagation via the ⇧⏎ ripple",
    "the `?` shortcuts surface",
    "Still shelved, verbatim",
    "Ship the plain 1.5 pt halo",
    "brighter-ring fallback lives behind a debug flag only",
]
for snippet in requiredRulingSnippets {
    guard rules.contains(snippet) else { fail(".cursorrules missing ruling snippet: \(snippet)") }
}
pass(".cursorrules contains all H0 ruling deltas")

if rules.contains("Develop` is banned") || rules.contains("Develop is banned") {
    fail(".cursorrules still bans Develop in user-visible strings")
}
pass("Develop removed from banned-words list")

// MARK: - No PDF-is-wrong in source

let sourceRoots = ["Lumina", "Scripts", "LuminaLogicTests", "LuminaUITests", "DesignTokens"]
let sourceSkip = Set(["Scripts/prompt_9_audit.swift", "Scripts/prompt_9_audit.py"])
for root in sourceRoots {
    let url = repoRoot.appendingPathComponent(root)
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
    for case let file as URL in enumerator {
        guard ["swift", "md", "sh", "txt"].contains(file.pathExtension) else { continue }
        let rel = file.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
        if sourceSkip.contains(rel) { continue }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        if text.localizedCaseInsensitiveContains("PDF is wrong") {
            fail("Source file references deleted PDF-is-wrong ruling: \(file.path)")
        }
    }
}
pass("No source file references the deleted PDF-is-wrong ruling")

// MARK: - Banned words policy (.cursorrules is source of truth for H0)

let bannedParts = rules.components(separatedBy: "### Banned words")
guard bannedParts.count > 1 else { fail(".cursorrules missing ### Banned words section") }
let bannedLower = bannedParts[1].lowercased()
for word in ["sync", "preset", "copy settings", "catalog", "import", "ai", "smart", "auto", "analyze", "generate"] {
    guard bannedLower.contains(word) else { fail(".cursorrules banned-words section missing: \(word)") }
}
if bannedLower.contains("banned everywhere: develop") || bannedLower.contains("banned: develop") {
    fail(".cursorrules still lists Develop among banned words")
}
pass("Banned-words policy matches hi-fi contract (Develop allowed)")

// MARK: - DesignTokens compile contract (static structure)

guard let tokens = read("DesignTokens/Tokens.swift") else { fail("DesignTokens/Tokens.swift missing") }

let requiredTokenSnippets = [
    "static let fill",
    "opacity: 0.07",
    "static let width: CGFloat = 252",
    "static let height: CGFloat = 64",
    "static let handleSize: CGFloat = 18",
    "static let minimumHit: CGFloat = 44",
    "static let selection = Color(hex: \"2E2E2C\")",
    "static let halo = Color(red: 255 / 255, green: 236 / 255, blue: 205 / 255)",
    "static let secondOrderOpacity: Double = 0.45",
    "static let grabDuration: TimeInterval = 0.100",
    "static let carryDuration: TimeInterval = 0.180",
    "static let placeDuration: TimeInterval = 0.140",
    "assert(selection != halo",
]
for snippet in requiredTokenSnippets {
    guard tokens.contains(snippet) else { fail("DesignTokens/Tokens.swift missing: \(snippet)") }
}
pass("DesignTokens/Tokens.swift contains required hi-fi token contract")

// MARK: - Copy contract diff (H1)

guard FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("design/copy-contract.txt").path) else {
    fail("design/copy-contract.txt missing")
}
guard let contractText = read("design/copy-contract.txt") else { fail("design/copy-contract.txt unreadable") }
var contractLines: [String] = []
for line in contractText.split(separator: "\n") {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
    if let range = trimmed.range(of: #/^\[[^\]]+\]\s+(.+)$/#, options: .regularExpression) {
        let body = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
        contractLines.append(body)
    }
}
guard contractLines.count >= 20 else { fail("copy-contract.txt looks truncated") }

func inContract(_ value: String) -> Bool {
    if contractLines.contains(value) { return true }
    return contractLines.contains { $0.contains(value) }
}

guard let copyContract = read("Lumina/Design/CopyContract.swift") else {
    fail("Lumina/Design/CopyContract.swift missing")
}
let exemptStatic: Set<String> = [
    "pointedFolderMovedBody", "pointedFolderMovedAction", "staleRenderBody", "staleRenderAction",
]
let staticPattern = #/static let (\w+) = "((?:[^"\\]|\\.)*)"/#
for match in copyContract.matches(of: staticPattern) {
    let name = String(match.output.1)
    let value = String(match.output.2)
    if exemptStatic.contains(name) { continue }
    guard inContract(value) else { fail("CopyContract.\(name) not in design/copy-contract.txt: \(value)") }
}
pass("CopyContract static strings are frozen in design/copy-contract.txt")

let legacyBanned = ["Adapt treatment to", "Adapted treatment to", "undoes all of it", "From DSC"]
let luminaURL = repoRoot.appendingPathComponent("Lumina")
if let enumerator = FileManager.default.enumerator(at: luminaURL, includingPropertiesForKeys: nil) {
    for case let file as URL in enumerator {
        guard file.pathExtension == "swift" else { continue }
        if file.lastPathComponent == "CopyContract.swift" { continue }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for phrase in legacyBanned where text.contains(phrase) {
            fail("Legacy hi-fi copy still present (\(phrase)) in \(file.path)")
        }
    }
}
pass("No legacy pre-H1 staged/receipt strings in Lumina")

print("Prompt-9 audit: all checks passed")
