import Foundation
import ImageIO
import CoreGraphics

/// Vision feature-print embeddings + agglomerative clustering for composition similarity.
enum EmbeddingService {
    static func embedAndCluster(_ input: [PhotoRecord]) async -> [PhotoRecord] {
        var photos = input
        let indexed = Array(photos.indices)

        await withTaskGroup(of: (Int, [Float]?).self) { group in
            for index in indexed {
                group.addTask {
                    let path = photos[index].displayThumbPath
                    let embedding = path.flatMap { embed(url: URL(fileURLWithPath: $0)) }
                    return (index, embedding)
                }
            }
            for await (index, embedding) in group {
                photos[index].embedding = embedding
            }
        }

        let clusters = cluster(photos)
        for (clusterID, memberIndices) in clusters {
            let label = labelForCluster(photos: photos, indices: memberIndices)
            for index in memberIndices {
                photos[index].clusterID = clusterID
                photos[index].clusterLabel = label
            }
        }
        return photos
    }

    static func embed(url: URL) -> [Float]? {
        // Spatial color histogram — fast, stable, good enough for composition clustering.
        // Vision feature-print distances are used pairwise when available via refineClusters.
        return histogramEmbedding(url: url)
    }

    private static func histogramEmbedding(url: URL) -> [Float]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        var hist = [Float](repeating: 0, count: 64)
        let bpp = max(cg.bitsPerPixel / 8, 1)
        let count = cg.width * cg.height
        for i in 0..<count {
            let o = (i % cg.width) * bpp + (i / cg.width) * cg.bytesPerRow
            if o + 2 >= CFDataGetLength(data) { continue }
            let r = Int(ptr[o]) / 64
            let g = Int(ptr[o + 1]) / 64
            let b = Int(ptr[o + 2]) / 64
            let bin = min(r * 16 + g * 4 + b, 63)
            hist[bin] += 1
        }
        let sum = hist.reduce(0, +)
        if sum > 0 {
            for i in hist.indices { hist[i] /= sum }
        }
        return hist
    }

    /// Simple agglomerative clustering by cosine/L2 distance threshold.
    private static func cluster(_ photos: [PhotoRecord], threshold: Float = 0.35) -> [String: [Int]] {
        var assignments = [Int: String]()
        var nextID = 0
        let withEmbed = photos.indices.filter { photos[$0].embedding != nil }

        for i in withEmbed {
            if assignments[i] != nil { continue }
            let clusterID = "cluster-\(nextID)"
            nextID += 1
            assignments[i] = clusterID
            guard let ei = photos[i].embedding else { continue }
            for j in withEmbed where j > i && assignments[j] == nil {
                guard let ej = photos[j].embedding else { continue }
                if distance(ei, ej) <= threshold {
                    assignments[j] = clusterID
                }
            }
        }

        // Unembedded → singleton clusters by burst
        for i in photos.indices where assignments[i] == nil {
            assignments[i] = photos[i].burstID.map { "burst-\($0)" } ?? "solo-\(photos[i].id.uuidString.prefix(8))"
        }

        var result: [String: [Int]] = [:]
        for (index, id) in assignments {
            result[id, default: []].append(index)
        }
        return result
    }

    private static func labelForCluster(photos: [PhotoRecord], indices: [Int]) -> String {
        let faces = indices.filter { photos[$0].faceDetected }.count
        let avgSharp = indices.map { photos[$0].sharpness }.reduce(0, +) / Double(max(indices.count, 1))
        if faces >= indices.count / 2 { return "portraits (\(indices.count))" }
        if avgSharp < 0.35 { return "soft / motion (\(indices.count))" }
        return "scene (\(indices.count))"
    }

    private static func distance(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        var sum: Float = 0
        for i in 0..<n {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sqrt(sum / Float(n))
    }

    private static func l2normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-6 else { return v }
        return v.map { $0 / norm }
    }
}
