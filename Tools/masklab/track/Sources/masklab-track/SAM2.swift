#if canImport(Vision) && canImport(AVFoundation)
import CoreML
import CoreVideo
import Foundation
import MaskLabCore
import Vision
import VideoToolbox

/// sam2-coreml, experimental. Written against an assumed interface of Apple's Core ML conversions
/// of SAM 2.1 (Hugging Face, apple/coreml-sam2.1-*: three models, image encoder, prompt encoder,
/// mask decoder); none was downloaded or run when this was written. The assumption, also in the
/// README:
///   image encoder   in:  one image input (square, e.g. 1024 × 1024)
///                   out: image_embedding, feats_s0, feats_s1 (passed to the decoder by name)
///   prompt encoder  in:  points [1, N, 2] (pixels in the encoder's input space), labels [1, N]
///                        (1 = on the object, 2 / 3 = box corners)
///                   out: sparse and dense embeddings (passed to the decoder by name)
///   mask decoder    in:  every input named like an encoder or prompt-encoder output
///                        (exactly, or with / without a trailing "s")
///                   out: low_res_masks [1, K, h, w] logits, scores [1, K]
/// The check runs before the first frame and names what the models really have when it fails.
///
/// These conversions take one image and a prompt; SAM 2's video memory is not in them. So this is
/// SAM per frame, the prompt carried forward as the last mask's box (SAMPrompt.follow), not SAM 2's
/// own video tracking.
final class SAM2Tracker: FrameTracker {
    private let encoder: MLModel, prompter: MLModel, decoder: MLModel
    private let imageInput: String, imageConstraint: MLImageConstraint
    private var prompt: Prompt?
    var confidence: Double? { nil }

    init(modelDir: URL) async throws {
        let files = (try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)) ?? []
        func find(_ word: String) async throws -> MLModel {
            let hits = files.filter {
                ["mlpackage", "mlmodelc", "mlmodel"].contains($0.pathExtension.lowercased())
                    && $0.lastPathComponent.lowercased().contains(word.lowercased())
            }
            // A compiled model is used as it is; a package is compiled first (into a temp folder).
            guard let url = hits.first(where: { $0.pathExtension == "mlmodelc" }) ?? hits.first else {
                throw UsageError("sam2-coreml: no model with \"\(word)\" in its name in \(modelDir.path) (expected the image encoder, prompt encoder and mask decoder of a SAM 2.1 Core ML conversion)")
            }
            let compiled = url.pathExtension == "mlmodelc" ? url : try await MLModel.compileModel(at: url)
            let config = MLModelConfiguration()
            config.computeUnits = .all
            return try MLModel(contentsOf: compiled, configuration: config)
        }
        encoder = try await find("ImageEncoder")
        prompter = try await find("PromptEncoder")
        decoder = try await find("MaskDecoder")

        guard let image = encoder.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .image }),
              let constraint = image.value.imageConstraint else {
            throw UsageError("sam2-coreml: the image encoder has no image input; its inputs: \(SAM2Tracker.names(encoder.modelDescription.inputDescriptionsByName))")
        }
        guard constraint.pixelsWide == constraint.pixelsHigh else {
            throw UsageError("sam2-coreml: assumed a square encoder input, got \(constraint.pixelsWide) × \(constraint.pixelsHigh)")
        }
        imageInput = image.key
        imageConstraint = constraint
        let prompterIn = prompter.modelDescription.inputDescriptionsByName
        guard prompterIn["points"] != nil, prompterIn["labels"] != nil else {
            throw UsageError("sam2-coreml: assumed prompt encoder inputs points + labels, got \(SAM2Tracker.names(prompterIn))")
        }
        let available = Set(encoder.modelDescription.outputDescriptionsByName.keys)
            .union(prompter.modelDescription.outputDescriptionsByName.keys)
        for name in decoder.modelDescription.inputDescriptionsByName.keys where SAM2Tracker.match(name, in: available) == nil {
            throw UsageError("sam2-coreml: the mask decoder's input \(name) is not an encoder or prompt encoder output (have \(available.sorted().joined(separator: ", ")))")
        }
    }

    func first(_ frame: CVPixelBuffer, prompt: Prompt) throws -> Mask {
        self.prompt = prompt
        return try step(frame)
    }

    func next(_ frame: CVPixelBuffer) throws -> Mask { try step(frame) }

    private func step(_ frame: CVPixelBuffer) throws -> Mask {
        let w = CVPixelBufferGetWidth(frame), h = CVPixelBufferGetHeight(frame)
        guard let prompt else { return Mask(width: w, height: h) }

        var cg: CGImage?
        VTCreateCGImageFromCVPixelBuffer(frame, options: nil, imageOut: &cg)
        guard let cg else { throw UsageError("sam2-coreml: can't convert the frame") }
        // Stretched to the square input; the masks are stretched back the same way.
        let image = try MLFeatureValue(cgImage: cg, constraint: imageConstraint,
                                       options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let encoded = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [imageInput: image]))

        let (xy, labels) = SAMPrompt.points(prompt, side: Double(imageConstraint.pixelsWide))
        let n = labels.count
        let inputs = prompter.modelDescription.inputDescriptionsByName
        let points = try MLMultiArray(shape: [1, NSNumber(value: n), 2], dataType: inputs["points"]?.multiArrayConstraint?.dataType ?? .float32)
        for (i, v) in xy.enumerated() { points[i] = NSNumber(value: v) }
        let pointLabels = try MLMultiArray(shape: [1, NSNumber(value: n)], dataType: inputs["labels"]?.multiArrayConstraint?.dataType ?? .int32)
        for (i, v) in labels.enumerated() { pointLabels[i] = NSNumber(value: v) }
        let prompted = try prompter.prediction(from: MLDictionaryFeatureProvider(dictionary: ["points": points, "labels": pointLabels]))

        var pool: [String: MLFeatureValue] = [:]
        for p in [encoded, prompted] { for name in p.featureNames { pool[name] = p.featureValue(for: name) } }
        var decoderIn: [String: MLFeatureValue] = [:]
        for name in decoder.modelDescription.inputDescriptionsByName.keys {
            guard let key = SAM2Tracker.match(name, in: Set(pool.keys)), let v = pool[key] else {
                throw UsageError("sam2-coreml: no value for the decoder's input \(name)")
            }
            decoderIn[name] = v
        }
        let decoded = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: decoderIn))
        let arrays = decoded.featureNames.compactMap { name in decoded.featureValue(for: name)?.multiArrayValue.map { (name, $0) } }
        guard let masks = arrays.first(where: { $0.0 == "low_res_masks" })?.1 ?? arrays.first(where: { $0.1.shape.count == 4 })?.1 else {
            throw UsageError("sam2-coreml: no 4-dimensional mask output (have \(decoded.featureNames.sorted().joined(separator: ", ")))")
        }
        let k = masks.shape[1].intValue
        var choice = 0
        if let scores = arrays.first(where: { $0.0 == "scores" })?.1 ?? arrays.first(where: { $0.1.shape.count == 2 })?.1,
           scores.count == k {
            choice = SAMPrompt.best((0..<k).map { scores[$0].floatValue }) ?? 0
        }
        let mh = masks.shape[2].intValue, mw = masks.shape[3].intValue
        let s = masks.strides.map(\.intValue)
        let mask = Mask.threshold(width: mw, height: mh, outWidth: w, outHeight: h, above: 0) { x, y in
            masks[choice * s[1] + y * s[2] + x * s[3]].floatValue   // logits: > 0 is in
        }
        // Lost: keep the last prompt, so a frame where the object is back can pick it up again.
        if let next = SAMPrompt.follow(mask) { self.prompt = next }
        return mask
    }

    /// `name`, or the same with / without a trailing "s" (sparse_embedding ⇄ sparse_embeddings).
    static func match(_ name: String, in names: Set<String>) -> String? {
        if names.contains(name) { return name }
        if names.contains(name + "s") { return name + "s" }
        if name.hasSuffix("s"), names.contains(String(name.dropLast())) { return String(name.dropLast()) }
        return nil
    }

    static func names(_ d: [String: MLFeatureDescription]) -> String { d.keys.sorted().joined(separator: ", ") }
}
#endif
