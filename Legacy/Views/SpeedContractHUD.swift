// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import SwiftUI

/// Speed Contract debug HUD — toggle with ⌥` (Option + backtick).
struct SpeedContractHUD: View {
    @Bindable var model: ProjectViewModel

    private var spine: PreviewSpine { PreviewSpine.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SPEED CONTRACT · DEFEATER KILLED")
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(.green)
                Spacer()
                Text(slaBadge)
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(photonP95Ok ? .green : .red)
            }
            ForEach(spine.hudLines(), id: \.self) { line in
                Text(line)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("photon samples: \(LatencyMetrics.sampleCount(for: "spine.input_to_photon")) · ⌥` hide")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(10)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            model.speedHUDPulse &+= 1
        }
        .opacity(model.showSpeedHUD ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var photonP95Ok: Bool {
        guard let p95 = LatencyMetrics.p95(for: "spine.input_to_photon") else { return true }
        return p95 <= LatencyMetrics.navigationSLAms
    }

    private var slaBadge: String {
        if let p95 = LatencyMetrics.p95(for: "spine.input_to_photon") {
            return p95 <= 50 ? "photon p95 PASS" : "photon p95 FAIL"
        }
        return "photon p95 —"
    }
}
