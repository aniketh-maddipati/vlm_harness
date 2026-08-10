import Foundation

/// Bidirectional migration between legacy `LuminaProject` / `PhotoRecord` and P0 `ShootRecord` / `AssetRecord`.
enum ShootMigration {
    /// Convert a legacy or in-memory project into the canonical shoot record.
    static func shoot(from project: LuminaProject, shootID: UUID? = nil) -> ShootRecord {
        let root = project.rawFolder.map { URL(fileURLWithPath: $0) }
        let assets = project.photos.map { photo -> AssetRecord in
            asset(from: photo, shootRoot: root)
        }
        let rawRef: SourceReference? = project.rawFolder.map { path in
            var ref = SourceReference(
                originalPath: path,
                relativePath: "",
                volumeID: AssetIdentity.volumeIdentifier(for: URL(fileURLWithPath: path)),
                availability: FileManager.default.fileExists(atPath: path) ? .available : .missing,
                lastSeenAt: FileManager.default.fileExists(atPath: path) ? Date() : nil
            )
            if let data = try? URL(fileURLWithPath: path).bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                ref.bookmarkData = data
            }
            return ref
        }
        let jpgRef: SourceReference? = project.jpgFolder.map { path in
            SourceReference(
                originalPath: path,
                relativePath: "",
                volumeID: AssetIdentity.volumeIdentifier(for: URL(fileURLWithPath: path)),
                availability: FileManager.default.fileExists(atPath: path) ? .available : .missing,
                lastSeenAt: FileManager.default.fileExists(atPath: path) ? Date() : nil
            )
        }

        var workspace = project.workspaceRestore ?? .default
        if workspace.focusedAssetID == nil {
            workspace.focusedAssetID = project.cursorPhotoID
        }

        return ShootRecord(
            schemaVersion: .current,
            id: shootID ?? project.shootID ?? UUID(),
            name: project.name,
            createdAt: project.createdAt,
            rawFolder: rawRef,
            jpgFolder: jpgRef,
            keepRateTarget: project.keepRateTarget,
            jobBrief: project.jobBrief,
            profile: project.editProfile,
            tasteSourceCount: project.tasteSourceCount,
            tasteStrength: project.tasteStrength,
            assets: assets,
            finalSetOrder: project.finalSetOrder ?? FinalSetOrder(),
            collections: project.collections,
            exportHistory: project.exportHistory ?? [],
            batchHistory: project.batchHistory ?? [],
            decisionLedger: project.decisionLedger,
            auditSeedPhotoIDs: project.auditSeedPhotoIDs,
            workspace: workspace,
            wholesaleExcludedPhotoIDs: project.wholesaleExcludedPhotoIDs
        )
    }

    static func asset(from photo: PhotoRecord, shootRoot: URL?) -> AssetRecord {
        let fileURL = URL(fileURLWithPath: photo.rawPath)
        let root = shootRoot ?? fileURL.deletingLastPathComponent()
        let relative = photo.sourceRelativePath
            ?? AssetIdentity.relativePath(file: fileURL, root: root)
        let size = photo.fileSize ?? AssetIdentity.fileSize(of: fileURL)
        let volume = photo.sourceVolumeID ?? AssetIdentity.volumeIdentifier(for: fileURL)
        let key = photo.sourceKey ?? AssetIdentity.sourceKey(
            volumeID: volume,
            relativePath: relative,
            fileSize: size,
            capturedAt: photo.capturedAt
        )
        var source = SourceReference(
            originalPath: photo.rawPath,
            bookmarkData: photo.sourceBookmark,
            relativePath: relative,
            volumeID: volume,
            availability: photo.sourceAvailability,
            lastSeenAt: photo.sourceAvailability == .available ? Date() : nil
        )
        if source.bookmarkData == nil,
           FileManager.default.fileExists(atPath: photo.rawPath),
           let data = try? fileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
           ) {
            source.bookmarkData = data
        }

        return AssetRecord(
            id: photo.id,
            sourceKey: key,
            source: source,
            filename: photo.filename,
            cull: CullDecision(tier: photo.tier),
            recipe: photo.editRecipe,
            capturedAt: photo.capturedAt,
            fileSize: size,
            thumbPath: photo.thumbPath,
            gridThumbPath: photo.gridThumbPath,
            proxyPath: photo.proxyPath,
            previewOrigin: photo.previewOrigin,
            previewLongEdge: photo.previewLongEdge,
            sharpness: photo.sharpness,
            exposureHealth: photo.exposureHealth,
            faceQuality: photo.faceQuality,
            aesthetic: photo.aesthetic,
            compositeQuality: photo.compositeQuality,
            faceDetected: photo.faceDetected,
            cullScore: photo.cullScore,
            cullConfidence: photo.cullConfidence,
            editConfidence: photo.editConfidence,
            tasteMatch: photo.tasteMatch,
            proposedTier: photo.proposedTier,
            userDecidedAt: photo.userDecidedAt,
            settledAt: photo.settledAt,
            isFlagged: photo.isFlagged,
            isBurstHero: photo.isBurstHero,
            isClusterHero: photo.isClusterHero,
            uncertaintyKind: photo.uncertaintyKind,
            whyUncertain: photo.whyUncertain,
            whyAction: photo.whyAction,
            burstID: photo.burstID,
            clusterID: photo.clusterID,
            clusterLabel: photo.clusterLabel,
            embedding: photo.embedding
        )
    }

    /// Runtime project view used by existing ViewModels / UI.
    static func project(from shoot: ShootRecord) -> LuminaProject {
        let photos = shoot.assets.map(photo(from:))
        var project = LuminaProject(
            name: shoot.name,
            rawFolder: shoot.rawFolder?.originalPath,
            jpgFolder: shoot.jpgFolder?.originalPath,
            keepRateTarget: shoot.keepRateTarget,
            jobBrief: shoot.jobBrief,
            profile: shoot.profile.asDevelopRecipe,
            tasteSourceCount: shoot.tasteSourceCount,
            tasteStrength: shoot.tasteStrength,
            photos: photos,
            collections: shoot.collections,
            cursorPhotoID: shoot.workspace.focusedAssetID,
            decisionLedger: shoot.decisionLedger,
            auditSeedPhotoIDs: shoot.auditSeedPhotoIDs,
            createdAt: shoot.createdAt
        )
        project.shootID = shoot.id
        project.editProfile = shoot.profile
        project.finalSetOrder = shoot.finalSetOrder
        project.exportHistory = shoot.exportHistory
        project.batchHistory = shoot.batchHistory
        project.workspaceRestore = shoot.workspace
        project.wholesaleExcludedPhotoIDs = shoot.wholesaleExcludedPhotoIDs
        return project
    }

    static func photo(from asset: AssetRecord) -> PhotoRecord {
        var photo = PhotoRecord(
            id: asset.id,
            rawPath: asset.source.originalPath,
            filename: asset.filename,
            thumbPath: asset.thumbPath,
            gridThumbPath: asset.gridThumbPath,
            proxyPath: asset.proxyPath,
            previewOrigin: asset.previewOrigin,
            previewLongEdge: asset.previewLongEdge,
            capturedAt: asset.capturedAt,
            burstID: asset.burstID,
            clusterID: asset.clusterID,
            clusterLabel: asset.clusterLabel,
            sharpness: asset.sharpness,
            exposureHealth: asset.exposureHealth,
            faceQuality: asset.faceQuality,
            aesthetic: asset.aesthetic,
            compositeQuality: asset.compositeQuality,
            faceDetected: asset.faceDetected,
            cullScore: asset.cullScore,
            cullConfidence: asset.cullConfidence,
            editConfidence: asset.editConfidence,
            tasteMatch: asset.tasteMatch,
            tier: asset.cull.asTier,
            proposedTier: asset.proposedTier,
            userDecidedAt: asset.userDecidedAt,
            settledAt: asset.settledAt,
            isFlagged: asset.isFlagged,
            isBurstHero: asset.isBurstHero,
            isClusterHero: asset.isClusterHero,
            uncertaintyKind: asset.uncertaintyKind,
            whyUncertain: asset.whyUncertain,
            whyAction: asset.whyAction,
            editRecipe: asset.recipe,
            embedding: asset.embedding
        )
        photo.sourceKey = asset.sourceKey
        photo.sourceRelativePath = asset.source.relativePath
        photo.sourceVolumeID = asset.source.volumeID
        photo.sourceBookmark = asset.source.bookmarkData
        photo.sourceAvailability = asset.source.availability
        photo.fileSize = asset.fileSize
        return photo
    }

    /// Decode either a P0 `ShootRecord` or a legacy `LuminaProject` blob.
    static func decodeShoot(from data: Data) throws -> ShootRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let shoot = try? decoder.decode(ShootRecord.self, from: data),
           shoot.schemaVersion.rawValue >= 1,
           !shoot.name.isEmpty {
            return migrateForward(shoot)
        }

        do {
            let legacy = try decoder.decode(LuminaProject.self, from: data)
            return shoot(from: legacy)
        } catch {
            throw ShootStoreError.migrationFailed(error.localizedDescription)
        }
    }

    static func migrateForward(_ shoot: ShootRecord) -> ShootRecord {
        switch shoot.schemaVersion {
        case .v1:
            return shoot
        }
    }
}
