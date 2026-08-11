import SwiftUI

/// Hold-? chrome-fade sheet — footer hints grouped by surface; release returns (Law 2, hi-fi H7).
/// Minimal held-glance version — awaiting a drawn frame in the PDF reference.
struct ShortcutsGlanceOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                glanceSection(title: "Table", lines: [
                    CopyContract.tableFooterShortcuts,
                    CopyContract.tableFooterHints
                ])
                glanceSection(title: "Edit", lines: [
                    CopyContract.editFooterShortcuts
                ])
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LuminaTokens.Surface.side.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Shortcuts glance")
        }
        .transition(reduceMotion ? .opacity : .opacity)
    }

    private func glanceSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.onTable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
