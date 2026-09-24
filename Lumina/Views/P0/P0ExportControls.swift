import SwiftUI

/// One remembered export recipe and receipts for the actual owned output folder.
struct P0ExportControls: View {
    @Bindable var session: P0SessionModel
    private enum Field: Hashable { case settings, format, size, quality, cancel, resume, reveal }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: ElasticLayout.headerGap) {
            HStack(spacing: ElasticLayout.headerGap) {
                Button(CopyContract.exportSettings) { session.exportSettingsVisible.toggle() }
                    .buttonStyle(LuminaElasticButtonStyle())
                    .help("⌥⌘E changes the recipe.")
                    .focused($focusedField, equals: .settings)
                Text(session.exportStatusLine ?? settingsLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if session.isExporting {
                    Button("Cancel") { session.cancelExport() }
                        .buttonStyle(LuminaElasticButtonStyle())
                        .focused($focusedField, equals: .cancel)
                } else if session.canResumeExport {
                    Button("Retry / Resume") { session.resumeExport() }
                        .buttonStyle(LuminaElasticButtonStyle())
                        .focused($focusedField, equals: .resume)
                }
                if session.exportSummary != nil || session.canResumeExport {
                    Button("Show in Finder") { session.revealExport() }
                        .buttonStyle(LuminaElasticButtonStyle())
                        .focused($focusedField, equals: .reveal)
                }
            }
            if session.exportStatusLine != nil {
                Text(settingsLabel)
            }
            if session.isExporting || session.canResumeExport {
                Text("Retry / Resume uses the original job’s frozen settings.")
            }
            if session.exportSettingsVisible {
                HStack(spacing: ElasticLayout.headerGap) {
                    Picker("Format", selection: $session.exportSettings.format) {
                        Text("JPEG · sRGB").tag(P0ExportSettings.Format.jpeg)
                        Text("TIFF · ProPhoto RGB").tag(P0ExportSettings.Format.tiff)
                    }
                    .focused($focusedField, equals: .format)
                    Picker("Size", selection: $session.exportSettings.longEdge) {
                        Text("Full size").tag(P0ExportControlLayout.fullSize)
                        Text("2048 px long edge").tag(P0ExportControlLayout.smallSize)
                        Text("4096 px long edge").tag(P0ExportControlLayout.largeSize)
                    }
                    .focused($focusedField, equals: .size)
                    if session.exportSettings.format == .jpeg {
                        Picker("Quality", selection: $session.exportSettings.quality) {
                            Text("95%").tag(P0ExportControlLayout.defaultQuality)
                            Text("85%").tag(P0ExportControlLayout.compactQuality)
                            Text(P0ExportControlLayout.maximumQuality, format: .percent).tag(P0ExportControlLayout.maximumQuality)
                        }
                        .focused($focusedField, equals: .quality)
                    }
                }
                .disabled(session.isExporting)
                Text(CopyContract.exportPolicy)
            }
            if let failure = session.exportSummary?.firstFailure {
                Text(failure)
                    .textSelection(.enabled)
            }
            if let summary = session.exportSummary {
                Text(summary.root.path)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(ElasticType.mono(ElasticLayout.headerTextSize))
        .foregroundStyle(LuminaTokens.Elastic.muted)
        .padding(.horizontal, ElasticLayout.chromeGutter)
        .padding(.vertical, ElasticLayout.headerGap)
        .background(LuminaTokens.Elastic.shell)
        .onChange(of: focusedField) { _, field in session.exportControlsFocused = field != nil }
        .onChange(of: session.exportSettingsVisible) { _, visible in focusedField = visible ? .format : .settings }
        .onDisappear { session.exportControlsFocused = false }
    }

    private var settingsLabel: String {
        "New export · \(P0ExportPresentation.settings(session.exportSettings))"
    }
}
