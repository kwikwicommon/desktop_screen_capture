import Cocoa
import CoreGraphics
import FlutterMacOS
import ScreenCaptureKit

final class MacosDisplayEnumerator {
  func displayPayloads() -> [[String: Any]] {
    let displayIds = activeDisplayIds()
    guard !displayIds.isEmpty else { return [] }
    let mainDisplayId = CGMainDisplayID()

    return displayIds.enumerated().map { index, displayId in
      let screen = screen(for: displayId)
      let frame = displayBounds(for: displayId)
      let displayName: String
      if #available(macOS 10.15, *), let screen {
        displayName = screen.localizedName
      } else {
        displayName = "Display \(index + 1)"
      }

      return [
        "id": Int(displayId),
        "name": displayName,
        "bounds": rectPayload(frame),
        "scaleFactor": screen?.backingScaleFactor ?? 1,
        "isPrimary": displayId == mainDisplayId,
        "isInternal": CGDisplayIsBuiltin(displayId) != 0,
      ]
    }
  }

  func windowPayloads() -> [[String: Any]] {
    let options: CGWindowListOption = [
      .optionOnScreenOnly,
      .excludeDesktopElements,
    ]
    guard
      let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]]
    else {
      return []
    }

    return windowList.compactMap { windowInfo in
      let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
      guard layer == 0 else { return nil }

      guard
        let windowId = windowInfo[kCGWindowNumber as String] as? Int,
        let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
        let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any]
      else {
        return nil
      }
      let ownerPid = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?
        .int32Value

      let x = bounds["X"] as? CGFloat ?? 0
      let y = bounds["Y"] as? CGFloat ?? 0
      let width = bounds["Width"] as? CGFloat ?? 0
      let height = bounds["Height"] as? CGFloat ?? 0
      let rect = CGRect(x: x, y: y, width: width, height: height)
      guard width > 20, height > 20 else { return nil }

      let windowTitle: String
      if let title = windowInfo[kCGWindowName as String] as? String, !title.isEmpty {
        windowTitle = title
      } else {
        windowTitle = ownerName
      }

      var payload: [String: Any] = [
        "id": windowId,
        "title": windowTitle,
        "appName": ownerName,
        "bounds": rectPayload(rect),
        "isVisible": (windowInfo[kCGWindowAlpha as String] as? Double ?? 1) > 0,
        "isOnScreen": windowInfo[kCGWindowIsOnscreen as String] as? Bool ?? true,
      ]
      if let displayId = displayId(for: rect) {
        payload["displayId"] = displayId
      }
      if let thumbnail = windowThumbnailData(windowId: windowId) {
        payload["thumbnail"] = thumbnail
      }
      if let appIcon = appIconData(pid: ownerPid) {
        payload["appIcon"] = appIcon
      }
      return payload
    }
  }

  @available(macOS 12.3, *)
  func screenCaptureDisplay(
    displayId: CGDirectDisplayID?
  ) async throws -> SCDisplay? {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    if let displayId, displayId > 0 {
      return content.displays.first { $0.displayID == displayId }
    }
    let mainDisplayId = CGMainDisplayID()
    return content.displays.first { $0.displayID == mainDisplayId }
      ?? content.displays.first
  }

  @available(macOS 12.3, *)
  func screenCaptureWindow(windowId: Int) async throws -> SCWindow? {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )
    return content.windows.first { Int($0.windowID) == windowId }
  }

  func scaleFactor(for displayId: CGDirectDisplayID) -> Double {
    for screen in NSScreen.screens {
      if self.displayId(for: screen) == displayId {
        return Double(screen.backingScaleFactor)
      }
    }
    return 1
  }

  func displayInfo(for rect: CGRect) -> (displayId: Int?, scaleFactor: Double) {
    guard let screen = screen(containingMostOf: rect) else {
      return (nil, 1)
    }
    return (Int(displayId(for: screen)), Double(screen.backingScaleFactor))
  }

  func displayId(for screen: NSScreen) -> CGDirectDisplayID {
    let screenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber
    return CGDirectDisplayID(screenNumber?.uint32Value ?? CGMainDisplayID())
  }

  func displayId(for rect: CGRect) -> Int? {
    guard let screen = screen(containingMostOf: rect) else {
      return nil
    }
    return Int(displayId(for: screen))
  }

  func displayBounds(for screen: NSScreen) -> CGRect {
    return quartzBounds(for: screen)
  }

  func displayBounds(for displayId: CGDirectDisplayID) -> CGRect {
    if let screen = screen(for: displayId) {
      return quartzBounds(for: screen)
    }
    return CGDisplayBounds(displayId)
  }

  func virtualScreenBounds() -> CGRect {
    let activeBounds = activeDisplayIds().map { displayBounds(for: $0) }
    let bounds = activeBounds.isEmpty
      ? NSScreen.screens.map { self.displayBounds(for: $0) }
      : activeBounds
    return bounds.reduce(CGRect.null) { partial, next in
      partial.isNull ? next : partial.union(next)
    }
  }

  func rectPayload(_ rect: CGRect) -> [String: Any] {
    return [
      "left": rect.origin.x,
      "top": rect.origin.y,
      "width": rect.size.width,
      "height": rect.size.height,
    ]
  }

  func sizePayload(_ size: CGSize) -> [String: Any] {
    return [
      "width": size.width,
      "height": size.height,
    ]
  }

  private func screen(for displayId: CGDirectDisplayID) -> NSScreen? {
    return NSScreen.screens.first { screen in
      self.displayId(for: screen) == displayId
    }
  }

  private func quartzBounds(for screen: NSScreen) -> CGRect {
    let frame = screen.frame
    let mainFrame = self.screen(for: CGMainDisplayID())?.frame
      ?? NSScreen.main?.frame
      ?? frame
    let top = mainFrame.maxY - frame.maxY
    let left = frame.minX - mainFrame.minX
    return CGRect(
      x: left == 0 ? 0 : left,
      y: top == 0 ? 0 : top,
      width: frame.width,
      height: frame.height
    )
  }

  private func screen(containingMostOf rect: CGRect) -> NSScreen? {
    var bestScreen: NSScreen?
    var bestArea: CGFloat = 0
    for screen in NSScreen.screens {
      let intersection = displayBounds(for: screen).intersection(rect)
      if !intersection.isNull {
        let area = intersection.width * intersection.height
        if area > bestArea {
          bestArea = area
          bestScreen = screen
        }
      }
    }
    if bestScreen != nil {
      return bestScreen
    }

    let center = CGPoint(x: rect.midX, y: rect.midY)
    return NSScreen.screens.first { screen in
      displayBounds(for: screen).contains(center)
    }
  }

  private func windowThumbnailData(windowId: Int) -> FlutterStandardTypedData? {
    guard
      let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowId),
        [.bestResolution, .boundsIgnoreFraming]
      )
    else {
      return nil
    }
    return pngData(from: image, maxPixel: 220)
  }

  private func appIconData(pid: pid_t?) -> FlutterStandardTypedData? {
    guard
      let pid,
      let app = NSRunningApplication(processIdentifier: pid),
      let icon = app.icon
    else {
      return nil
    }
    return pngData(from: icon, maxPixel: 64)
  }

  private func pngData(
    from image: NSImage,
    maxPixel: CGFloat
  ) -> FlutterStandardTypedData? {
    let sourceSize = image.size
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return nil
    }
    let scale = min(
      min(maxPixel / sourceSize.width, maxPixel / sourceSize.height),
      1.0
    )
    let targetSize = NSSize(
      width: max(1.0, sourceSize.width * scale),
      height: max(1.0, sourceSize.height * scale)
    )
    let rendered = NSImage(size: targetSize)
    rendered.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: targetSize),
      from: NSRect(origin: .zero, size: sourceSize),
      operation: .copy,
      fraction: 1
    )
    rendered.unlockFocus()
    guard
      let tiffData = rendered.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      return nil
    }
    return FlutterStandardTypedData(bytes: pngData)
  }

  private func pngData(
    from image: CGImage,
    maxPixel: CGFloat
  ) -> FlutterStandardTypedData? {
    let nsImage = NSImage(
      cgImage: image,
      size: NSSize(width: image.width, height: image.height)
    )
    return pngData(from: nsImage, maxPixel: maxPixel)
  }

  private func activeDisplayIds() -> [CGDirectDisplayID] {
    var displayCount: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
          displayCount > 0 else {
      return []
    }

    var displayIds = Array<CGDirectDisplayID>(
      repeating: 0,
      count: Int(displayCount)
    )
    guard CGGetActiveDisplayList(displayCount, &displayIds, &displayCount)
      == .success else {
      return []
    }
    return Array(displayIds.prefix(Int(displayCount))).filter { $0 != 0 }
  }
}
