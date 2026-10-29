import Foundation

/// File layout for in-app training data collection, matching Create ML's folder-per-label format.
public enum TrainingLibrary {
    /// Root folder: `~/Library/Application Support/Palmo/Training`.
    public static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Palmo/Training", directoryHint: .isDirectory)
    }

    /// Labels offered in the recorder: motion gestures plus a negative "background" class.
    public static let labels: [String] = [
        Gesture.swipeLeft, .swipeRight, .threeFingerUp, .threeFingerDown,
        .thumbFlickLeft, .thumbFlickRight, .peaceFlickLeft, .peaceFlickRight, .palmFlip,
    ].map(\.rawValue) + ["background"]

    /// A new, unique clip URL for `label`.
    public static func newClipURL(label: String, date: Date = Date()) -> URL {
        let stamp = Int(date.timeIntervalSince1970 * 1000)
        return root.appending(path: label, directoryHint: .isDirectory).appending(path: "\(label)-\(stamp).mov")
    }

    /// Number of clips recorded per label.
    public static func clipCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for label in labels {
            let folder = root.appending(path: label, directoryHint: .isDirectory)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            counts[label] = files.filter { $0.hasSuffix(".mov") }.count
        }
        return counts
    }
}
