@preconcurrency import AVFoundation
import Foundation

/// One processed camera frame: the detected hand (if any) and face rectangle (if recently seen).
public struct HandFrame: Sendable {
    /// The detected hand, mirrored into user perspective.
    public var pose: HandPose?
    /// The most recent face rectangle.
    public var face: Rect2D?
    /// Media timestamp in seconds.
    public var timestamp: TimeInterval

    /// Creates a frame.
    public init(pose: HandPose?, face: Rect2D?, timestamp: TimeInterval) {
        self.pose = pose
        self.face = face
        self.timestamp = timestamp
    }
}

/// Errors raised while configuring the camera.
public enum CameraError: LocalizedError, Sendable {
    /// No video device found.
    case noCamera
    /// The device could not be added to the session.
    case cannotAddInput
    /// The video output could not be added.
    case cannotAddOutput

    /// Human-readable description.
    public var errorDescription: String? {
        switch self {
        case .noCamera: "No camera was found."
        case .cannotAddInput: "The camera could not be opened. Another app may be using it."
        case .cannotAddOutput: "The camera output could not be configured."
        }
    }
}

/// AVFoundation capture + Vision tracking, delivered as an ordered `AsyncStream` of `HandFrame`s.
///
/// Thread-safety: every mutable property is touched only on the private serial `queue` (the sample
/// buffer delegate queue), which is why the type is `@unchecked Sendable`. Frames never leave the queue;
/// only `Sendable` `HandFrame` values do.
public final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Ordered stream of processed frames. Only the newest two are buffered, so a slow consumer drops frames.
    public let frames: AsyncStream<HandFrame>

    private let continuation: AsyncStream<HandFrame>.Continuation
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "app.palmo.capture", qos: .userInteractive)
    private let tracker = HandTracker()
    private var configured = false
    private var minInterval: TimeInterval = 1.0 / 30
    private var lastProcessed: TimeInterval = -.infinity
    private var clipWriter: ClipWriter?
    private var clipRequest: (url: URL, completion: @Sendable (URL?) -> Void)?

    /// Creates an idle capture pipeline.
    public override init() {
        var c: AsyncStream<HandFrame>.Continuation!
        frames = AsyncStream(bufferingPolicy: .bufferingNewest(2)) { c = $0 }
        continuation = c
        super.init()
    }

    /// Names of available cameras, built-in first.
    public static var availableCameras: [String] { discovery().devices.map(\.localizedName) }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                         mediaType: .video, position: .unspecified)
    }

    /// Starts capturing. Requires camera authorization; throws if no camera can be opened.
    public func start() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configureIfNeeded()
                    if !self.session.isRunning { self.session.startRunning() }
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    /// Stops capturing (the camera indicator light turns off).
    public func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Limits Vision processing to at most `fps` frames per second (energy throttle).
    public func setTargetFrameRate(_ fps: Double) {
        queue.async { self.minInterval = 1.0 / max(1, min(fps, 30)) }
    }

    /// Records the next `duration` seconds of raw video to `url` (training data collection).
    public func recordClip(to url: URL, duration: TimeInterval, completion: @escaping @Sendable (URL?) -> Void) {
        queue.async {
            self.clipRequest = (url, completion)
            self.queue.asyncAfter(deadline: .now() + duration) { self.finishClip() }
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        let devices = Self.discovery().devices
        guard let device = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first else {
            throw CameraError.noCamera
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        configured = true
    }

    /// Delegate callback, always on `queue`.
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let request = clipRequest {
            if clipWriter == nil { clipWriter = ClipWriter(url: request.url) }
            clipWriter?.append(sampleBuffer)
        }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp - lastProcessed >= minInterval * 0.9,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastProcessed = timestamp
        let result = tracker.process(pixelBuffer, timestamp: timestamp)
        continuation.yield(HandFrame(pose: result.pose, face: result.face, timestamp: timestamp))
    }

    private func finishClip() {
        guard let request = clipRequest else { return }
        clipRequest = nil
        let writer = clipWriter
        clipWriter = nil
        guard let writer else {
            request.completion(nil)
            return
        }
        writer.finish { ok in request.completion(ok ? request.url : nil) }
    }
}

/// Writes camera sample buffers to a QuickTime movie. Used only on the capture queue.
final class ClipWriter {
    private let writer: AVAssetWriter?
    private let input: AVAssetWriterInput
    private var started = false

    init(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        writer = try? AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 480,
        ])
        input.expectsMediaDataInRealTime = true
        if let writer, writer.canAdd(input) { writer.add(input) }
    }

    func append(_ buffer: CMSampleBuffer) {
        guard let writer else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }

    func finish(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard let writer, started else {
            completion(false)
            return
        }
        input.markAsFinished()
        // The writer is only read for its final status inside its own completion handler.
        nonisolated(unsafe) let finishing = writer
        writer.finishWriting { completion(finishing.status == .completed) }
    }
}
