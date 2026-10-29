import CoreGraphics
import Foundation
import FoundationModels
import Vision

/// The text read from a word's strokes.
public struct HandwritingResult: Sendable, Hashable {
    /// Best reading.
    public var text: String
    /// Vision confidence `0...1`.
    public var confidence: Double
    /// Other readings, best first.
    public var alternatives: [String]
}

/// Reads air-written strokes on-device by rendering them as ink and running Vision text recognition.
public enum HandwritingRecognizer {
    /// Render passes tried in order: image height in pixels and pen width as a fraction of that height.
    static let passes: [(height: Int, lineWidth: Double)] = [(128, 0.045), (256, 0.06), (192, 0.08)]

    /// Renders strokes (normalized, y up) as black ink on white, scaled to `height` pixels.
    /// - Parameter xScale: image aspect ratio, so normalized x and y distances are comparable (4:3 VGA camera).
    public static func render(_ strokes: [[Point2D]], height: Int = 128, lineWidth: Double = 0.045,
                              xScale: Double = 4.0 / 3.0) -> CGImage? {
        let points = strokes.flatMap { $0 }.map { Point2D(x: $0.x * xScale, y: $0.y) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let inkHeight = max(maxY - minY, (maxX - minX) * 0.25, 1e-3)
        let scale = Double(height) * 0.6 / inkHeight
        let pad = Double(height) * 0.2
        let width = min(Int((maxX - minX) * scale + 2 * pad), 4096)
        guard width > 0, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceGray(),
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setStrokeColor(gray: 0, alpha: 1)
        ctx.setLineWidth(lineWidth * Double(height))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        func map(_ p: Point2D) -> CGPoint {
            CGPoint(x: (p.x * xScale - minX) * scale + pad, y: (p.y - minY) * scale + pad)
        }
        for stroke in strokes where !stroke.isEmpty {
            ctx.beginPath()
            ctx.move(to: map(stroke[0]))
            if stroke.count == 1 {
                ctx.addLine(to: map(stroke[0]).applying(CGAffineTransform(translationX: 0.5, y: 0)))
            }
            for p in stroke.dropFirst() { ctx.addLine(to: map(p)) }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    /// Recognizes a word. Tries a few render sizes and pen widths and keeps the most confident reading.
    public static func recognize(_ strokes: [[Point2D]], xScale: Double = 4.0 / 3.0) -> HandwritingResult? {
        var best: HandwritingResult?
        for pass in passes {
            guard let image = render(strokes, height: pass.height, lineWidth: pass.lineWidth, xScale: xScale),
                  let result = ocr(image) else { continue }
            if best == nil || result.confidence > best!.confidence { best = result }
            if result.confidence >= 0.8 { break }
        }
        return best
    }

    /// Runs Vision text recognition on an image and joins the lines it finds.
    static func ocr(_ image: CGImage) -> HandwritingResult? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let tops = observations.compactMap { $0.topCandidates(3).first }
        guard !tops.isEmpty else { return nil }
        let text = tops.map(\.string).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let confidence = Double(tops.map(\.confidence).min() ?? 0)
        let alternatives = observations.count == 1 ? observations[0].topCandidates(3).dropFirst().map(\.string) : []
        return HandwritingResult(text: text, confidence: confidence, alternatives: alternatives)
    }
}

/// Optionally tidies recognized air-writing with the on-device language model.
public enum AirTextCleaner {
    /// Returns a corrected version of `text`, or `text` itself if the model is unavailable, slow, or changes too much.
    public static func clean(_ text: String, alternatives: [String] = [], timeout: Double = 1.5) async -> String {
        guard case .available = SystemLanguageModel.default.availability else { return text }
        let prompt = """
        Handwriting recognition read: "\(text)". Other readings: \(alternatives.joined(separator: ", ")).
        Reply with only the most likely intended English word or words, fixing obvious misreadings. \
        If it already looks right, reply with it unchanged.
        """
        let cleaned = await withTimeout(seconds: timeout) { () async -> String? in
            let session = LanguageModelSession(instructions: "You correct handwriting-recognition output. Reply with plain text only.")
            return try? await session.respond(to: prompt).content
        }
        guard var cleaned else { return text }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
        guard !cleaned.isEmpty, !cleaned.contains("\n"), cleaned.count <= text.count * 2 + 3 else { return text }
        return cleaned
    }
}
