import Foundation

// WP-2. Open: the card copy, imports and drops, Start over (R-01, R-10…R-1A, R-31).

public extension AppModel {
    /// ⏎ on Open, or the card button: start the copy (once) and go to Cull. Ignored within
    /// 450 ms of a step change (R-01).
    func openEnter() {
        guard sinceStepChange >= 0.45 else { return }
        startCulling()
    }

    func startCulling() {
        guard !shoot.isEmpty else { return }
        if !shoot.local, copied < total, !copying { startCopy() }
        go(.cull)
    }

    /// The (simulated) card copy: photos arrive one by one, the count only goes up (R-1A).
    func startCopy() {
        guard !shoot.local, copied < total else { copying = false; return }
        copying = true
        let rate = config.copyRate ?? 66
        func tick() {
            guard copying, copied < total else { copying = false; changed(); return }
            copied += 1
            if cullCur == nil { cullCur = shoot.photos.first?.id }
            if copied % 15 == 0 || copied == total { changed() }
            if copied < total { clock.after(1 / rate) { tick() } } else { copying = false }
        }
        clock.after(1 / rate) { tick() }
    }

    /// ⌘O / "Open folder…".
    func chooseFolder() { hooks.pickFolder?() }

    /// WP-2: walk, classify, decode, dedupe, group; queue while busy (R-10…R-18).
    func importURLs(_ urls: [URL]) {}

    /// Start over: the first click arms it for 4 s, the second clears the decisions (R-31).
    func startOverClick() {
        if let until = open.startOverArmedUntil, clock.now < until {
            open.startOverArmedUntil = nil
            setShoot(shoot); cullCur = visiblePhotos.first?.id; editCur = nil; save.saved = nil
            changed()
        } else {
            open.startOverArmedUntil = clock.now.addingTimeInterval(4)
            clock.after(4) { [weak self] in if let s = self, let u = s.open.startOverArmedUntil, s.clock.now >= u { s.open.startOverArmedUntil = nil } }
        }
    }
}
