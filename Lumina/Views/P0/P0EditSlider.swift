import AppKit
import SwiftUI

/// Gesture-coalesced develop slider — live scrub without undo flooding.
struct P0EditSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String
    let neutral: Double
    let enabled: Bool
    let onBegin: () -> Void
    let onScrub: (Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void

    @State private var isDragging = false
    @State private var optionPrecision = false

    private var isChanged: Bool { abs(value - neutral) > 0.000_5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Spacer(minLength: 4)
                Text(display(value))
                    .font(LuminaTokens.Typeface.count(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .monospacedDigit()
                if isChanged {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(LuminaTokens.Ink.tertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to as-shot")
                }
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { next in
                        let precise = NSEvent.modifierFlags.contains(.option)
                        optionPrecision = precise
                        let resolved = precise
                            ? value + (next - value) * 0.15
                            : next
                        let clamped = min(max(resolved, range.lowerBound), range.upperBound)
                        onScrub(clamped)
                    }
                ),
                in: range,
                step: step,
                onEditingChanged: { editing in
                    if editing {
                        isDragging = true
                        onBegin()
                    } else if isDragging {
                        isDragging = false
                        onEnd()
                    }
                }
            )
            .controlSize(.regular)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .frame(minHeight: 28)
            .onTapGesture(count: 2) {
                guard enabled, isChanged else { return }
                onReset()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(display(value))
    }
}

/// Lightweight section header — one expanded section at a time.
struct P0RailSectionHeader: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
