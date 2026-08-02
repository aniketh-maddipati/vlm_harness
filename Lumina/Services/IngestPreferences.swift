import Foundation

enum IngestPreferences {
    private static let defaults = UserDefaults.standard

    static var autoIngestOnMount: Bool {
        get {
            if defaults.object(forKey: Keys.autoIngest) == nil { return true }
            return defaults.bool(forKey: Keys.autoIngest)
        }
        set { defaults.set(newValue, forKey: Keys.autoIngest) }
    }

    static var lastTasteFolderPath: String? {
        get { defaults.string(forKey: Keys.lastTaste) }
        set { defaults.set(newValue, forKey: Keys.lastTaste) }
    }

    static var lastKeepRate: Double {
        get {
            let v = defaults.double(forKey: Keys.keepRate)
            return v > 0 ? v : 0.10
        }
        set { defaults.set(newValue, forKey: Keys.keepRate) }
    }

    static var lastTargetKeepCount: Int? {
        get {
            let v = defaults.integer(forKey: Keys.targetKeeps)
            return v > 0 ? v : nil
        }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.targetKeeps) }
            else { defaults.removeObject(forKey: Keys.targetKeeps) }
        }
    }

    static var lastExportFolderPath: String? {
        get { defaults.string(forKey: Keys.lastExport) }
        set { defaults.set(newValue, forKey: Keys.lastExport) }
    }

    private enum Keys {
        static let autoIngest = "lumina.ingest.autoMount"
        static let lastTaste = "lumina.ingest.lastTasteFolder"
        static let keepRate = "lumina.ingest.keepRate"
        static let targetKeeps = "lumina.ingest.targetKeeps"
        static let lastExport = "lumina.ingest.lastExportFolder"
    }
}
