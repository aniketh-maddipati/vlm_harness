import SwiftUI

/// Lightweight bridge from contact sheet → grouping.
/// Preserves shoot/cull/selection; full burst grouping comes next.
struct P0GroupingView: View {
    @Bindable var session: P0SessionModel

    private var selectedCount: Int { session.selectionCount }
    private var keptCount: Int {
        session.assets.filter { $0.cull == .keep }.count
    }

    var body: some View {
        ZStack {
            LuminaTokens.Surface.mist.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                content
                Spacer(minLength: 40)
            }
        }
    }

    private var header: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Button {
                session.leaveGrouping()
            } label: {
                Label("Grid", systemImage: "square.grid.2x2")
                    .font(LuminaTokens.Typeface.navigation(14))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: LuminaTokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Return to contact sheet")

            VStack(alignment: .leading, spacing: 2) {
                Text("Grouping")
                    .font(LuminaTokens.Typeface.editorial(22))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text(session.shoot?.name ?? "Shoot")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }

            Spacer(minLength: 12)

            Text("⇧G")
                .font(LuminaTokens.Typeface.meta(11, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(LuminaTokens.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help("Return to contact sheet")
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.header)
        .background(LuminaTokens.Surface.porcelain.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline.opacity(0.65))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Organize the shoot into groups")
                .font(LuminaTokens.Typeface.title(28))
                .foregroundStyle(LuminaTokens.Ink.primary)

            Text("Your grid, cull marks, and selection carry forward. Burst grouping and story order land here next.")
                .font(LuminaTokens.Typeface.body(16))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                chip("\(session.assets.count) photos")
                if keptCount > 0 { chip("\(keptCount) kept") }
                if selectedCount > 0 { chip("\(selectedCount) selected") }
            }

            Button {
                session.leaveGrouping()
            } label: {
                Text("Back to grid")
                    .font(LuminaTokens.Typeface.navigation(15, weight: .semibold))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 20)
                    .frame(minHeight: LuminaTokens.HitTarget.minimum)
                    .background(LuminaTokens.Surface.well)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(LuminaTokens.Typeface.meta(12))
            .foregroundStyle(LuminaTokens.Ink.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(LuminaTokens.Surface.well)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
