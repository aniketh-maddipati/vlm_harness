import Foundation

// WP-3. Cull's wording (README §2), in one place so the headless tests can read it.

public extension Photo {
    /// "ILCE-7M4 · 09:12:40 · 85mm f/2 1/250 · ISO 100". A field the file doesn't have is left
    /// out, with its separator; nothing ever reads "undefined", "—" or "nil" (R-16, R-53).
    var cullDetails: String {
        func text(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.contains("—"), t != "-" else { return nil }
            return t
        }
        func number(_ v: Double?) -> String? {
            guard let v, v.isFinite, v > 0 else { return nil }
            let r = (v * 10).rounded() / 10
            return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        }
        let exposure = [number(focal).map { "\($0)mm" }, number(aperture).map { "f/\($0)" }, text(shutter)].compactMap { $0 }.joined(separator: " ")
        let parts = [text(camera), text(time), text(exposure), iso.flatMap { $0 > 0 ? "ISO \($0)" : nil }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

public enum CullCopy {
    public static let empty = "Nothing open yet."
    public static let openShoot = "Open a shoot"
    public static let keepSuggestedHelp = "Keep the photos Lumina marked with a ring. Undecided photos only."
    public static let editHelp = "Optional. Nothing changes unless you move a setting."

    public static func state(_ keep: Bool?) -> String { keep == true ? "Kept" : keep == false ? "Out" : "Undecided" }
    public static func copying(_ n: Int, of total: Int) -> String { "Copying \(n) of \(total). Photos appear here one by one…" }
    public static func sceneCount(photos: Int, decided: Int) -> String { "\(photos) photos" + (decided > 0 ? " · \(decided) decided" : "") }
    public static func keepSuggested(_ n: Int) -> String { "Keep \(n) suggested" }
    public static func toEdit(kept: Int) -> String { kept > 0 ? "Edit \(kept) keepers" : "Edit" }
    public static func toSave(kept: Int) -> String { kept > 0 ? "Save \(kept) keepers →" : "Save →" }
}
