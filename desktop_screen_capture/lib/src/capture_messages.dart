class CaptureMessages {
  final String nativeRegionSelectionUnavailable;
  final String useFlutterOverlayFallback;
  final String targetTooSmall;
  final String selectLargerArea;
  final String invalidCaptureGeometry;
  final String selectValidCaptureArea;
  final String regionOutsideTargetDisplay;
  final String selectAreaInsideSingleDisplay;
  final String selectedAreaCropFailed;
  final String selectAreaInsideVisibleScreen;
  final String screenCaptureFailed;
  final String checkRecordingPermission;
  final String capturedImageReadFailed;
  final String tryCaptureAgain;
  final String displayTargetRequired;
  final String selectDisplayTarget;
  final String windowTargetRequired;
  final String selectWindowTarget;
  final String validWindowIdRequired;
  final String refreshWindowList;
  final String windowCaptureFailed;
  final String windowStillVisible;
  final String displayEnumerationUnsupported;
  final String useDefaultDisplayInstead;
  final String windowEnumerationUnsupported;
  final String useRegionCaptureInstead;
  final String captureFileMissing;
  final String selectedDisplayUnresolved;
  final String refreshDisplayTargets;
  final String encodedImageEmpty;
  final String nativePayloadParseFailed;
  final String checkPlatformChannelContract;
  final String nativeOperationFailed;
  final String nativeBridgeNotRegistered;
  final String useSupportedDesktopBuild;
  final String inspectPlatformChannelHandler;
  final String nativeBridgeInvocationFailed;

  const CaptureMessages({
    this.nativeRegionSelectionUnavailable =
        'Native region selection is unavailable.',
    this.useFlutterOverlayFallback = 'Use the Flutter overlay fallback.',
    this.targetTooSmall = 'The selected area is too small.',
    this.selectLargerArea = 'Select a larger area and try again.',
    this.invalidCaptureGeometry = 'The capture geometry is invalid.',
    this.selectValidCaptureArea = 'Select a valid capture area and try again.',
    this.regionOutsideTargetDisplay =
        'The selected region is outside the target display.',
    this.selectAreaInsideSingleDisplay =
        'Select an area inside a single display.',
    this.selectedAreaCropFailed = 'The selected area could not be cropped.',
    this.selectAreaInsideVisibleScreen =
        'Select an area inside the visible screen.',
    this.screenCaptureFailed = 'Screen capture failed.',
    this.checkRecordingPermission =
        'Check screen recording permission and try again.',
    this.capturedImageReadFailed = 'The captured image could not be read.',
    this.tryCaptureAgain = 'Try the capture again.',
    this.displayTargetRequired = 'A display target is required.',
    this.selectDisplayTarget = 'Select a display target.',
    this.windowTargetRequired = 'A window target is required.',
    this.selectWindowTarget = 'Select a window target.',
    this.validWindowIdRequired = 'A valid window id is required.',
    this.refreshWindowList = 'Refresh the window list and try again.',
    this.windowCaptureFailed = 'Window capture failed.',
    this.windowStillVisible =
        'Make sure the window is still visible and try again.',
    this.displayEnumerationUnsupported = 'Display enumeration is unsupported.',
    this.useDefaultDisplayInstead = 'Use the default display instead.',
    this.windowEnumerationUnsupported = 'Window enumeration is unsupported.',
    this.useRegionCaptureInstead = 'Use region capture instead.',
    this.captureFileMissing = 'The capture file is missing.',
    this.selectedDisplayUnresolved =
        'The selected display could not be resolved.',
    this.refreshDisplayTargets = 'Refresh display targets and try again.',
    this.encodedImageEmpty = 'The encoded image is empty.',
    this.nativePayloadParseFailed = 'The native payload could not be parsed.',
    this.checkPlatformChannelContract =
        'Check the platform channel contract.',
    this.nativeOperationFailed = 'The native operation failed.',
    this.nativeBridgeNotRegistered = 'The native bridge is not registered.',
    this.useSupportedDesktopBuild = 'Use a supported desktop build.',
    this.inspectPlatformChannelHandler =
        'Inspect the platform channel handler.',
    this.nativeBridgeInvocationFailed =
        'The native bridge invocation failed.',
  });
}
