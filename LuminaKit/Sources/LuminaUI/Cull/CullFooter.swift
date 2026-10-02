import SwiftUI
import LuminaCore

// WP-3. Cull's footer (README §2 "Footer"): progress, the key reminder or the latest message,
// and the way on to Edit and Save. It wraps on narrow windows; Save is always there (R-50).

struct CullFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let gap = 16.scaled(s), row = 8.scaled(s)
        // The first arrangement that fits, widest first.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: gap) { decided; message; buttons() }
            HStack(spacing: gap) { decided; Spacer(minLength: 0); buttons() }
            VStack(alignment: .leading, spacing: row) { decided; buttons() }
            VStack(alignment: .leading, spacing: row) { decided; buttons(optional: false) }
            VStack(alignment: .leading, spacing: row) { decided; buttons(optional: false, stacked: true) }
        }
        // The prototype's min-height 56 is CSS content-box: its padding 8 / 8 and the 1pt top
        // hairline come on top, so the footer is 73 tall (measured in the prototype at 1100 × 760
        // and 1440 × 900; golden cull-mid). The content gets the 56 here, then the padding.
        .frame(maxWidth: .infinity, minHeight: 56.scaled(s), alignment: .leading)
        .padding(.horizontal, 20.scaled(s)).padding(.top, 8.scaled(s) + 1).padding(.bottom, 8.scaled(s))
        .background(LuminaColor.bgPanel)
        .overlay(alignment: .top) { LuminaColor.hairline.frame(height: 1) }
    }

    /// "12/117 decided" over a 150 × 3 bar.
    private var decided: some View {
        let n = model.decisions.keptCount + model.decisions.outCount, total = model.total
        let share = total > 0 ? (Double(n) / Double(total) * 100).rounded() / 100 : 0
        return VStack(alignment: .leading, spacing: 5.scaled(s)) {
            (Text(verbatim: "\(n)/\(total)").fontWeight(.semibold).foregroundColor(LuminaColor.textPrimary)
                + Text(verbatim: " decided").foregroundColor(LuminaColor.textTertiary))
                .font(LuminaFont.caption(s)).lineLimit(1).fixedSize()
            ZStack(alignment: .leading) {
                Capsule().fill(LuminaColor.fill10)
                Capsule().fill(LuminaColor.textPrimary).frame(width: 150.scaled(s) * min(1, share))
            }
            .frame(width: 150.scaled(s), height: 3.scaled(s))
        }
        .frame(minWidth: 150.scaled(s), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Cull.decided)
        .accessibilityLabel("\(n) of \(total) decided")
        .accessibilityValue("\(n)/\(total)")
    }

    /// The latest message, or the key reminder. One line; it gives way before anything else does.
    private var message: some View {
        let text = model.toast?.text ?? AppModel.cullKeyReminder
        return Text(text).font(LuminaFont.small(s, id: AccessibilityID.Cull.message)).foregroundStyle(LuminaColor.textTertiary)
            .lineLimit(1).truncationMode(.tail)
            .frame(minWidth: 0, idealWidth: 120.scaled(s), maxWidth: .infinity, alignment: .leading)
            .luminaStatus(AccessibilityID.Cull.message, text)
    }

    @ViewBuilder private func buttons(optional: Bool = true, stacked: Bool = false) -> some View {
        let kept = model.decisions.keptCount
        let edit = Button { model.go(.edit) } label: {
            HStack(spacing: 8.scaled(s)) {
                Text(CullCopy.toEdit(kept: kept)).lineLimit(1)
                if optional { Text("optional").font(LuminaFont.ui(LuminaFontSize.monoHint, .regular, s)).foregroundStyle(LuminaColor.textTertiary).lineLimit(1) }
            }
            .fixedSize()
        }
        .buttonStyle(LuminaSecondaryButtonStyle(height: LuminaHeight.footerButton, radius: LuminaRadius.buttonPrimary, padding: 14))
        .help(CullCopy.editHelp)
        .accessibilityIdentifier(AccessibilityID.Cull.toEdit)
        let save = Button { model.go(.save) } label: { Text(CullCopy.toSave(kept: kept)).lineLimit(1).fixedSize() }
            .buttonStyle(LuminaPrimaryButtonStyle(height: LuminaHeight.footerButton, padding: 16))
            .accessibilityIdentifier(AccessibilityID.Cull.toSave)
        if stacked {
            VStack(alignment: .leading, spacing: 8.scaled(s)) { edit; save }
        } else {
            HStack(spacing: 8.scaled(s)) { edit; save }
        }
    }
}
