import Foundation
import CoreGraphics
import Observation

// WP-0 contract: one window's state. Stored state is declared here (so `debug.state` and every
// screen agree on it); behaviour lives in `AppModel+<Area>.swift` files inside each work
// package's own folder. A work package that needs more stored state keeps it in its own
// `@Observable` class and reaches it with `model.feature(MyState.self)`.

public enum Overlay: String, Codable, Sendable { case help, crop, variations, intro, sceneGrid, picker }

public enum PhotoLoad: String, Sendable { case loading, loaded, failed }

public struct Toast: Equatable, Sendable {
    public var text: String
    public var at: Date
    public init(_ text: String, at: Date = Date()) { self.text = text; self.at = at }
}

/// Open screen state (WP-2).
public struct OpenState: Equatable, Sendable {
    /// Start over was clicked once; a second click before this date clears (R-31).
    public var startOverArmedUntil: Date?
    /// A folder from the last session that needs choosing again (R-19).
    public var reopenName: String?
    public var reopenCount = 0
    /// Something has been opened in this store ("Recent" shows).
    public var hasRecent = false
    public init() {}
}

/// Import progress and result (R-10…R-19), read by `open.importProgress` / `open.importMessage`.
public struct ImportState: Equatable, Sendable {
    public var busy = false
    /// Files checked so far / to check, while busy.
    public var checked = 0
    public var toCheck = 0
    /// Photos added by the last import.
    public var added = 0
    public var message: String?
    /// The last import added nothing (error colour).
    public var failed = false
    /// A drag is over the window (`shell.dropOverlay`).
    public var dropTargeted = false
    public init() {}
}

/// Cull screen state (WP-3).
public struct CullState: Equatable, Sendable {
    /// ⌘+ / ⌘− override of the tile height (64…320), remembered. Nil = by the formula.
    public var tileHeightOverride: Double?
    public init() {}
}

/// Edit screen state shared by the canvas (WP-4), controls (WP-5) and overlays (WP-6).
public struct EditState: Equatable, Sendable {
    /// 1 = Fit. Clamped to ¼× of Fit … 2× of 1:1 (R-46).
    public var zoom = 1.0
    /// The zoom factor that shows the photo 1:1 on the current canvas (set by the canvas).
    public var oneToOne = 2.0
    /// Pan offset in canvas points while zoomed.
    public var pan = CGSize.zero
    public var overlay: Overlay?
    /// Focus mode (H): only the photo.
    public var focus = false
    /// Showing the original (toggle, or \ held).
    public var before = false
    public var beforeHeld = false
    public var section: EditSection = .light
    /// Colour section sub-tab: "hue", "sat" or "lum".
    public var colourAxis = "sat"
    /// The setting nudges act on ([ ] choose it).
    public var activeKey = "ev"
    /// The setting under the pointer, if any (nudges and Variations prefer it).
    public var hoverKey: String?
    /// The setting whose value is being typed (`edit.valueField` is up).
    public var typingKey: String?
    /// The setting being dragged.
    public var draggingKey: String?
    /// Variations: the target setting (debug.state `spec`) and the highlighted cell.
    public var variationKey: String?
    public var variationIndex = 0
    /// Variations opened by a tap (stays open) rather than a hold.
    public var variationSticky = false
    /// The photo Variations opened on; applying is cancelled if it changed (R-06).
    public var variationPhoto: String?
    public var photo: PhotoLoad = .loading
    /// "Loading full size" chip.
    public var loadingFullSize = false
    /// Controls collapsed (narrow layout) or hidden ("Large").
    public var controlsCollapsed = false
    public var controlsHidden = false
    /// `edit.warning`: storage full / another window / offline.
    public var warning: String?
    /// The crop being drawn; nil outside Crop. Keys are `CropKey`.
    public var cropDraft: Look?
    public var cropRatio = "Original"
    public var pickingWhite = false
    public var straightening = false
    public init() {}
}

/// Save screen state (WP-7).
public struct SaveState: Equatable, Sendable {
    public var fmt: SaveFormat = .xmp
    public var withEdits = true
    public var saved: SavedRecord?
    public var destination: URL?
    /// ⏎ guard: the last ⏎ seen on Save (R-33).
    public var lastEnter = Date.distantPast
    /// A save is running; clicks and ⌘S are ignored (R-32).
    public var saving = false
    public var message: String?
    public var lastResult: URL?
    public init() {}
}

@MainActor @Observable
public final class AppModel {
    public private(set) var shoot: Shoot
    public private(set) var decisions: DecisionStore
    public private(set) var edits: EditStore

    public var step: Step = .open
    /// When the step last changed (the ⏎ guards, R-01, R-33).
    public var stepChangedAt = Date.distantPast
    /// Cull's current photo. Edit keeps its own place (`editCur`): entering Edit lands on the
    /// first keeper, and coming back to Cull finds its photo where it was (parity traces).
    public var cullCur: String?
    public var editCur: String?
    /// The current photo of the step on screen (`debug.state.cur`).
    public var cur: String? {
        get { step == .edit ? editCur : cullCur }
        set { if step == .edit { editCur = newValue } else { cullCur = newValue } }
    }
    /// Photos copied from the card so far (R-1A: only ever increases). Equals the total for a local shoot.
    public var copied = 0
    public var copying = false

    public var open = OpenState()
    public var imports = ImportState()
    public var cull = CullState()
    public var edit = EditState()
    public var save = SaveState()
    /// The latest message: `cull.message` in Cull, `edit.toast` in Edit.
    public var toast: Toast?
    /// Window content size in points (set by the shell).
    public var windowSize = CGSize(width: 1100, height: 760)
    /// Keys held through `debug.command` or the event monitor (for releaseAllKeys and blur).
    public var heldKeys: Set<String> = []
    /// Bumped by `changed()`; the persistence layer and the debug hook watch it.
    public private(set) var revision = 0

    public let services: Services
    public let config: LaunchConfig
    /// The clock and timers. Use `clock.now` and `clock.after`, never `Date()` / asyncAfter.
    public let clock: any Scheduler
    public let windowID = UUID().uuidString

    /// Things only the UI layer can do (pickers, window). Installed by the shell.
    @ObservationIgnored public var hooks = UIHooks()
    @ObservationIgnored private var features: [ObjectIdentifier: AnyObject] = [:]
    @ObservationIgnored private var keptCache: (rev: Int, copied: Int, ids: [String])?

    public init(shoot: Shoot = .empty, services: Services, config: LaunchConfig = LaunchConfig(), clock: (any Scheduler)? = nil) {
        self.shoot = shoot; self.services = services; self.config = config; self.clock = clock ?? LiveScheduler()
        decisions = DecisionStore(ids: shoot.photos.map(\.id))
        edits = EditStore(shoot: shoot)
        for f in config.faults { Faults.shared.inject(f) }
    }

    /// A work package's own state, created on first use and kept for the window's life.
    public func feature<T: AnyObject>(_ type: T.Type, _ make: () -> T) -> T {
        if let f = features[ObjectIdentifier(type)] as? T { return f }
        let f = make(); features[ObjectIdentifier(type)] = f; return f
    }

    /// Replace the shoot (a card arrives, a folder is imported, Start over). Decisions and edits
    /// restart from `keep` / `looks` when given.
    public func setShoot(_ s: Shoot, keep: [String: Bool] = [:], looks: [String: Look] = [:], tags: [String: String] = [:], done: [String] = []) {
        shoot = s
        decisions = DecisionStore(ids: s.photos.map(\.id), keep: keep)
        edits = EditStore(shoot: s, looks: looks, tags: tags, done: Set(done))
        keptCache = nil
        if s.local { copied = s.photos.count }
        if shoot.photo(cullCur) == nil { cullCur = visiblePhotos.first?.id }
        if shoot.photo(editCur) == nil { editCur = nil }
    }

    // MARK: derived

    public var total: Int { shoot.photos.count }
    public var breakpoints: Breakpoints { Breakpoints(windowSize) }
    public var scale: CGFloat { LayoutScale.scale(for: windowSize) }
    public var current: Photo? { shoot.photo(cur) }
    /// Photos on screen in Cull: what has been copied so far.
    public var visiblePhotos: ArraySlice<Photo> { shoot.photos.prefix(shoot.local ? total : copied) }
    /// The Edit set: kept photos in shoot order. Cached per decision revision (5,000 photos).
    public var keptIDs: [String] {
        if let c = keptCache, c.rev == decisions.revision, c.copied == copied { return c.ids }
        let keep = decisions.keep, ids = visiblePhotos.lazy.map(\.id).filter { keep[$0] == true }
        let a = Array(ids); keptCache = (decisions.revision, copied, a); return a
    }
    /// The look shown for the current photo.
    public var currentLook: Look { (step == .edit ? editCur : nil).map { edits.look($0, decisions: decisions) } ?? [:] }

    /// The open layers, for `KeyRouter` (KEYMAP "Layer order").
    public var layers: [Layer] {
        var l: [Layer] = [.step(step)]
        if step == .edit {
            if edit.typingKey != nil { l.append(.textField) }
            switch edit.overlay {
            case .help: l.append(.help)
            case .intro: l.append(.intro)
            case .crop: l.append(.crop)
            case .variations: l.append(.variations)
            default: break
            }
        }
        return l
    }

    // MARK: input

    /// Every key goes through here: the event monitor, `debug.command` holds, and tests.
    /// Returns the route so the caller knows whether to let the event through (`.typing`).
    @discardableResult
    public func handle(_ key: KeyEvent) -> Route {
        if key.phase == .down { heldKeys.insert(key.key) } else { heldKeys.remove(key.key) }
        let route = KeyRouter.route(key, layers: layers)
        perform(route.action)
        return route
    }

    public func perform(_ action: Action) {
        switch action {
        case .goStep(let s): go(s)
        case .saveShortcut: saveShortcut()
        case .openFolder: chooseFolder()
        case .openEnter: openEnter()
        case .keep: Perf.measure("CullKey") { cullMark(keep: true) }
        case .out: Perf.measure("CullKey") { cullMark(keep: false) }
        case .cullMove(let d): Perf.measure("CullKey") { cullMove(d) }
        case .cullScene(let d): cullScene(d)
        case .nextUndecided: cullNextUndecided()
        case .cullUndo: cullUndo()
        case .cullRedo: cullRedo()
        case .tileSize(let d): cullTileSize(d)
        case .editEnter: editEnter()
        case .editMove(let d): editMove(d)
        case .editScene(let d): editScene(d)
        case .editUndo: editUndo()
        case .editRedo: editRedo()
        case .before(let down): beforeHold(down)
        case .variations(let down): variationsHold(down)
        case .crop: cropOpen()
        case .straighten: straighten()
        case .auto: auto()
        case .nudge(let d, let coarse): nudge(d, coarse: coarse)
        case .pickSetting(let d): pickSetting(d)
        case .reset: resetSetting()
        case .resetAll: resetAll()
        case .sameAsLast: sameAsLast()
        case .pickWhite: pickWhite()
        case .editOut: editOut()
        case .copySettings: copySettings()
        case .pasteSettings: pasteSettings()
        case .zoomToggle: zoomToggle()
        case .zoomStep(let d): zoomStep(d)
        case .zoomFit: zoomFit()
        case .focus: toggleFocus()
        case .editEscape: editEscape()
        case .help: helpOpen()
        case .rotate(let d): cropRotate(d)
        case .cropAngle(let d): cropAngle(d)
        case .cropGrow(let d): cropGrow(d)
        case .cropMove(let dx, let dy, let coarse): cropMove(dx: dx, dy: dy, coarse: coarse)
        case .cropUndo: cropUndo()
        case .cropRedo: cropRedo()
        case .cropKeep: cropKeep()
        case .cropCancel: cropCancel()
        case .variationMove(let dx, let dy): variationsMove(dx: dx, dy: dy)
        case .variationApply: variationsApply()
        case .variationClose: variationsClose()
        case .helpClose: helpClose()
        case .introClose: introClose()
        case .saveEnter: saveEnter()
        case .save: saveNow()
        case .explain(let text): say(text)
        case .typing, .none: break
        }
    }

    /// Show a message in the step's message line (`cull.message`, `edit.toast`).
    public func say(_ text: String) { toast = Toast(text, at: clock.now) }

    /// Call after any change that must survive a relaunch. Coalescing is the persistence layer's job.
    public func changed() { revision &+= 1; keptCache = nil; persistSoon() }
}
