import AVFoundation
import ARKit

/// Camera and depth hardware detected at runtime. Nothing is assumed from the device model.
///
/// APIs:
/// - AVCaptureDevice.DiscoverySession — https://developer.apple.com/documentation/avfoundation/avcapturedevice/discoverysession
/// - builtInLiDARDepthCamera (iOS 15.4+) — https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/builtinlidardepthcamera
/// - ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) — https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth
/// - ARBodyTrackingConfiguration.isSupported — https://developer.apple.com/documentation/arkit/arbodytrackingconfiguration
struct CameraCapabilities: Equatable {
    var hasRearWideCamera = false
    var hasFrontCamera = false
    var hasRearUltraWide = false
    var hasLiDARDepthCamera = false
    var hasRearDualDepth = false
    var hasTrueDepthFront = false
    var supportsARSceneDepth = false
    var supportsARBodyTracking = false
    var isSimulator = false

    static func detect() -> CameraCapabilities {
        var c = CameraCapabilities()
        #if targetEnvironment(simulator)
        c.isSimulator = true
        #endif
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInLiDARDepthCamera,
                          .builtInDualCamera, .builtInDualWideCamera, .builtInTrueDepthCamera],
            mediaType: .video, position: .unspecified)
        for d in discovery.devices {
            let type = d.deviceType
            let back = d.position == .back
            if type == .builtInWideAngleCamera && back { c.hasRearWideCamera = true }
            if type == .builtInWideAngleCamera && d.position == .front { c.hasFrontCamera = true }
            if type == .builtInUltraWideCamera && back { c.hasRearUltraWide = true }
            if type == .builtInLiDARDepthCamera && back { c.hasLiDARDepthCamera = true }
            if (type == .builtInDualCamera || type == .builtInDualWideCamera) && back { c.hasRearDualDepth = true }
            if type == .builtInTrueDepthCamera && d.position == .front { c.hasTrueDepthFront = true }
        }
        c.supportsARSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        c.supportsARBodyTracking = ARBodyTrackingConfiguration.isSupported
        return c
    }

    var canCapture: Bool { hasRearWideCamera || hasFrontCamera }

    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let available: Bool
        let usage: String
    }

    /// Human-readable list for the setup and settings screens.
    var rows: [Row] {
        [
            Row(name: "Rear wide camera", available: hasRearWideCamera,
                usage: "Used for capture (recommended). Least distortion for full-body photos."),
            Row(name: "Rear ultra-wide camera", available: hasRearUltraWide,
                usage: "Never used: its strong lens distortion would bend body outlines."),
            Row(name: "Front camera", available: hasFrontCamera,
                usage: "Optional fallback if you can’t use the rear camera. Lower accuracy."),
            Row(name: "LiDAR depth", available: hasLiDARDepthCamera,
                usage: "Used, when on in Settings, to cross-check scale and 3D pose. Not required."),
            Row(name: "Dual-camera depth", available: hasRearDualDepth,
                usage: "Not used: disparity depth is unreliable at full-body distance (2–3 m)."),
            Row(name: "TrueDepth (front)", available: hasTrueDepthFront,
                usage: "Not used: its range is too short for a full-body capture."),
            Row(name: "ARKit body tracking", available: supportsARBodyTracking,
                usage: "Detected but not used in this version; Vision provides pose and outline on-device."),
        ]
    }
}
