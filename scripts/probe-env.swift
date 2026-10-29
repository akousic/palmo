import Foundation
import FoundationModels
import Vision
import AVFoundation
let m = SystemLanguageModel.default
print("FoundationModels availability:", m.availability)
print("isAvailable:", m.isAvailable)
let r = VNDetectHumanHandPoseRequest()
print("Vision hand pose revisions:", VNDetectHumanHandPoseRequest.supportedRevisions.map{$0}, "maxHands:", r.maximumHandCount)
print("Camera auth:", AVCaptureDevice.authorizationStatus(for: .video).rawValue)
let ds = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
print("Cameras:", ds.devices.map{$0.localizedName})
print("LowPower:", ProcessInfo.processInfo.isLowPowerModeEnabled)
