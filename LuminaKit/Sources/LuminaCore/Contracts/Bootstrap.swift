import Foundation

// WP-0 contract: how a window comes up.

/// Closures the UI layer installs so Core can ask for things only AppKit can do.
public struct UIHooks {
    public var pickFolder: (@MainActor () -> Void)?
    public var pickPhotos: (@MainActor () -> Void)?
    public var pickDestination: (@MainActor () -> Void)?
    public var reveal: (@MainActor (URL) -> Void)?
    public var resize: (@MainActor (CGSize) -> Void)?
    public var blur: (@MainActor () -> Void)?
    public var openSecondWindow: (@MainActor () -> Void)?
    public init() {}
}

public extension Services {
    /// The package's defaults: ImageIO pictures, a recording exporter, and a store in
    /// `config.storeDir` (memory when there is none).
    static func standard(config: LaunchConfig) -> Services {
        Services(images: DefaultImageProvider(), exporter: RecordingExporter(), persistence: makePersistence(config: config))
    }
}

public extension AppModel {
    /// A window's model for a launch: the card, then whatever the store remembers.
    static func launch(config: LaunchConfig = LaunchConfig(), services: Services? = nil, clock: (any Scheduler)? = nil) -> AppModel {
        let m = AppModel(shoot: Shoot.card(config.card) ?? .empty, services: services ?? .standard(config: config), config: config, clock: clock)
        m.restore()
        if m.copying || (m.copied > 0 && m.copied < m.total && !m.shoot.local) { m.startCopy() }
        if let f = config.fixture { m.importURLs([f]) }
        return m
    }
}
