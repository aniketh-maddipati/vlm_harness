import SwiftUI
import LuminaCore

// WP-2. The pieces of Open (README §1): the card tile, the import row with its progress and
// result, the folder to reopen, Recent with Start over. Every size is a token × luminaScale.

extension View {
    /// CSS `line-height: 1.5`: the extra leading between lines, and half of it above and below.
    func openLineHeight(_ size: CGFloat, _ s: CGFloat) -> some View {
        let gap = LayoutScale.font(size, s) * (LuminaFontSize.lineHeightBody - 1.2)
        return lineSpacing(gap).padding(.vertical, gap / 2)
    }
}

/// The 3pt gold bar: copy progress under the card button, and files checked during an import.
struct OpenBar: View {
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                LuminaColor.fill10
                LuminaColor.accentGold.frame(width: g.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 3.scaled(s))
        .clipShape(RoundedRectangle(cornerRadius: 2.scaled(s), style: .continuous))
        .animation(LuminaMotion.copyBar(reduce), value: fraction)
        .accessibilityHidden(true)
    }
}

/// "SD card · Untitled", its details, the primary button and the copy bar.
struct OpenCardTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        VStack(alignment: .leading, spacing: 14.scaled(s)) {
            WrapRow(spacing: 16.scaled(s), lineSpacing: 16.scaled(s)) {
                VStack(alignment: .leading, spacing: 4.scaled(s)) {
                    Text(model.openCardName).font(LuminaFont.ui(LuminaFontSize.title3, .semibold, s))
                    Text(model.openCardDetails).font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wrapFlex(minWidth: 220.scaled(s))

                Button { model.startCulling() } label: {
                    HStack(spacing: 10.scaled(s)) { Text(model.openCardButton).lineLimit(1); KeyHint("⏎") }.fixedSize()
                }
                .buttonStyle(.luminaPrimary)
                .accessibilityIdentifier(AccessibilityID.Open.card)
                .accessibilityLabel(model.openCardButton)
            }
            if let f = model.openCopyFraction { OpenBar(fraction: f) }
        }
        .padding(20.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.card.scaled(s), style: .continuous).fill(LuminaColor.bgPanel))
        .overlay(RoundedRectangle(cornerRadius: LuminaRadius.card.scaled(s), style: .continuous).strokeBorder(LuminaColor.hairline, lineWidth: 1))
    }
}

/// "Open folder… ⌘O", "Choose photos…", the drop hint, then what the import is doing or did.
struct OpenImportBlock: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        VStack(alignment: .leading, spacing: 10.scaled(s)) {
            WrapRow(spacing: 8.scaled(s), lineSpacing: 8.scaled(s)) {
                Button { model.chooseFolder() } label: {
                    HStack(spacing: 10.scaled(s)) {
                        Text("Open folder…")
                        KeyHint("⌘O", opacity: 1).foregroundStyle(LuminaColor.textTertiary)
                    }
                    .fixedSize()
                }
                .buttonStyle(.luminaSecondary)
                .accessibilityIdentifier(AccessibilityID.Open.openFolder)
                .accessibilityLabel("Open folder…")

                Button { model.choosePhotos() } label: { Text("Choose photos…").fixedSize() }
                    .buttonStyle(.luminaSecondary)
                    .accessibilityIdentifier(AccessibilityID.Open.choosePhotos)

                Text("or drop photos or a folder anywhere")
                    .font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = model.openImportProgress {
                VStack(alignment: .leading, spacing: 6.scaled(s)) {
                    Text(progress).font(LuminaFont.caption(s, id: AccessibilityID.Open.importProgress)).foregroundStyle(LuminaColor.accentGold)
                        .luminaStatus(AccessibilityID.Open.importProgress, progress)
                    OpenBar(fraction: model.openImportFraction)
                }
            }
            if let message = model.openImportMessage {
                // Wraps, and a long unbroken name breaks rather than widening the column (R-1B).
                Text(message)
                    .font(LuminaFont.caption(s, id: AccessibilityID.Open.importMessage))
                    .foregroundStyle(model.imports.failed ? LuminaColor.errorText : LuminaColor.textSecondary)
                    .openLineHeight(LuminaFontSize.caption, s)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .luminaStatus(AccessibilityID.Open.importMessage, message)
            }
        }
    }
}

/// A resume row: rest fill 0.04, 0.09 on hover, radius 9, padding 12 / 14.
struct OpenRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration) }
    private struct Content: View {
        let configuration: Configuration
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        var body: some View {
            configuration.label
                .padding(.vertical, 12.scaled(s)).padding(.horizontal, 14.scaled(s))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: LuminaRadius.row.scaled(s), style: .continuous).fill(hover ? LuminaColor.fill09 : LuminaColor.fill04))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}

/// Title (one line, truncated), a subline, and what a click does on the right.
struct OpenRow: View {
    @Environment(\.luminaScale) private var s
    let title: String, details: String, action: String
    var body: some View {
        HStack(spacing: 14.scaled(s)) {
            VStack(alignment: .leading, spacing: 2.scaled(s)) {
                Text(title).font(LuminaFont.ui(LuminaFontSize.bodyLarge, .regular, s)).foregroundStyle(LuminaColor.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Text(details).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(action).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textSecondary).lineLimit(1).fixedSize()
        }
    }
}

/// "Folder · {name}": an imported folder that isn't on screen (after a relaunch, or behind the card).
struct OpenReopenRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.reopenFolder() } label: {
            OpenRow(title: model.openReopenTitle, details: model.openReopenDetails, action: "Choose folder")
        }
        .buttonStyle(OpenRowButtonStyle())
        .accessibilityIdentifier(AccessibilityID.Open.reopenFolder)
    }
}

/// "Recent", the resume row, and Start over with its two-click guard (R-31).
struct OpenRecent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        VStack(alignment: .leading, spacing: 8.scaled(s)) {
            Text("Recent").font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textTertiary)
            Button { model.resumeRecent() } label: {
                OpenRow(title: model.openRecentTitle, details: model.openRecentDetails, action: model.openRecentAction)
            }
            .buttonStyle(OpenRowButtonStyle())
            .accessibilityIdentifier(AccessibilityID.Open.recent)

            Button { model.startOverClick() } label: { Text(model.openStartOverTitle).lineLimit(1) }
                .buttonStyle(.luminaLink)
                .accessibilityIdentifier(AccessibilityID.Open.startOver)
                .accessibilityLabel(model.openStartOverTitle)
        }
    }
}
