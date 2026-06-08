import Cocoa
import CoreGraphics
import FlutterMacOS

public class MacosCapturePlugin: NSObject, FlutterPlugin {
  private let enumerator = MacosDisplayEnumerator()
  private lazy var engine = MacosCaptureEngine(enumerator: enumerator)
  private var regionSelectionSession: MacosRegionSelectionSession?
  private var screenRecordingRequiresRestart = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "desktop_screen_capture/native",
      binaryMessenger: registrar.messenger
    )
    let instance = MacosCapturePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "capture.listDisplays":
      result(MacosCaptureEnvelope.success(payload: enumerator.displayPayloads()))
    case "capture.listWindows":
      result(MacosCaptureEnvelope.success(payload: enumerator.windowPayloads()))
    case "capture.captureDisplay":
      engine.captureDisplay(arguments: call.arguments) { payload in
        result(payload)
      }
    case "capture.captureWindow":
      engine.captureWindow(arguments: call.arguments) { payload in
        result(payload)
      }
    case "capture.captureRegion":
      engine.captureRegion(arguments: call.arguments) { payload in
        result(payload)
      }
    case "capture.selectRegion":
      selectRegion(result: result)
    case "capture.encodeImage":
      result(engine.encodeImage(arguments: call.arguments))
    case "capability.queryPermissions":
      result(MacosCaptureEnvelope.success(payload: capabilitySnapshot()))
    case "capability.requestPermission":
      requestPermission(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func selectRegion(result: @escaping FlutterResult) {
    if regionSelectionSession != nil {
      result(MacosCaptureEnvelope.nativeFailure(
        message: "A region selection session is already active.",
        recoverySuggestion: "Finish or cancel the active selection first."
      ))
      return
    }

    let session = MacosRegionSelectionSession(
      enumerator: enumerator,
      onComplete: { [weak self] payload in
        guard let self else { return }
        self.regionSelectionSession = nil
        result(MacosCaptureEnvelope.success(payload: payload))
      },
      onCancel: { [weak self] in
        guard let self else { return }
        self.regionSelectionSession = nil
        result(MacosCaptureEnvelope.failure(
          status: .cancelled,
          message: "Region selection was cancelled.",
          recoverySuggestion: "Start a new capture when ready.",
          domain: "user",
          recoverability: "notRecoverable"
        ))
      }
    )

    if !session.start() {
      result(MacosCaptureEnvelope.nativeFailure(
        message: "No display is available for region selection.",
        recoverySuggestion: "Connect a display and try again."
      ))
      return
    }
    regionSelectionSession = session
  }

  private func capabilitySnapshot() -> [String: Any] {
    return [
      "permissions": [
        permissionPayload(
          forcedGranted: nil,
          requiresRestartOverride: nil
        )
      ],
      "features": featurePayloads(),
    ]
  }

  private func featurePayloads() -> [[String: Any]] {
    let screenPermission = permissionState()
    let supportsScreenshotCapture = ProcessInfo.processInfo.isOperatingSystemAtLeast(
      OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    )
    return [
      featurePayload(name: "displayEnumeration", supported: true, message: ""),
      featurePayload(name: "windowEnumeration", supported: true, message: ""),
      featurePayload(
        name: "captureDisplay",
        supported: supportsScreenshotCapture,
        permissionState: screenPermission,
        message: supportsScreenshotCapture
          ? "Display capture requires screen recording permission."
          : "Display capture requires macOS 14 or later."
      ),
      featurePayload(
        name: "captureWindow",
        supported: supportsScreenshotCapture,
        permissionState: screenPermission,
        message: supportsScreenshotCapture
          ? "Window capture requires screen recording permission."
          : "Window capture requires macOS 14 or later."
      ),
      featurePayload(
        name: "captureRegion",
        supported: supportsScreenshotCapture,
        permissionState: screenPermission,
        message: supportsScreenshotCapture
          ? "Region capture requires screen recording permission."
          : "Region capture requires macOS 14 or later."
      ),
      featurePayload(name: "imageEncoding", supported: true, message: ""),
      featurePayload(name: "nativeRegionSelection", supported: true, message: ""),
    ]
  }

  private func featurePayload(
    name: String,
    supported: Bool,
    permissionState: PermissionStateDescriptor? = nil,
    message: String
  ) -> [String: Any] {
    if !supported {
      return [
        "feature": name,
        "status": "unsupported",
        "message": message,
      ]
    }

    if let permissionState,
       permissionState.state != "granted" {
      return [
        "feature": name,
        "status": "permissionRequired",
        "message": message,
        "permissionType": "screenRecording",
      ]
    }

    return [
      "feature": name,
      "status": "available",
      "message": message,
    ]
  }

  private func requestPermission(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard
      let args = arguments as? [String: Any],
      let type = args["type"] as? String
    else {
      result(MacosCaptureEnvelope.nativeFailure(
        message: "A permission type is required.",
        recoverySuggestion: "Specify the permission type before requesting access."
      ))
      return
    }

    guard type == "screenRecording" else {
      result(MacosCaptureEnvelope.success(payload: [
        "type": type,
        "state": "unsupported",
        "message": "This permission is not managed by desktop_screen_capture_macos.",
        "requiresRestart": false,
      ]))
      return
    }

    if #available(macOS 10.15, *) {
      let wasGranted = CGPreflightScreenCaptureAccess()
      let granted = CGRequestScreenCaptureAccess()
      let requiresRestart = granted && !wasGranted
      if requiresRestart {
        screenRecordingRequiresRestart = true
      }
      result(MacosCaptureEnvelope.success(payload: permissionPayload(
        forcedGranted: granted,
        requiresRestartOverride: requiresRestart
      )))
    } else {
      result(MacosCaptureEnvelope.success(payload: permissionPayload(
        forcedGranted: true,
        requiresRestartOverride: false
      )))
    }
  }

  private func permissionPayload(
    forcedGranted: Bool?,
    requiresRestartOverride: Bool?
  ) -> [String: Any] {
    let state = permissionState(
      forcedGranted: forcedGranted,
      requiresRestartOverride: requiresRestartOverride
    )
    return [
      "type": "screenRecording",
      "state": state.state,
      "message": state.message,
      "requiresRestart": state.requiresRestart,
    ]
  }

  private func permissionState(
    forcedGranted: Bool? = nil,
    requiresRestartOverride: Bool? = nil
  ) -> PermissionStateDescriptor {
    if let forcedGranted {
      if forcedGranted &&
        (requiresRestartOverride == true || screenRecordingRequiresRestart) {
        return PermissionStateDescriptor(
          state: "requiresRestart",
          message: "Restart the app to finish enabling screen recording.",
          requiresRestart: true
        )
      }
      return forcedGranted
        ? PermissionStateDescriptor(state: "granted")
        : PermissionStateDescriptor(
          state: "denied",
          message: "Screen recording permission is not granted."
        )
    }
    if #available(macOS 10.15, *) {
      if screenRecordingRequiresRestart {
        return PermissionStateDescriptor(
          state: "requiresRestart",
          message: "Restart the app to finish enabling screen recording.",
          requiresRestart: true
        )
      }
      return CGPreflightScreenCaptureAccess()
        ? PermissionStateDescriptor(state: "granted")
        : PermissionStateDescriptor(
          state: "denied",
          message: "Screen recording permission is not granted."
        )
    }
    return PermissionStateDescriptor(state: "granted")
  }
}

enum MacosCaptureNativeStatus: String {
  case success
  case cancelled
  case invalidInput
  case permissionDenied
  case unsupported
  case ioFailure
  case nativeFailure
}

enum MacosCaptureEnvelope {
  static func success(payload: Any? = nil) -> [String: Any] {
    var response: [String: Any] = [
      "status": MacosCaptureNativeStatus.success.rawValue
    ]
    if let payload {
      response["payload"] = payload
    }
    return response
  }

  static func nativeFailure(
    message: String,
    recoverySuggestion: String,
    details: Any? = nil
  ) -> [String: Any] {
    return failure(
      status: .nativeFailure,
      message: message,
      recoverySuggestion: recoverySuggestion,
      details: details,
      domain: "native",
      recoverability: "retryable"
    )
  }

  static func ioFailure(
    message: String,
    recoverySuggestion: String
  ) -> [String: Any] {
    return failure(
      status: .ioFailure,
      message: message,
      recoverySuggestion: recoverySuggestion,
      domain: "io",
      recoverability: "retryable"
    )
  }

  static func failure(
    status: MacosCaptureNativeStatus,
    message: String,
    recoverySuggestion: String,
    permissionType: String? = nil,
    nativeCode: String? = nil,
    details: Any? = nil,
    requiresRestart: Bool = false,
    domain: String? = nil,
    recoverability: String = "unknown",
    artifactPath: String = ""
  ) -> [String: Any] {
    var failure: [String: Any] = [
      "message": message,
      "recoverySuggestion": recoverySuggestion,
      "requiresRestart": requiresRestart,
      "domain": domain ?? status.rawValue,
      "nativeCode": nativeCode ?? "",
      "recoverability": recoverability,
      "artifactPath": artifactPath,
    ]
    if let permissionType {
      failure["permissionType"] = permissionType
    }
    if let details {
      failure["details"] = details
    }

    return [
      "status": status.rawValue,
      "failure": failure,
    ]
  }
}

private struct PermissionStateDescriptor {
  let state: String
  let message: String
  let requiresRestart: Bool

  init(
    state: String,
    message: String = "",
    requiresRestart: Bool = false
  ) {
    self.state = state
    self.message = message
    self.requiresRestart = requiresRestart
  }
}
