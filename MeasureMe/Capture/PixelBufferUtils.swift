import AVFoundation
import CoreImage
import UIKit

enum PixelBufferUtils {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Deep-copies a camera frame into a new BGRA buffer so the capture pool isn't starved
    /// while frames are held for analysis. The copy lives in memory only.
    static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &out) == kCVReturnSuccess, let out else { return nil }
        ciContext.render(CIImage(cvPixelBuffer: source), to: out)
        return out
    }

    /// Mean brightness 0…1 from the luma plane of a 420f buffer (sampled sparsely).
    static func meanLuma(_ pb: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPlaneCount(pb) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, n = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                sum += Int(ptr[y * stride + x])
                n += 1
                x += 16
            }
            y += 16
        }
        return n > 0 ? Double(sum) / Double(n) / 255 : nil
    }

    static func uiImage(_ pb: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func jpegData(_ pb: CVPixelBuffer, quality: CGFloat = 0.8) -> Data? {
        uiImage(pb)?.jpegData(compressionQuality: quality)
    }
}

/// Converts LiDAR depth + camera intrinsics into centimetres per image pixel at the body.
enum DepthScale {
    /// - Parameters:
    ///   - depthData: synchronized depth for the frame.
    ///   - imageSize: size of the portrait video frame.
    /// - Returns: cm per image pixel at the person's body plane, or nil when depth or intrinsics are missing.
    ///
    /// Samples the median depth in a small central window. Live framing checks keep the person centred,
    /// so the window falls on the torso regardless of the depth map's orientation.
    /// https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata/intrinsicmatrix
    static func cmPerImagePixel(depthData: AVDepthData, imageSize: CGSize) -> Double? {
        let depth = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        guard let calibration = depth.cameraCalibrationData else { return nil }
        let map = depth.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var samples: [Float] = []
        let x0 = Int(Double(w) * 0.42), x1 = Int(Double(w) * 0.58)
        let y0 = Int(Double(h) * 0.42), y1 = Int(Double(h) * 0.58)
        guard x1 > x0, y1 > y0 else { return nil }
        for y in y0..<y1 {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in x0..<x1 {
                let v = row[x]
                if v.isFinite, v > 0.3, v < 8 { samples.append(v) }
            }
        }
        guard samples.count > 10 else { return nil }
        samples.sort()
        let medianMetres = Double(samples[samples.count / 2])
        let fx = Double(calibration.intrinsicMatrix.columns.0.x)
        let ref = calibration.intrinsicMatrixReferenceDimensions
        // Intrinsics are in sensor (landscape) pixels; compare long sides to scale them to the portrait frame.
        let refLong = Double(max(ref.width, ref.height))
        let imageLong = Double(max(imageSize.width, imageSize.height))
        guard fx > 0, refLong > 0 else { return nil }
        let focalImagePixels = fx * imageLong / refLong
        // LiDAR measures the front surface; the outline sits roughly at mid-torso, ~8 cm further away.
        let distanceCM = medianMetres * 100 + 8
        return distanceCM / focalImagePixels
    }
}
