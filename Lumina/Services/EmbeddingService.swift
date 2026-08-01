import Foundation
import ImageIO
import CoreGraphics
import Vision
import AppKit

/// On-device Vision feature prints (+ histogram fallback) for composition similarity.
/// No cloud model required — `VNGenerateImageFeaturePrintRequest` is Apple’s local embedding.
enum EmbeddingService {
    static func embedAndCluster(_ input: [PhotoRecord]) async -> [PhotoRecord] {
        var photos = input
        let indexed = Array(photos.indices)

        await withTaskGroup(of: (Int, [Float]?).self) { group in
            for index in indexed {
                group.addTask {
                    let path = photos[index].displayThumbPath ?? photos[index].thumbPath
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
        if let vision = visionFeaturePrint(url: url) {
            return vision
        }
        return histogramEmbedding(url: url)
    }

    // MARK: - Vision feature print (local model)

    private static func visionFeaturePrint(url: URL) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                return nil
            }
            return floats(from: observation)
        } catch {
            return nil
        }
    }

    private static func floats(from observation: VNFeaturePrintObservation) -> [Float]? {
        let count = Int(observation.elementCount)
        guard count > 0 else { return nil }
        var values = [Float](repeating: 0, count: count)
        let copied: Bool = observation.data.withUnsafeBytes { raw in
            guard raw.count >= count * MemoryLayout<Float>.stride,
                  let base = raw.bindMemory(to: Float.self).baseAddress else { return false }
            for i in 0..<count { values[i] = base[i] }
            return true
        }
        guard copied else { return nil }
        return l2normalize(values)
    }

    private static func histogramEmbedding(url: URL) -> [Float]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        // 4x4 spatial × 8 hue bins — better composition signal than global histogram
        var hist = [Float](repeating: 0, count: 4 * 4 * 8)
        let bpp = max(cg.bitsPerPixel / 8, 1)
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        for y in 0..<h {
            for x in 0..<w {
                let o = x * bpp + y * cg.bytesPerRow
                if o + 2 >= CFDataGetLength(data) { continue }
                let r = Float(ptr[o]) / 255
                let g = Float(ptr[o + 1]) / 255
                let b = Float(ptr[o + 2]) / 255
                let mx = max(r, g, b)
                let mn = min(r, g, b)
                var hue: Float = 0
                let d = mx - mn
                if d > 1e-4 {
                    if mx == r { hue = (g - b) / d }
                    else if mx == g { hue = 2 + (b - r) / d }
                    else { hue = 4 + (r - g) / d }
                    hue = ((hue / 6).truncatingRemainder(dividingBy: 1) + 1)
                        .truncatingRemainder(dividingBy: 1)
                }
                let sx = min(x * 4 / w, 3)
                let sy = min(y * 4 / h, 3)
                let hb = min(Int(hue * 8), 7)
                hist[(sy * 4 + sx) * 8 + hb] += 1
            }
        }
        let sum = hist.reduce(0, +)
        if sum > 0 {
            for i in hist.indices { hist[i] /= sum }
        }
        return l2normalize(hist)
    }

    // MARK: - Clustering

    /// Burst-first, then merge visually similar groups. Threshold tuned for Vision prints.
    private static func cluster(_ photos: [PhotoRecord], threshold: Float = 0.55) -> [String: [Int]] {
        // 1) Seed: every burst is a hard group (near-duplicate frames stay together)
        var burstBuckets: [String: [Int]] = [:]
        for i in photos.indices {
            let key = photos[i].burstID ?? "solo-\(photos[i].id.uuidString)"
            burstBuckets[key, default: []].append(i)
        }

        var groups: [[Int]] = burstBuckets.values.map { $0.sorted() }

        // 2) Merge groups whose centroids are close (composition / objects)
        var merged = true
        while merged {
            merged = false
            outer: for i in 0..<groups.count {
                for j in (i + 1)..<groups.count {
                    guard let ci = centroid(photos, groups[i]),
                          let cj = centroid(photos, groups[j]) else { continue }
                    if distance(ci, cj) <= threshold {
                        groups[i].append(contentsOf: groups[j])
                        groups.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }

        // 3) Absorb tiny singles into nearest multi if close enough
        var multi = groups.filter { $0.count >= 2 }
        var singles = groups.filter { $0.count == 1 }
        var absorbed: [Int] = []
        for (si, solo) in singles.enumerated() {
            guard let idx = solo.first, let e = photos[idx].embedding else { continue }
            var bestJ: Int?
            var bestD: Float = threshold * 1.15
            for (ji, m) in multi.enumerated() {
                guard let c = centroid(photos, m) else { continue }
                let d = distance(e, c)
                if d < bestD {
                    bestD = d
                    bestJ = ji
                }
            }
            if let bestJ {
                multi[bestJ].append(idx)
                absorbed.append(si)
            }
        }
        for si in absorbed.sorted(by: >) {
            singles.remove(at: si)
        }

        let finalGroups = multi + singles
        var result: [String: [Int]] = [:]
        for (n, members) in finalGroups.enumerated() {
            result["set-\(n)"] = members.sorted()
        }
        return result
    }

    private static func centroid(_ photos: [PhotoRecord], _ indices: [Int]) -> [Float]? {
        let embeds = indices.compactMap { photos[$0].embedding }
        guard let first = embeds.first else { return nil }
        var acc = [Float](repeating: 0, count: first.count)
        for e in embeds {
            let n = min(acc.count, e.count)
            for i in 0..<n { acc[i] += e[i] }
        }
        let inv = 1 / Float(embeds.count)
        for i in acc.indices { acc[i] *= inv }
        return l2normalize(acc)
    }

    private static func labelForCluster(photos: [PhotoRecord], indices: [Int]) -> String {
        let n = indices.count
        let faces = indices.filter { photos[$0].faceDetected }.count
        let avgSharp = indices.map { photos[$0].sharpness }.reduce(0, +) / Double(max(n, 1))
        let burstIDs = indices.compactMap { photos[$0].burstID }
        let allSameBurst = burstIDs.count == n && Set(burstIDs).count == 1 && n > 1
        let multiBurst = Set(burstIDs).count > 1 && n >= 3

        if allSameBurst { return "Burst · \(n) frames" }
        if multiBurst { return "Sequence · \(n) frames" }
        if faces >= (n + 1) / 2 { return "Portraits · \(n)" }
        if avgSharp < 0.35 { return "Soft / motion · \(n)" }
        return "Similar look · \(n)"
    }

    static func l2Distance(_ a: [Float], _ b: [Float]) -> Float {
        distance(a, b)
    }

    private static func distance(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        // Cosine distance for normalized vectors
        var dot: Float = 0
        for i in 0..<n { dot += a[i] * b[i] }
        return max(0, 1 - dot)
    }

    private static func l2normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 1e-6 else { return v }
        return v.map { $0 / norm }
    }
}
