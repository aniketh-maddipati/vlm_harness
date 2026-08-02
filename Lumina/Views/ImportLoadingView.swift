import AppKit
import SwiftUI

/// Full-screen import — screen-fit wall; previews arrive slowly as ingest continues.
struct ImportLoadingView: View {
    let progress: ImportProgress
    let photos: [PhotoRecord]
    var isFinishing: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.92),
                    Color.accentColor.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 28)
                    .padding(.horizontal, 40)

                Spacer(minLength: 16)

                if previewPaths.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(pulse ? 1.06 : 0.94)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
                        .frame(maxHeight: 360)
                } else {
                    ProgressivePhotoWall(
                        paths: previewPaths,
                        revealIntervalMs: 420,
                        prefetchAhead: 6
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 12)

                footer
                    .padding(.horizontal, 48)
                    .padding(.bottom, 32)
            }
        }
        .onAppear { pulse = true }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(progress.phase.title)
                .font(.largeTitle.weight(.semibold))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.45), value: progress.phase)

            Text(progress.detail)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.35), value: progress.detail)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: max(6, geo.size.width * progress.overallFraction))
                }
            }
            .frame(height: 6)
            .animation(.spring(duration: 0.85, bounce: 0.08), value: progress.overallFraction)

            HStack {
                Text(phaseSteps)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(isFinishing ? "Opening your sets…" : "Previews fill in as we ingest · no rush")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 520)
    }

    private var previewPaths: [String] {
        let fromPhotos = photos.compactMap(\.displayThumbPath)
        return fromPhotos.isEmpty ? progress.recentThumbPaths : fromPhotos
    }

    private var phaseSteps: String {
        let all = ImportPhase.allCases.filter { $0 != .ready }
        guard let idx = all.firstIndex(of: progress.phase) else { return "" }
        return "Step \(idx + 1) of \(all.count)"
    }
}
