import Flutter
import UIKit
import AVFoundation
import SDWebImage
import SDWebImageWebPCoder

public class SwiftVideoThumbnailPlugin: NSObject, FlutterPlugin {

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keep the original channel name for compatibility with the existing Dart API.
    let channel = FlutterMethodChannel(
      name: "plugins.justsoft.xyz/video_thumbnail",
      binaryMessenger: registrar.messenger()
    )
    let instance = SwiftVideoThumbnailPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Ensure the WebP coder is registered once.
    let webpCoder = SDImageWebPCoder.shared
    if !SDImageCodersManager.shared.coders.contains(where: { $0 === webpCoder }) {
      SDImageCodersManager.shared.addCoder(webpCoder)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS",
                          message: "Arguments are not a dictionary",
                          details: nil))
      return
    }

    guard let file = args["video"] as? String, !file.isEmpty else {
      result(FlutterError(code: "MISSING_VIDEO",
                          message: "Argument 'video' is required",
                          details: nil))
      return
    }

    let headers = args["headers"] as? [String: String]
    var path = args["path"]
    let format = (args["format"] as? NSNumber)?.intValue ?? 0
    let maxh = (args["maxh"] as? NSNumber)?.intValue ?? 0
    let maxw = (args["maxw"] as? NSNumber)?.intValue ?? 0
    let timeMs = (args["timeMs"] as? NSNumber)?.intValue ?? 0
    let quality = (args["quality"] as? NSNumber)?.intValue ?? 75

    let isLocalFile = file.hasPrefix("file://") || file.hasPrefix("/")

    let url: URL?
    if file.hasPrefix("file://") {
      url = URL(fileURLWithPath: String(file.dropFirst("file://".count)))
    } else if file.hasPrefix("/") {
      url = URL(fileURLWithPath: file)
    } else {
      url = URL(string: file)
    }

    guard let videoURL = url else {
      result(FlutterError(code: "INVALID_URL",
                          message: "Could not parse video URL",
                          details: file))
      return
    }

    switch call.method {
    case "data":
      DispatchQueue.global(qos: .userInitiated).async {
        let data = self.generateThumbnail(
          url: videoURL,
          headers: headers,
          format: format,
          maxHeight: maxh,
          maxWidth: maxw,
          timeMs: timeMs,
          quality: quality
        )

        guard let thumbnailData = data else {
          result(FlutterError(code: "THUMBNAIL_ERROR",
                              message: "Failed to generate thumbnail",
                              details: nil))
          return
        }

        result(FlutterStandardTypedData(bytes: thumbnailData))
      }

    case "file":
      if (path is NSNull) && !isLocalFile {
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last {
          path = caches.path
        }
      }

      DispatchQueue.global(qos: .userInitiated).async {
        guard let data = self.generateThumbnail(
          url: videoURL,
          headers: headers,
          format: format,
          maxHeight: maxh,
          maxWidth: maxw,
          timeMs: timeMs,
          quality: quality
        ) else {
          result(FlutterError(code: "THUMBNAIL_ERROR",
                              message: "Failed to generate thumbnail",
                              details: nil))
          return
        }

        let ext: String
        switch format {
        case 0: ext = "jpg"
        case 1: ext = "png"
        default: ext = "webp"
        }

        var thumbnailURL = videoURL.deletingPathExtension().appendingPathExtension(ext)

        if let pathStr = path as? String, !pathStr.isEmpty {
          let base = URL(fileURLWithPath: pathStr)
          let lastPart = thumbnailURL.lastPathComponent
          if base.pathExtension == ext {
            thumbnailURL = base
          } else {
            thumbnailURL = base.appendingPathComponent(lastPart)
          }
        }

        do {
          try data.write(to: thumbnailURL, options: [])
        } catch {
          result(FlutterError(code: "IO_ERROR",
                              message: "Failed to write data to file",
                              details: error.localizedDescription))
          return
        }

        var fullPath = thumbnailURL.absoluteString
        if fullPath.hasPrefix("file://") {
          fullPath = String(fullPath.dropFirst("file://".count))
        }
        result(fullPath)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func generateThumbnail(
    url: URL,
    headers: [String: String]?,
    format: Int,
    maxHeight: Int,
    maxWidth: Int,
    timeMs: Int,
    quality: Int
  ) -> Data? {
    var options: [String: Any]? = nil
    if let headers = headers {
      options = ["AVURLAssetHTTPHeaderFieldsKey": headers]
    }

    let asset = AVURLAsset(url: url, options: options)
    let imageGenerator = AVAssetImageGenerator(asset: asset)

    imageGenerator.appliesPreferredTrackTransform = true
    if maxWidth > 0 && maxHeight > 0 {
      imageGenerator.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxHeight))
    }
    imageGenerator.requestedTimeToleranceBefore = .zero
    imageGenerator.requestedTimeToleranceAfter = CMTime(value: 100, timescale: 1000)

    let requestedTime = CMTime(value: CMTimeValue(timeMs), timescale: 1000)

    let cgImage: CGImage
    do {
      cgImage = try imageGenerator.copyCGImage(at: requestedTime, actualTime: nil)
    } catch {
      NSLog("VideoThumbnail: couldn't generate thumbnail, error: %@", error.localizedDescription)
      return nil
    }

    let image = UIImage(cgImage: cgImage)

    // JPEG
    if format == 0 {
      let q = max(0.0, min(1.0, Double(quality) * 0.01))
      return image.jpegData(compressionQuality: q)
    }

    // PNG
    if format == 1 {
      return image.pngData()
    }

    // WebP using SDWebImageWebPCoder
    let webpCoder = SDImageWebPCoder.shared
    let q = max(0.0, min(1.0, Double(quality) * 0.01))
    let options: [SDImageCoderOption: Any] = [
      .encodeCompressionQuality: q
    ]

    return webpCoder.encodedData(with: image, format: .webP, options: options)
  }
}

