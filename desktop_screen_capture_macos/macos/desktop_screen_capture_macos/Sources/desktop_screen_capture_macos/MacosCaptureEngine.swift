import Cocoa
import CoreGraphics
import FlutterMacOS
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

final class MacosCaptureEngine {
  private let enumerator: MacosDisplayEnumerator

  init(enumerator: MacosDisplayEnumerator) {
    self.enumerator = enumerator
  }

  func captureDisplay(
    arguments: Any?,
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard hasScreenCapturePermission() else {
      completion(permissionDenied())
      return
    }
    guard #available(macOS 14.0, *) else {
      completion(unsupportedScreenshotCapture())
      return
    }

    Task {
      do {
        let requestedId = resolvedDisplayId(from: arguments)
        guard let display = try await enumerator.screenCaptureDisplay(
          displayId: requestedId
        ) else {
          DispatchQueue.main.async {
            completion(MacosCaptureEnvelope.nativeFailure(
              message: "No display is available to capture.",
              recoverySuggestion: "Connect a display and try again."
            ))
          }
          return
        }

        let scaleFactor = await MainActor.run {
          enumerator.scaleFactor(for: display.displayID)
        }
        let configuration = screenshotConfiguration(
          width: Double(display.width) * scaleFactor,
          height: Double(display.height) * scaleFactor
        )
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(
          contentFilter: filter,
          configuration: configuration
        )
        let payload = imagePayload(
          from: image,
          displayId: Int(display.displayID),
          scaleFactor: scaleFactor
        )
        DispatchQueue.main.async {
          completion(payload ?? MacosCaptureEnvelope.ioFailure(
            message: "The display image could not be encoded as PNG.",
            recoverySuggestion: "Try the capture again."
          ))
        }
      } catch {
        DispatchQueue.main.async {
          completion(MacosCaptureEnvelope.nativeFailure(
            message: "The selected display could not be captured.",
            recoverySuggestion: "Check screen recording permission and try again.",
            details: String(describing: error)
          ))
        }
      }
    }
  }

  func captureWindow(
    arguments: Any?,
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard hasScreenCapturePermission() else {
      completion(permissionDenied())
      return
    }
    guard #available(macOS 14.0, *) else {
      completion(unsupportedScreenshotCapture())
      return
    }
    guard
      let args = arguments as? [String: Any],
      let windowId = intValue(args["windowId"]),
      windowId > 0
    else {
      completion(MacosCaptureEnvelope.failure(
        status: .nativeFailure,
        message: "A valid window id is required for native window capture.",
        recoverySuggestion: "Enumerate windows first and retry the capture.",
        domain: "native",
        recoverability: "retryable"
      ))
      return
    }

    let keepTransparentBackground = args["keepTransparentBackground"] as? Bool ?? true
    let includeShadow = args["includeShadow"] as? Bool ?? true
    let replacementBackgroundColor = intValue(args["replacementBackgroundColor"]) ?? 0xFFFFFFFF

    Task {
      do {
        guard let window = try await enumerator.screenCaptureWindow(windowId: windowId) else {
          DispatchQueue.main.async {
            completion(MacosCaptureEnvelope.nativeFailure(
              message: "The selected window could not be found.",
              recoverySuggestion: "Refresh the window list and try again."
            ))
          }
          return
        }

        let displayInfo = await MainActor.run {
          enumerator.displayInfo(for: window.frame)
        }
        let scale = displayInfo.scaleFactor
        let configuration = screenshotConfiguration(
          width: window.frame.width * scale,
          height: window.frame.height * scale
        )
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.ignoreShadowsSingleWindow = !includeShadow
        let filter = SCContentFilter(desktopIndependentWindow: window)
        var image = try await SCScreenshotManager.captureImage(
          contentFilter: filter,
          configuration: configuration
        )
        if !keepTransparentBackground,
           let flattened = flattenedImage(image, argb: replacementBackgroundColor) {
          image = flattened
        }
        let payload = imagePayload(
          from: image,
          displayId: displayInfo.displayId,
          windowId: windowId,
          scaleFactor: Double(scale)
        )
        DispatchQueue.main.async {
          completion(payload ?? MacosCaptureEnvelope.ioFailure(
            message: "The window image could not be encoded as PNG.",
            recoverySuggestion: "Try the capture again."
          ))
        }
      } catch {
        DispatchQueue.main.async {
          completion(MacosCaptureEnvelope.nativeFailure(
            message: "The selected window could not be captured.",
            recoverySuggestion: "Make sure the window is still visible and try again.",
            details: String(describing: error)
          ))
        }
      }
    }
  }

  func captureRegion(
    arguments: Any?,
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard hasScreenCapturePermission() else {
      completion(permissionDenied())
      return
    }
    guard #available(macOS 14.0, *) else {
      completion(unsupportedScreenshotCapture())
      return
    }
    guard
      let args = arguments as? [String: Any],
      let regionMap = args["region"] as? [String: Any]
    else {
      completion(MacosCaptureEnvelope.failure(
        status: .nativeFailure,
        message: "A physical pixel region is required for native region capture.",
        recoverySuggestion: "Resolve the display scale and retry the capture.",
        domain: "native",
        recoverability: "retryable"
      ))
      return
    }

    guard let regionLeft = numberValue(regionMap["left"]),
          let regionTop = numberValue(regionMap["top"]),
          let regionWidth = numberValue(regionMap["width"]),
          let regionHeight = numberValue(regionMap["height"]) else {
      completion(MacosCaptureEnvelope.failure(
        status: .invalidInput,
        message: "A valid physical pixel region is required for native region capture.",
        recoverySuggestion: "Select a visible area inside the target display and retry.",
        domain: "native",
        recoverability: "retryable"
      ))
      return
    }

    let requestedRect = CGRect(
      x: regionLeft,
      y: regionTop,
      width: regionWidth,
      height: regionHeight
    ).standardized
    guard requestedRect.origin.x.isFinite,
          requestedRect.origin.y.isFinite,
          requestedRect.size.width.isFinite,
          requestedRect.size.height.isFinite,
          requestedRect.size.width >= 1,
          requestedRect.size.height >= 1 else {
      completion(MacosCaptureEnvelope.failure(
        status: .invalidInput,
        message: "A valid physical pixel region is required for native region capture.",
        recoverySuggestion: "Select a visible area inside the target display and retry.",
        domain: "native",
        recoverability: "retryable"
      ))
      return
    }

    Task {
      do {
        let displayId = resolvedDisplayId(from: arguments)
        guard let display = try await enumerator.screenCaptureDisplay(
          displayId: displayId
        ) else {
          DispatchQueue.main.async {
            completion(MacosCaptureEnvelope.nativeFailure(
              message: "The selected display could not be captured.",
              recoverySuggestion: "Check screen recording permission and try again."
            ))
          }
          return
        }

        let scaleFactor = await MainActor.run {
          enumerator.scaleFactor(for: display.displayID)
        }
        let configuration = screenshotConfiguration(
          width: Double(display.width) * scaleFactor,
          height: Double(display.height) * scaleFactor
        )
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(
          contentFilter: filter,
          configuration: configuration
        )
        let cropRect = clampedCropRect(requestedRect, image: image)
        guard cropRect.width >= 1,
              cropRect.height >= 1,
              let cropped = image.cropping(to: cropRect) else {
          DispatchQueue.main.async {
            completion(MacosCaptureEnvelope.ioFailure(
              message: "The selected region could not be cropped.",
              recoverySuggestion: "Select a visible area inside the target display and try again."
            ))
          }
          return
        }

        let payload = imagePayload(
          from: cropped,
          displayId: Int(display.displayID),
          scaleFactor: scaleFactor
        )
        DispatchQueue.main.async {
          completion(payload ?? MacosCaptureEnvelope.ioFailure(
            message: "The selected region image could not be encoded as PNG.",
            recoverySuggestion: "Try the capture again."
          ))
        }
      } catch {
        DispatchQueue.main.async {
          completion(MacosCaptureEnvelope.nativeFailure(
            message: "The selected region could not be captured.",
            recoverySuggestion: "Check screen recording permission and try again.",
            details: String(describing: error)
          ))
        }
      }
    }
  }

  func encodeImage(arguments: Any?) -> [String: Any] {
    guard
      let args = arguments as? [String: Any],
      let typedData = args["imageBytes"] as? FlutterStandardTypedData
    else {
      return MacosCaptureEnvelope.nativeFailure(
        message: "Image bytes are required for image encoding.",
        recoverySuggestion: "Capture an image and try again."
      )
    }

    let format = (args["format"] as? String ?? "png").lowercased()
    let quality = max(1, min(intValue(args["quality"]) ?? 90, 100))
    let matteColor = intValue(args["matteColor"]) ?? 0xFFFFFFFF
    guard let source = CGImageSourceCreateWithData(typedData.data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return MacosCaptureEnvelope.ioFailure(
        message: "The capture image could not be decoded for encoding.",
        recoverySuggestion: "Try the capture again."
      )
    }

    switch format {
    case "png":
      let bitmap = NSBitmapImageRep(cgImage: image)
      guard let data = bitmap.representation(using: .png, properties: [:]) else {
        return MacosCaptureEnvelope.ioFailure(
          message: "The capture image could not be encoded as PNG.",
          recoverySuggestion: "Try the capture again."
        )
      }
      return encodedImagePayload(
        data: data,
        image: image,
        format: "png",
        fileExtension: "png",
        mimeType: "image/png"
      )
    case "jpeg":
      let outputImage = flattenedImage(image, argb: matteColor) ?? image
      let bitmap = NSBitmapImageRep(cgImage: outputImage)
      let properties: [NSBitmapImageRep.PropertyKey: Any] = [
        .compressionFactor: Double(quality) / 100.0
      ]
      guard let data = bitmap.representation(using: .jpeg, properties: properties) else {
        return MacosCaptureEnvelope.ioFailure(
          message: "The capture image could not be encoded as JPEG.",
          recoverySuggestion: "Try the capture again."
        )
      }
      return encodedImagePayload(
        data: data,
        image: outputImage,
        format: "jpeg",
        fileExtension: "jpeg",
        mimeType: "image/jpeg"
      )
    case "webp":
      if #available(macOS 11.0, *) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
          data,
          UTType.webP.identifier as CFString,
          1,
          nil
        ) else {
          return MacosCaptureEnvelope.failure(
            status: .unsupported,
            message: "WebP encoding is not available on this macOS build.",
            recoverySuggestion: "Use PNG or JPEG output."
          )
        }
        let properties = [
          kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
          return MacosCaptureEnvelope.ioFailure(
            message: "The capture image could not be encoded as WebP.",
            recoverySuggestion: "Use PNG or JPEG output."
          )
        }
        return encodedImagePayload(
          data: data as Data,
          image: image,
          format: "webp",
          fileExtension: "webp",
          mimeType: "image/webp"
        )
      }
      return MacosCaptureEnvelope.failure(
        status: .unsupported,
        message: "WebP encoding requires macOS 11 or later.",
        recoverySuggestion: "Use PNG or JPEG output."
      )
    default:
      return MacosCaptureEnvelope.failure(
        status: .invalidInput,
        message: "The requested image format is not supported.",
        recoverySuggestion: "Choose PNG, JPEG, or WebP."
      )
    }
  }

  private func encodedImagePayload(
    data: Data,
    image: CGImage,
    format: String,
    fileExtension: String,
    mimeType: String
  ) -> [String: Any] {
    return MacosCaptureEnvelope.success(payload: [
      "imageBytes": FlutterStandardTypedData(bytes: data),
      "width": image.width,
      "height": image.height,
      "format": format,
      "extension": fileExtension,
      "mimeType": mimeType,
    ])
  }

  private func imagePayload(
    from image: CGImage,
    displayId: Int? = nil,
    windowId: Int? = nil,
    scaleFactor: Double
  ) -> [String: Any]? {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
      return nil
    }

    var payload: [String: Any] = [
      "imageBytes": FlutterStandardTypedData(bytes: pngData),
      "width": image.width,
      "height": image.height,
      "scaleFactor": scaleFactor,
      "isTemporary": false,
    ]
    if let displayId {
      payload["displayId"] = displayId
    }
    if let windowId {
      payload["windowId"] = windowId
    }
    return MacosCaptureEnvelope.success(payload: payload)
  }

  private func screenshotConfiguration(
    width: Double,
    height: Double
  ) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.width = clampedPixelDimension(width)
    configuration.height = clampedPixelDimension(height)
    configuration.showsCursor = false
    return configuration
  }

  private func clampedPixelDimension(_ value: Double) -> Int {
    guard value.isFinite, value > 0 else {
      return 1
    }
    return max(1, Int(value.rounded(.up)))
  }

  private func clampedCropRect(_ rect: CGRect, image: CGImage) -> CGRect {
    let imageBounds = CGRect(
      x: 0,
      y: 0,
      width: CGFloat(image.width),
      height: CGFloat(image.height)
    )
    let sanitized = CGRect(
      x: max(0, rect.origin.x.rounded(.down)),
      y: max(0, rect.origin.y.rounded(.down)),
      width: max(0, rect.size.width.rounded(.up)),
      height: max(0, rect.size.height.rounded(.up))
    )
    let intersection = sanitized.intersection(imageBounds)
    if intersection.isNull {
      return .zero
    }
    return intersection.integral
  }

  private func flattenedImage(_ image: CGImage, argb: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
      data: nil,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else {
      return nil
    }

    let rect = CGRect(
      x: 0,
      y: 0,
      width: CGFloat(image.width),
      height: CGFloat(image.height)
    )
    context.setFillColor(cgColor(fromARGB: argb))
    context.fill(rect)
    context.draw(image, in: rect)
    return context.makeImage()
  }

  private func cgColor(fromARGB argb: Int) -> CGColor {
    let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
    let red = CGFloat((argb >> 16) & 0xFF) / 255.0
    let green = CGFloat((argb >> 8) & 0xFF) / 255.0
    let blue = CGFloat(argb & 0xFF) / 255.0
    return CGColor(red: red, green: green, blue: blue, alpha: alpha)
  }

  private func resolvedDisplayId(from arguments: Any?) -> CGDirectDisplayID? {
    if let args = arguments as? [String: Any],
       let displayId = intValue(args["displayId"]),
       displayId > 0 {
      return CGDirectDisplayID(displayId)
    }
    return CGMainDisplayID()
  }

  private func numberValue(_ raw: Any?) -> CGFloat? {
    if raw is Bool { return nil }
    if let value = raw as? CGFloat, value.isFinite { return value }
    if let value = raw as? Double, value.isFinite { return CGFloat(value) }
    if let value = raw as? Int { return CGFloat(value) }
    if let value = raw as? NSNumber {
      let value = CGFloat(truncating: value)
      return value.isFinite ? value : nil
    }
    return nil
  }

  private func intValue(_ raw: Any?) -> Int? {
    if raw is Bool { return nil }
    if let value = raw as? Int { return value }
    if let value = raw as? NSNumber {
      guard value.doubleValue.isFinite else { return nil }
      return value.intValue
    }
    if let value = raw as? Double, value.isFinite { return Int(value) }
    return nil
  }

  private func hasScreenCapturePermission() -> Bool {
    if #available(macOS 10.15, *) {
      return CGPreflightScreenCaptureAccess()
    }
    return true
  }

  private func permissionDenied() -> [String: Any] {
    return MacosCaptureEnvelope.failure(
      status: .permissionDenied,
      message: "Screen recording permission is required.",
      recoverySuggestion: "Grant Screen Recording access in System Settings and try again.",
      permissionType: "screenRecording",
      domain: "permission",
      recoverability: "userActionRequired"
    )
  }

  private func unsupportedScreenshotCapture() -> [String: Any] {
    return MacosCaptureEnvelope.failure(
      status: .unsupported,
      message: "Native screenshot capture requires macOS 14 or later.",
      recoverySuggestion: "Use a supported macOS version."
    )
  }
}
