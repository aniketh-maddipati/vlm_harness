import Foundation

// WP-0 contract: real pictures for the demo card. The prototype shows picsum.photos pictures;
// the goldens were captured with them, so pixel parity needs the same ones. They are cached once
// on this Mac, outside the repo (they may not be redistributed), and the app never fetches them:
// with no cache the demo card draws its generated pictures.
//
//   LUMINA_DEMO_PHOTOS=<dir>   default ~/LuminaEvidence/native-ui/demo-photos (debug builds only)
//   files: seed<seed>_<aspect × 1000>[_bw].jpg, 2000 px on the long side

public enum DemoPhotos {
    public static let directory: URL? = {
        if let d = ProcessInfo.processInfo.environment["LUMINA_DEMO_PHOTOS"] { return d.isEmpty ? nil : URL(fileURLWithPath: d) }
        #if LUMINA_UITEST
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("LuminaEvidence/native-ui/demo-photos")
        return FileManager.default.fileExists(atPath: d.path) ? d : nil
        #else
        return nil
        #endif
    }()

    /// The cached picture for a demo photo, if there is one.
    public static func url(seed: Int, aspect: Double, bw: Bool) -> URL? {
        guard let directory else { return nil }
        let u = directory.appendingPathComponent("seed\(seed)_\(Int((aspect * 1000).rounded()))\(bw ? "_bw" : "").jpg")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}
