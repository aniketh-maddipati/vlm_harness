import AppKit
import SwiftUI

/// Large tactile develop slider — wide track, fat thumb, local draft while dragging
/// so the control stays snappy even when RAW scrub is catching up.
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

    @State private var draft: Double?
    @State private var isDragging = false
    @State private var lastScrubAt: CFAbsoluteTime = 0
    @State private var trackWidth: CGFloat = 1

    private var shown: Double { draft ?? value }
    private var isChanged: Bool { abs(shown - neutral) > 0.000_5 }
    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((shown - range.lowerBound) / span)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(LuminaTokens.Typeface.navigation(14, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Spacer(minLength: 6)
                Text(display(shown))
                    .font(LuminaTokens.Typeface.count(14))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .monospacedDigit()
                if isChanged {
                    Button(action: {
                        draft = nil
                        onReset()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(LuminaTokens.Ink.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to as-shot")
                }
            }

            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let thumb: CGFloat = 28
                let travel = max(width - thumb, 1)
                let x = fraction * travel

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(LuminaTokens.Surface.well)
                        .frame(height: 12)

                    Capsule(style: .continuous)
                        .fill(LuminaTokens.Ink.primary.opacity(enabled ? 0.88 : 0.28))
                        .frame(width: max(x + thumb * 0.5, 12), height: 12)

                    Circle()
                        .fill(LuminaTokens.Surface.porcelain)
                        .overlay {
                            Circle()
                                .strokeBorder(LuminaTokens.Ink.primary.opacity(0.55), lineWidth: 1.5)
                        }
                        .shadow(color: LuminaTokens.Ink.primary.opacity(0.14), radius: 4, y: 1)
                        .frame(width: thumb, height: thumb)
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width, thumb: thumb))
                .onAppear { trackWidth = width }
                .onChange(of: geo.size.width) { _, w in trackWidth = w }
            }
            .frame(height: 44)
            .opacity(enabled ? 1 : 0.42)
            .allowsHitTesting(enabled)
            .onTapGesture(count: 2) {
                guard enabled, isChanged else { return }
                draft = nil
                onReset()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(display(shown))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            let delta = step * (direction == .increment ? 1 : -1)
            commit(shown + delta, beginIfNeeded: true, forceScrub: true, end: true)
        }
        .onChange(of: value) { _, newValue in
            guard !isDragging else { return }
            draft = nil
            _ = newValue
        }
    }

    private func dragGesture(width: CGFloat, thumb: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard enabled else { return }
                if !isDragging {
                    isDragging = true
                    onBegin()
                }
                let travel = max(width - thumb, 1)
                let clampedX = min(max(gesture.location.x - thumb * 0.5, 0), travel)
                let raw = range.lowerBound + Double(clampedX / travel) * (range.upperBound - range.lowerBound)
                let precise = NSEvent.modifierFlags.contains(.option)
                let next: Double
                if precise {
                    let from = draft ?? value
                    next = from + (raw - from) * 0.18
                } else {
                    next = snap(raw)
                }
                commit(next, beginIfNeeded: false, forceScrub: false, end: false)
            }
            .onEnded { _ in
                guard enabled else { return }
                let final = draft ?? value
                commit(final, beginIfNeeded: false, forceScrub: true, end: true)
                isDragging = false
                draft = nil
            }
    }

    private func snap(_ raw: Double) -> Double {
        let stepped = (raw / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private func commit(_ raw: Double, beginIfNeeded: Bool, forceScrub: Bool, end: Bool) {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        draft = clamped
        if beginIfNeeded, !isDragging {
            isDragging = true
            onBegin()
        }
        let now = CFAbsoluteTimeGetCurrent()
        // ~40 Hz to session/render while the thumb itself updates every frame.
        if forceScrub || now - lastScrubAt >= 0.024 {
            lastScrubAt = now
            onScrub(clamped)
        }
        if end {
            onScrub(clamped)
            onEnd()
        }
    }
}

/// Large rail section header — easy to hit without precision aiming.
struct P0RailSectionHeader: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(LuminaTokens.Typeface.navigation(16, weight: .semibold))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: LuminaTokens.HitTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
