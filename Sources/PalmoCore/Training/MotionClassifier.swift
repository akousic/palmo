import CoreML
import Foundation

/// Optional Core ML motion classifier trained with Create ML's Hand Action Classifier template.
///
/// Drop a compiled `PalmoMotion.mlmodelc` (or an uncompiled `.mlmodel`) into
/// `~/Library/Application Support/Palmo/Models/`. Predictions with confidence ≥ 0.85 for a label that
/// matches a `Gesture` raw value are fed to the recognizer; everything else is ignored.
public actor MotionClassifier {
    /// Errors raised while loading a model.
    public enum LoadError: LocalizedError, Sendable {
        /// The model has no multi-array input of the expected rank.
        case unsupportedInput
        /// Human-readable description.
        public var errorDescription: String? { "The model's input is not a [frames, 3, 21] keypoint array." }
    }

    private let model: MLModel
    private let inputName: String
    private let shape: [NSNumber]
    private let labelName: String
    private let probabilityName: String?

    /// Number of frames the model expects per prediction.
    public let windowSize: Int

    private init(model: MLModel) throws {
        let description = model.modelDescription
        guard let input = description.inputDescriptionsByName.values.first(where: { $0.type == .multiArray }),
              let constraint = input.multiArrayConstraint,
              constraint.shape.count == 3,
              constraint.shape[1].intValue == 3,
              constraint.shape[2].intValue == 21 else {
            throw LoadError.unsupportedInput
        }
        self.model = model
        inputName = input.name
        shape = constraint.shape
        windowSize = constraint.shape[0].intValue
        labelName = description.predictedFeatureName ?? "label"
        probabilityName = description.predictedProbabilitiesName
    }

    /// Default model directory: `~/Library/Application Support/Palmo/Models`.
    public static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Palmo/Models", directoryHint: .isDirectory)
    }

    /// Loads `PalmoMotion.mlmodelc` or `PalmoMotion.mlmodel` from `directory`, or returns `nil` if neither exists.
    public static func loadInstalled(from directory: URL = modelsDirectory) async throws -> MotionClassifier? {
        let compiled = directory.appending(path: "PalmoMotion.mlmodelc")
        let source = directory.appending(path: "PalmoMotion.mlmodel")
        let fm = FileManager.default
        let url: URL
        if fm.fileExists(atPath: compiled.path) {
            url = compiled
        } else if fm.fileExists(atPath: source.path) {
            url = try await MLModel.compileModel(at: source)
        } else {
            return nil
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: url, configuration: configuration)
        return try MotionClassifier(model: model)
    }

    /// Classifies the most recent `windowSize` poses (oldest first).
    ///
    /// Poses are un-mirrored back to camera coordinates because Create ML extracts keypoints from
    /// unmirrored video. Returns `nil` when there are too few poses or the label is not a gesture.
    public func predict(_ poses: [HandPose]) throws -> MotionPrediction? {
        guard poses.count >= windowSize else { return nil }
        let window = poses.suffix(windowSize)
        let array = try MLMultiArray(shape: shape, dataType: .float32)
        for (f, pose) in window.enumerated() {
            for j in 0..<21 {
                let landmark = pose.landmarks[j]
                array[[f, 0, j] as [NSNumber]] = NSNumber(value: Float(1 - landmark.location.x))
                array[[f, 1, j] as [NSNumber]] = NSNumber(value: Float(landmark.location.y))
                array[[f, 2, j] as [NSNumber]] = NSNumber(value: Float(landmark.confidence))
            }
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: array)])
        let output = try model.prediction(from: provider)
        guard let label = output.featureValue(for: labelName)?.stringValue,
              let gesture = Gesture(rawValue: label) else { return nil }
        let confidence = probabilityName
            .flatMap { output.featureValue(for: $0)?.dictionaryValue[label]?.doubleValue } ?? 0
        return MotionPrediction(gesture: gesture, confidence: confidence)
    }
}
