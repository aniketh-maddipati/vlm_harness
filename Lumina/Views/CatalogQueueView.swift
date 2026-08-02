import SwiftUI

struct CatalogQueueView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Backlog queue")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.catalogQueue.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(model.catalogQueue.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !model.agentPlanText.isEmpty {
                Text(model.agentPlanText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if model.isCatalogMode, !model.catalogQueue.folders.isEmpty {
                backlogProgress
                folderStrip
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var backlogProgress: some View {
        let total = max(model.catalogQueue.totalFolders, 1)
        let cleared = model.catalogQueue.clearedCount
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(cleared), total: Double(total))
                .tint(.accentColor)
            Text("\(cleared)/\(total) folders cleared")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.catalogQueue.folders.prefix(24)) { folder in
                    CatalogFolderChip(
                        folder: folder,
                        isActive: folder.id == model.catalogQueue.activeFolderID
                    )
                }
                if model.catalogQueue.folders.count > 24 {
                    Text("+\(model.catalogQueue.folders.count - 24)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 28)
    }
}

private struct CatalogFolderChip: View {
    let folder: CatalogFolder
    let isActive: Bool

    private var tint: Color {
        switch folder.status {
        case .cleared: .green.opacity(0.7)
        case .active: .accentColor
        case .indexed: folder.needsYouCount > 0 ? .orange : .secondary.opacity(0.5)
        case .indexing: .yellow.opacity(0.8)
        case .error: .red.opacity(0.8)
        case .pending: .secondary.opacity(0.35)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(folder.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
            in: Capsule()
        )
        .overlay {
            if isActive {
                Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
        }
    }
}
