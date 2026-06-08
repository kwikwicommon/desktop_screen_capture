import Cocoa
import CoreGraphics

final class MacosRegionSelectionSession {
  private var windows: [NSWindow] = []
  private var didFinish = false
  private let enumerator: MacosDisplayEnumerator
  private let onComplete: ([String: Any]) -> Void
  private let onCancel: () -> Void

  init(
    enumerator: MacosDisplayEnumerator,
    onComplete: @escaping ([String: Any]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.enumerator = enumerator
    self.onComplete = onComplete
    self.onCancel = onCancel
  }

  func start() -> Bool {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return false }

    for screen in screens {
      let view = MacosRegionSelectionView(
        screen: screen,
        onComplete: { [weak self] rect, screen in
          self?.complete(rect: rect, screen: screen)
        },
        onCancel: { [weak self] in
          self?.cancel()
        }
      )
      let window = NSWindow(
        contentRect: screen.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false,
        screen: screen
      )
      window.backgroundColor = .clear
      window.isOpaque = false
      window.hasShadow = false
      window.ignoresMouseEvents = false
      window.acceptsMouseMovedEvents = true
      window.canBecomeVisibleWithoutLogin = true
      window.level = .screenSaver
      window.collectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
      ]
      window.contentView = view
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
      window.makeFirstResponder(view)
      windows.append(window)
    }

    NSApp.activate(ignoringOtherApps: true)
    return true
  }

  private func complete(rect: CGRect, screen: NSScreen) {
    guard !didFinish else { return }
    didFinish = true
    closeWindows()
    onComplete(selectionPayload(rect: rect, screen: screen))
  }

  private func cancel() {
    guard !didFinish else { return }
    didFinish = true
    closeWindows()
    onCancel()
  }

  private func closeWindows() {
    for window in windows {
      window.orderOut(nil)
      window.close()
    }
    windows.removeAll()
  }

  private func selectionPayload(rect: CGRect, screen: NSScreen) -> [String: Any] {
    let displayBounds = enumerator.displayBounds(for: screen)
    return [
      "rect": enumerator.rectPayload(rect),
      "sourceSize": enumerator.sizePayload(displayBounds.size),
      "displayId": Int(enumerator.displayId(for: screen)),
      "displayBoundsLogical": enumerator.rectPayload(displayBounds),
      "virtualScreenBoundsLogical": enumerator.rectPayload(
        enumerator.virtualScreenBounds()
      ),
      "scaleFactor": screen.backingScaleFactor,
      "coordinateSpace": "displayLogical",
    ]
  }
}

private final class MacosRegionSelectionView: NSView {
  private let targetScreen: NSScreen
  private let onComplete: (CGRect, NSScreen) -> Void
  private let onCancel: () -> Void
  private var startPoint: CGPoint?
  private var currentPoint: CGPoint?

  init(
    screen: NSScreen,
    onComplete: @escaping (CGRect, NSScreen) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.targetScreen = screen
    self.onComplete = onComplete
    self.onCancel = onCancel
    super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  required init?(coder: NSCoder) {
    return nil
  }

  override var acceptsFirstResponder: Bool { true }

  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let overlayPath = NSBezierPath(rect: bounds)
    if let rect = selectionRect {
      overlayPath.append(NSBezierPath(rect: rect))
      overlayPath.windingRule = .evenOdd
    }
    NSColor.black.withAlphaComponent(0.38).setFill()
    overlayPath.fill()

    guard let rect = selectionRect else { return }
    NSColor.systemGreen.setStroke()
    let border = NSBezierPath(rect: rect)
    border.lineWidth = 2
    border.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    startPoint = point
    currentPoint = point
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    currentPoint = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    currentPoint = convert(event.locationInWindow, from: nil)
    confirmSelection()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onCancel()
      return
    }
    if event.keyCode == 36 || event.keyCode == 49 {
      confirmSelection()
      return
    }
    super.keyDown(with: event)
  }

  private var selectionRect: CGRect? {
    guard let startPoint, let currentPoint else { return nil }
    let clampedStart = clampedPoint(startPoint)
    let clampedCurrent = clampedPoint(currentPoint)
    let left = min(clampedStart.x, clampedCurrent.x)
    let top = min(clampedStart.y, clampedCurrent.y)
    let right = max(clampedStart.x, clampedCurrent.x)
    let bottom = max(clampedStart.y, clampedCurrent.y)
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  private func clampedPoint(_ point: CGPoint) -> CGPoint {
    return CGPoint(
      x: min(max(point.x, bounds.minX), bounds.maxX),
      y: min(max(point.y, bounds.minY), bounds.maxY)
    )
  }

  private func confirmSelection() {
    guard let rect = selectionRect,
          rect.width >= 5,
          rect.height >= 5 else {
      onCancel()
      return
    }
    onComplete(rect, targetScreen)
  }
}
