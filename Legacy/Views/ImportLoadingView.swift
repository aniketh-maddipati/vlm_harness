import AppKit
import SwiftUI

/// Full-screen import — the shoot arrives; machinery stays quiet.
struct ImportLoadingView: View {
    let progress: ImportProgress
    let photos: [PhotoRecord]
    var isFinishing: Bool

    var body: some View {
        ZStack {
            LuminaAtmosphereBackdrop()

            VStack(spacing: 0) {
                header
                    .padding(.top, 36)
                    .padding(.horizontal, 48)

                Spacer(minLength: 20)

                if previewPaths.isEmpty {
                    Text("Gathering light…")
                        .font(LuminaAtmosphere.Typeface.body(15))
                        .foregroundStyle(LuminaAtmosphere.breath)
                        .frame(maxHeight: 360)
                } else {
                    ProgressivePhotoWall(
                        paths: previewPaths,
                        revealIntervalMs: 480,
                        prefetchAhead: 6
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 16)

                footer
                    .padding(.horizontal, 48)
                    .padding(.bottom, 36)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(isFinishing ? "Settling" : arrivalTitle)
                .font(LuminaAtmosphere.Typeface.display(32))
                .foregroundStyle(Color.white.opacity(0.92))
                .contentTransition(.opacity)
                .animation(LuminaAtmosphere.Motion.reveal, value: progress.phase)

            Text(progress.detail)
                .font(LuminaAtmosphere.Typeface.body(15))
                .foregroundStyle(LuminaAtmosphere.whisper)
                .multilineTextAlignment(.center)
                .animation(LuminaAtmosphere.Motion.condense, value: progress.detail)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LuminaAtmosphere.affirm.opacity(0.85))
                        .frame(width: max(4, geo.size.width * progress.overallFraction))
                }
            }
            .frame(height: 2)
            .animation(LuminaAtmosphere.Motion.settle, value: progress.overallFraction)

            HStack {
                Text(isFinishing ? "Opening the shoot" : CopyContract.copyingOriginals)
                    .font(LuminaAtmosphere.Typeface.caption(11))
                    .foregroundStyle(LuminaAtmosphere.breath)
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed) · \(progress.total)")
                        .font(LuminaAtmosphere.Typeface.caption(11).monospacedDigit())
                        .foregroundStyle(LuminaAtmosphere.breath)
                }
            }
        }
        .frame(maxWidth: 480)
    }

    private var previewPaths: [String] {
        let fromPhotos = photos.compactMap(\.displayThumbPath)
        return fromPhotos.isEmpty ? progress.recentThumbPaths : fromPhotos
    }

    private var arrivalTitle: String {
        switch progress.phase {
        case .metadata, .previews: "Arriving"
        case .quality: "Seeing"
        case .taste, .grouping, .faces, .edits: "Learning the look"
        case .ready: "Settling"
        }
    }
}
