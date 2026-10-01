import SwiftUI
import AppKit
import LuminaCore

// WP-7. The Save screen's own controls (README §4): the "Save for" segments, the "Include my
// edits" row, the saved card, and the two AppKit panels behind "Change…" and "Show in Finder".

/// Lightroom / Folder / JPEG: three equal segments, 34 high, the chosen one #5B5854 in bold.
struct SaveFormatControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        HStack(spacing: 2.scaled(s)) {
            ForEach(SaveFormat.allCases, id: \.self) { f in Segment(format: f, on: model.save.fmt == f) { model.setFormat(f) } }
        }
        .padding(3.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.segmented.scaled(s), style: .continuous).fill(LuminaColor.fill07))
        .accessibilityElement(children: .contain).accessibilityLabel(SavePresentation.saveFor)
    }

    private struct Segment: View {
        let format: SaveFormat, on: Bool, pick: () -> Void
        @Environment(\.luminaScale) private var s
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false
        var body: some View {
            Button(action: pick) {
                Text(SavePresentation.formatLabel(format))
                    .font(LuminaFont.body(s, on ? .bold : .regular, id: AccessibilityID.Save.format(format.rawValue)))
                    .foregroundStyle(on || hover ? LuminaColor.textPrimary : LuminaColor.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity).frame(height: LuminaHeight.segment.scaled(s))
                    .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonSecondary.scaled(s), style: .continuous).fill(on ? LuminaColor.bgSelected : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(SavePressStyle())
            .onHover { hover = $0 }
            .animation(LuminaMotion.panelFade(reduce), value: on)
            .accessibilityIdentifier(AccessibilityID.Save.format(format.rawValue))
            .accessibilityLabel(SavePresentation.formatLabel(format))
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }
}

/// "Include my edits": the whole row toggles; "Review" opens Edit.
struct SaveIncludeEditsRow: View {
    let subline: String
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var hover = false

    var body: some View {
        let on = model.save.withEdits
        HStack(spacing: 12.scaled(s)) {
            Button { model.setWithEdits(!on) } label: {
                HStack(spacing: 12.scaled(s)) {
                    Capsule().fill(on ? LuminaColor.accentGold : LuminaColor.fill20)
                        .frame(width: 30.scaled(s), height: 18.scaled(s))
                        .overlay(alignment: .leading) {
                            Circle().fill(LuminaColor.textPrimary).frame(width: 14.scaled(s), height: 14.scaled(s))
                                .padding(2.scaled(s)).offset(x: on ? 12.scaled(s) : 0)
                        }
                    VStack(alignment: .leading, spacing: 1.scaled(s)) {
                        Text(SavePresentation.includeEdits).font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textPrimary)
                        Text(subline).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: LuminaHeight.minHit.scaled(s))
                .contentShape(Rectangle())
            }
            .buttonStyle(SavePressStyle())
            .animation(reduce ? nil : .easeOut(duration: LuminaMotion.panelFadeSeconds), value: on)
            .accessibilityIdentifier(AccessibilityID.Save.includeEdits)
            .accessibilityLabel(SavePresentation.includeEdits).accessibilityValue(on ? "1" : "0").accessibilityHint(subline)
            .accessibilityAddTraits(.isToggle)

            Button("Review") { model.go(.edit) }
                .buttonStyle(LuminaLinkButtonStyle(size: LuminaFontSize.small)).fixedSize()
                .accessibilityLabel("Review edits")
        }
        .padding(.vertical, 12.scaled(s)).padding(.horizontal, 14.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.toggleRow.scaled(s), style: .continuous).fill(hover ? LuminaColor.bgPanelHover : LuminaColor.bgPanel))
        .onHover { hover = $0 }
    }
}

/// "Saved · 12 photos, 4 with edits · 14:02", Show in Finder, and what to do next.
struct SaveSavedCard: View {
    let title: String, hint: String
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let name = Text(title).font(LuminaFont.ui(LuminaFontSize.bodyLarge, .semibold, s)).foregroundStyle(LuminaColor.accentGold)
        let finder = Button { model.revealSaved() } label: { Text("Show in Finder").underline().foregroundStyle(LuminaColor.textPrimary) }
            .buttonStyle(LuminaLinkButtonStyle(size: LuminaFontSize.caption)).saveInlineLink(s).fixedSize()
            .accessibilityLabel("Show in Finder")
        VStack(alignment: .leading, spacing: 8.scaled(s)) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12.scaled(s)) { name.lineLimit(1); Spacer(minLength: 0); finder }
                VStack(alignment: .leading, spacing: 6.scaled(s)) { name.fixedSize(horizontal: false, vertical: true); finder }
            }
            Text(hint).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14.scaled(s)).padding(.horizontal, 16.scaled(s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LuminaRadius.card.scaled(s), style: .continuous).fill(LuminaColor.accentGoldTint))
        .overlay(RoundedRectangle(cornerRadius: LuminaRadius.card.scaled(s), style: .continuous).strokeBorder(LuminaColor.accentGoldLine, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Save.savedCard)
        .accessibilityLabel(title)
    }
}

/// Custom-drawn controls press like every other button: 0.97.
struct SavePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1) }
}

extension View {
    /// A link inside a line of text: it keeps its 28pt hit area (R-54) without making the line taller.
    func saveInlineLink(_ s: CGFloat) -> some View { padding(.vertical, -6.scaled(s)) }

    /// CSS line-height 1.5 for a paragraph at `size` (system text sets about 1.23).
    func saveLineHeight(_ size: CGFloat, _ s: CGFloat) -> some View {
        let extra = (LayoutScale.font(size, s) * 0.27 * 2).rounded() / 2
        return lineSpacing(extra).padding(.vertical, extra / 2).fixedSize(horizontal: false, vertical: true)
    }
}

/// The two things only AppKit can do for Save. Installed when the screen appears.
@MainActor
enum SavePanels {
    static func install(on model: AppModel) {
        model.hooks.pickDestination = { [weak model] in if let model { pickDestination(for: model) } }
        if model.hooks.reveal == nil { model.hooks.reveal = { reveal($0) } }
    }

    /// "Change…": a folder picker, as a sheet on the window.
    static func pickDestination(for model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "Choose"
        panel.directoryURL = nearestExisting(model.exportDestination(model.save.fmt))
        let done: (NSApplication.ModalResponse) -> Void = { [weak model] r in
            if r == .OK, let u = panel.url { model?.setDestination(u) }
        }
        if let w = NSApp.keyWindow { panel.beginSheetModal(for: w, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    /// "Show in Finder": the file selected, or the folder opened; a folder that isn't there yet
    /// shows the nearest one that is.
    static func reveal(_ url: URL) {
        let target = nearestExisting(url)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), !isDir.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: target.path)
        }
    }

    static func nearestExisting(_ url: URL) -> URL {
        var u = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: u.path), u.pathComponents.count > 1 { u.deleteLastPathComponent() }
        return u
    }
}
