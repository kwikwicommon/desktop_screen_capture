import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart' as sc;

import 'app_error.dart';
import 'capture_image_utils.dart';
import 'capture_messages.dart';
import 'capture_region_resolver.dart';
import 'capture_service.dart';
import 'capture_target.dart';
import 'native_service.dart';
import 'window_target_validator.dart';

typedef CaptureDirectoryProvider = Future<Directory> Function();

class CaptureServiceImpl implements CaptureService {
  final DesktopCaptureNativeService nativeService;
  final CaptureMessages messages;
  final CaptureRegionResolver regionResolver;
  final WindowTargetValidator windowValidator;
  final CaptureDirectoryProvider? temporaryDirectoryProvider;
  AppFailure? _lastFailure;
  CaptureFallbackDiagnostic? _lastFallbackDiagnostic;
  int _capturePathSequence = 0;

  CaptureServiceImpl({
    DesktopCaptureNativeService? nativeService,
    DesktopScreenCapturePlatform? platform,
    this.messages = const CaptureMessages(),
    CaptureRegionResolver? regionResolver,
    WindowTargetValidator? windowValidator,
    this.temporaryDirectoryProvider,
  }) : nativeService =
           nativeService ??
           PlatformDesktopCaptureNativeService(
             platform: platform,
             messages: messages,
           ),
       regionResolver =
           regionResolver ?? CaptureRegionResolver(messages: messages),
       windowValidator =
           windowValidator ?? WindowTargetValidator(messages: messages);

  @override
  AppFailure? get lastFailure => _lastFailure;

  @override
  CaptureFallbackDiagnostic? get lastFallbackDiagnostic =>
      _lastFallbackDiagnostic;

  @override
  Future<AppResult<CaptureRegionSelection>> selectNativeRegion() async {
    _clearFailure();
    final selection = await nativeService.selectRegion();
    if (selection.isSuccess) {
      return selection;
    }
    if (selection.requireFailure.code != AppFailureCode.unsupported) {
      _lastFailure = selection.requireFailure;
      return AppResult.failure(selection.requireFailure);
    }
    _lastFailure = selection.requireFailure;
    return AppResult.failure(selection.requireFailure);
  }

  @override
  Future<AppResult<CaptureResult>> captureRegion(
    Rect region, {
    Size? sourceSize,
    int? displayId,
    Rect? displayBoundsLogical,
    Rect? virtualScreenBoundsLogical,
    double? scaleFactor,
    CaptureCoordinateSpace coordinateSpace =
        CaptureCoordinateSpace.displayLogical,
  }) async {
    _clearFailure();
    final normalizedRegion = _normalizedRect(region);
    if (!_isFiniteRect(normalizedRegion) ||
        !_isFiniteSize(sourceSize) ||
        !_isFiniteNullableRect(displayBoundsLogical) ||
        !_isFiniteNullableRect(virtualScreenBoundsLogical) ||
        (scaleFactor != null && (!scaleFactor.isFinite || scaleFactor <= 0))) {
      return _failResult(
        AppFailureCode.invalidInput,
        messages.invalidCaptureGeometry,
        messages.selectValidCaptureArea,
      );
    }
    if (normalizedRegion.width < 1 || normalizedRegion.height < 1) {
      return _failResult(
        AppFailureCode.invalidInput,
        messages.targetTooSmall,
        messages.selectLargerArea,
      );
    }

    final selection = CaptureRegionSelection(
      rect: region,
      sourceSize: sourceSize ?? Size.zero,
      displayId: displayId,
      displayBoundsLogical: displayBoundsLogical,
      virtualScreenBoundsLogical: virtualScreenBoundsLogical,
      scaleFactor: scaleFactor ?? 1,
      coordinateSpace: coordinateSpace,
    );

    final nativeResult = await _captureRegionWithNativeBridge(
      selection: selection,
    );
    if (nativeResult != null) {
      return nativeResult;
    }

    try {
      final imagePath = await _newCapturePath();
      final capturedData = await _captureToFile(
        mode: sc.CaptureMode.screen,
        imagePath: imagePath,
      );

      if (capturedData?.imagePath != null) {
        final file = File(capturedData!.imagePath!);
        if (await file.exists()) {
          final bytes = await _readAndDeleteCaptureFile(file);
          final cropPlan = selection.toFullscreenFallbackCropPlan();
          if (cropPlan == null) {
            return _failResult(
              AppFailureCode.invalidInput,
              messages.regionOutsideTargetDisplay,
              messages.selectAreaInsideSingleDisplay,
            );
          }
          final cropped = await CaptureImageUtils.cropPngBytes(
            imageBytes: bytes,
            selectionRect: cropPlan.selectionRect,
            sourceSize: cropPlan.sourceSize,
          );
          if (cropped == null) {
            return _failResult(
              AppFailureCode.invalidInput,
              messages.selectedAreaCropFailed,
              messages.selectAreaInsideVisibleScreen,
            );
          }
          return AppResult.success(
            CaptureResult(
              imageBytes: cropped.imageBytes,
              size: cropped.size,
              displayId: selection.displayId,
              scaleFactor: selection.scaleFactor,
              target: cropPlan.target,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      return _failResult(
        AppFailureCode.nativeFailure,
        messages.screenCaptureFailed,
        messages.checkRecordingPermission,
        error,
        stackTrace,
      );
    }

    return _failResultIfEmpty(
      AppFailureCode.ioFailure,
      messages.capturedImageReadFailed,
      messages.tryCaptureAgain,
    );
  }

  @override
  Future<AppResult<CaptureResult>> captureFullscreen({
    int displayId = 0,
  }) async {
    return _captureDisplayById(displayId: displayId);
  }

  @override
  Future<AppResult<CaptureResult>> captureDisplay(
    CaptureTargetDescriptor target, {
    FullscreenCaptureOptions options = const FullscreenCaptureOptions(),
  }) async {
    if (target.type != CaptureTargetType.display) {
      return _failResult(
        AppFailureCode.invalidInput,
        messages.displayTargetRequired,
        messages.selectDisplayTarget,
      );
    }
    final displayId =
        options.selectedDisplayId ?? target.nativeId ?? target.displayId ?? 0;
    return _captureDisplayById(displayId: displayId, target: target);
  }

  Future<AppResult<CaptureResult>> _captureDisplayById({
    required int displayId,
    CaptureTargetDescriptor? target,
  }) async {
    _clearFailure();
    final nativeResult = await nativeService.captureDisplay(
      NativeCaptureRequest(displayId: displayId > 0 ? displayId : null),
    );
    if (nativeResult.isSuccess) {
      return AppResult.success(
        _captureResultFromNative(
          nativeResult.requireValue,
          target: target,
          captureMode: CaptureMode.fullscreen,
        ),
      );
    }
    if (nativeResult.requireFailure.code != AppFailureCode.unsupported) {
      _lastFailure = nativeResult.requireFailure;
      return AppResult.failure(nativeResult.requireFailure);
    }
    _recordFallback(
      operation: 'captureDisplay',
      failure: nativeResult.requireFailure,
      fallbackPath: 'screen_capturer',
    );

    try {
      final imagePath = await _newCapturePath();
      final capturedData = await _captureToFile(
        mode: sc.CaptureMode.screen,
        imagePath: imagePath,
      );

      if (capturedData?.imagePath != null) {
        return _readCaptureFile(
          capturedData!.imagePath!,
          fallbackSize: Size(
            capturedData.imageWidth?.toDouble() ?? 0,
            capturedData.imageHeight?.toDouble() ?? 0,
          ),
          displayId: displayId > 0 ? displayId : null,
          target: target,
          captureMode: CaptureMode.fullscreen,
        );
      }
    } catch (error, stackTrace) {
      return _failResult(
        AppFailureCode.nativeFailure,
        messages.screenCaptureFailed,
        messages.checkRecordingPermission,
        error,
        stackTrace,
      );
    }

    return _failResultIfEmpty(
      AppFailureCode.ioFailure,
      messages.capturedImageReadFailed,
      messages.tryCaptureAgain,
    );
  }

  @override
  Future<AppResult<CaptureResult>> captureWindow(
    CaptureTargetDescriptor target, {
    WindowCaptureOptions options = const WindowCaptureOptions(),
  }) async {
    _clearFailure();
    if (target.type != CaptureTargetType.window) {
      return _failResult(
        AppFailureCode.invalidInput,
        messages.windowTargetRequired,
        messages.selectWindowTarget,
      );
    }

    final windowId = target.nativeId ?? 0;
    if (windowId <= 0) {
      return _failResult(
        AppFailureCode.invalidInput,
        messages.validWindowIdRequired,
        messages.refreshWindowList,
      );
    }

    final validatedTarget = await _validatedWindowTarget(target);
    if (validatedTarget.isFailure) {
      _lastFailure = validatedTarget.requireFailure;
      return AppResult.failure(validatedTarget.requireFailure);
    }
    final captureTarget = validatedTarget.requireValue;

    final nativeResult = await nativeService.captureWindow(
      NativeCaptureRequest(
        windowId: windowId,
        expectedWindowBoundsLogical: captureTarget.boundsLogical,
        expectedDisplayId: captureTarget.displayId,
        includeShadow: options.includeShadow,
        keepTransparentBackground: options.keepTransparentBackground,
        replacementBackgroundColor: options.replacementBackgroundColor
            ?.toARGB32(),
      ),
    );
    if (nativeResult.isSuccess) {
      return AppResult.success(
        _captureResultFromNative(
          nativeResult.requireValue,
          target: captureTarget,
          windowOptions: options,
          captureMode: CaptureMode.window,
        ),
      );
    }
    if (nativeResult.requireFailure.code != AppFailureCode.unsupported) {
      _lastFailure = nativeResult.requireFailure;
      return AppResult.failure(nativeResult.requireFailure);
    }
    _recordFallback(
      operation: 'captureWindow',
      failure: nativeResult.requireFailure,
      fallbackPath: 'screen_capturer',
    );

    try {
      final imagePath = await _newCapturePath();
      final capturedData = await _captureToFile(
        mode: sc.CaptureMode.window,
        imagePath: imagePath,
      );

      if (capturedData?.imagePath != null) {
        return _readCaptureFile(
          capturedData!.imagePath!,
          fallbackSize: Size(
            capturedData.imageWidth?.toDouble() ?? 0,
            capturedData.imageHeight?.toDouble() ?? 0,
          ),
          windowId: windowId,
          target: captureTarget,
          windowOptions: options,
          captureMode: CaptureMode.window,
        );
      }
    } catch (error, stackTrace) {
      return _failResult(
        AppFailureCode.nativeFailure,
        messages.windowCaptureFailed,
        messages.windowStillVisible,
        error,
        stackTrace,
      );
    }

    return _failResultIfEmpty(
      AppFailureCode.ioFailure,
      messages.capturedImageReadFailed,
      messages.tryCaptureAgain,
    );
  }

  Future<AppResult<CaptureTargetDescriptor>> _validatedWindowTarget(
    CaptureTargetDescriptor target,
  ) async {
    final windowsResult = await getWindows();
    if (windowsResult.isFailure) {
      return AppResult.failure(windowsResult.requireFailure);
    }

    final displayInfos = await _getDisplayMetadata();
    return windowValidator.validate(
      target: target,
      windows: windowsResult.requireValue,
      displays: displayInfos,
    );
  }

  @override
  Future<AppResult<List<DisplayInfo>>> getDisplays() async {
    _clearFailure();
    final nativeResult = await nativeService.listDisplays();
    if (nativeResult.isSuccess) {
      return AppResult.success(
        nativeResult.requireValue.map(_displayInfoFromNativeDisplay).toList(),
      );
    }
    if (nativeResult.requireFailure.code != AppFailureCode.unsupported) {
      _lastFailure = nativeResult.requireFailure;
      return AppResult.failure(nativeResult.requireFailure);
    }

    return _failResult(
      AppFailureCode.unsupported,
      messages.displayEnumerationUnsupported,
      messages.useDefaultDisplayInstead,
    );
  }

  @override
  Future<AppResult<List<WindowInfo>>> getWindows() async {
    _clearFailure();
    final nativeResult = await nativeService.listWindows();
    if (nativeResult.isSuccess) {
      return AppResult.success(
        nativeResult.requireValue.map(_windowInfoFromNativeWindow).toList(),
      );
    }
    if (nativeResult.requireFailure.code != AppFailureCode.unsupported) {
      _lastFailure = nativeResult.requireFailure;
      return AppResult.failure(nativeResult.requireFailure);
    }

    return _failResult(
      AppFailureCode.unsupported,
      messages.windowEnumerationUnsupported,
      messages.useRegionCaptureInstead,
    );
  }

  @override
  Future<AppResult<List<CaptureTargetDescriptor>>> listDisplayTargets() async {
    final displays = await getDisplays();
    if (displays.isFailure) return AppResult.failure(displays.requireFailure);

    final virtualBounds = unionRects(
      displays.requireValue.map((display) => display.bounds),
    );
    return AppResult.success(
      displays.requireValue
          .map((display) => _displayTargetFromInfo(display, virtualBounds))
          .toList(),
    );
  }

  @override
  Future<AppResult<List<CaptureTargetDescriptor>>> listWindowTargets() async {
    final windows = await getWindows();
    if (windows.isFailure) return AppResult.failure(windows.requireFailure);

    final displayInfos = await _getDisplayMetadata();
    final virtualBounds = unionRects(
      displayInfos.map((display) => display.bounds),
    );

    return AppResult.success(
      windows.requireValue
          .where(
            (window) =>
                window.isVisible &&
                window.isOnScreen &&
                window.bounds.width > 20 &&
                window.bounds.height > 20,
          )
          .map(
            (window) => windowValidator.windowTargetFromInfo(
              window,
              displayInfos,
              virtualBounds,
            ),
          )
          .toList(),
    );
  }

  Future<List<DisplayInfo>> _getDisplayMetadata() async {
    final nativeResult = await nativeService.listDisplays();
    if (nativeResult.isFailure) {
      return const <DisplayInfo>[];
    }
    return nativeResult.requireValue.map(_displayInfoFromNativeDisplay).toList();
  }

  Future<Directory> _captureTemporaryDirectory() async {
    final provider = temporaryDirectoryProvider;
    final base = provider == null
        ? await getTemporaryDirectory()
        : await provider();
    final directory = Directory(p.join(base.path, 'desktop_screen_capture'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String> _newCapturePath() async {
    final directory = await _captureTemporaryDirectory();
    _capturePathSequence = (_capturePathSequence + 1) & 0x3fffffff;
    return p.join(
      directory.path,
      'capture_${DateTime.now().microsecondsSinceEpoch}_'
      '$_capturePathSequence.png',
    );
  }

  Future<sc.CapturedData?> _captureToFile({
    required sc.CaptureMode mode,
    required String imagePath,
  }) {
    return sc.screenCapturer.capture(
      mode: mode,
      imagePath: imagePath,
      copyToClipboard: false,
      silent: true,
    );
  }

  Future<AppResult<CaptureResult>> _readCaptureFile(
    String imagePath, {
    Size? fallbackSize,
    int? displayId,
    int? windowId,
    CaptureTargetDescriptor? target,
    WindowCaptureOptions? windowOptions,
    CaptureMode captureMode = CaptureMode.region,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return _failResult(
        AppFailureCode.ioFailure,
        messages.captureFileMissing,
        messages.tryCaptureAgain,
      );
    }

    final bytes = await _readAndDeleteCaptureFile(file);
    Size size = fallbackSize ?? Size.zero;
    if (size.width <= 0 || size.height <= 0) {
      final decoded = await decodeImageFromList(bytes);
      try {
        size = Size(decoded.width.toDouble(), decoded.height.toDouble());
      } finally {
        decoded.dispose();
      }
    }

    return AppResult.success(
      CaptureResult(
        imageBytes: bytes,
        size: size,
        displayId: displayId,
        windowId: windowId,
        target: target,
        windowOptions: windowOptions,
        captureMode: captureMode,
      ),
    );
  }

  Future<AppResult<CaptureResult>?> _captureRegionWithNativeBridge({
    required CaptureRegionSelection selection,
  }) async {
    final displaysResult = await getDisplays();
    if (displaysResult.isFailure) {
      final failure = displaysResult.requireFailure;
      if (failure.code == AppFailureCode.unsupported) {
        _recordFallback(
          operation: 'captureRegion',
          failure: failure,
          fallbackPath: 'screen_capturer',
        );
        return null;
      }
      _lastFailure = failure;
      return AppResult.failure(failure);
    }

    final requestResult = regionResolver.resolve(
      selection: selection,
      displays: displaysResult.requireValue,
    );
    if (requestResult.isFailure) {
      _lastFailure = requestResult.requireFailure;
      return AppResult.failure(requestResult.requireFailure);
    }

    final request = requestResult.requireValue;
    final nativeResult = await nativeService.captureRegion(
      NativeCaptureRequest(
        displayId: request.display?.id,
        region: NativePhysicalRect.fromRect(request.physicalRegion),
      ),
    );
    if (nativeResult.isFailure) {
      if (nativeResult.requireFailure.code == AppFailureCode.unsupported) {
        _recordFallback(
          operation: 'captureRegion',
          failure: nativeResult.requireFailure,
          fallbackPath: 'screen_capturer',
        );
        return null;
      }
      _lastFailure = nativeResult.requireFailure;
      return AppResult.failure(nativeResult.requireFailure);
    }

    return AppResult.success(
      _captureResultFromNative(
        nativeResult.requireValue,
        target: request.target,
      ),
    );
  }

  CaptureResult _captureResultFromNative(
    NativeCaptureFrame frame, {
    CaptureTargetDescriptor? target,
    WindowCaptureOptions? windowOptions,
    CaptureMode captureMode = CaptureMode.region,
  }) {
    return CaptureResult(
      imageBytes: frame.imageBytes,
      size: frame.size,
      sourcePath: frame.sourcePath,
      isTemporary: frame.isTemporary,
      displayId: frame.displayId,
      windowId: frame.windowId,
      scaleFactor: frame.scaleFactor,
      target: target,
      windowOptions: windowOptions,
      captureMode: captureMode,
    );
  }

  CaptureTargetDescriptor _displayTargetFromInfo(
    DisplayInfo display,
    Rect virtualBounds,
  ) {
    return CaptureTargetDescriptor.display(
      displayId: display.id,
      title: display.name,
      boundsLogical: display.bounds,
      scaleFactor: display.scaleFactor,
      virtualScreenBoundsLogical: virtualBounds,
    );
  }

  DisplayInfo _displayInfoFromNativeDisplay(NativeDisplay data) {
    return DisplayInfo(
      id: data.id,
      name: data.name,
      bounds: data.bounds,
      scaleFactor: data.scaleFactor,
      isPrimary: data.isPrimary,
      isInternal: data.isInternal,
    );
  }

  WindowInfo _windowInfoFromNativeWindow(NativeWindow data) {
    return WindowInfo(
      id: data.id,
      title: data.title.isEmpty ? data.appName : data.title,
      appName: data.appName,
      bounds: data.bounds,
      displayId: data.displayId,
      isVisible: data.isVisible,
      isOnScreen: data.isOnScreen,
      thumbnailBytes: data.thumbnailBytes,
      appIconBytes: data.appIconBytes,
    );
  }

  Future<void> _deleteCaptureFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup must not turn a successful capture into a failure.
    }
  }

  Future<Uint8List> _readAndDeleteCaptureFile(File file) async {
    try {
      return await file.readAsBytes();
    } finally {
      await _deleteCaptureFile(file);
    }
  }

  void _clearFailure() {
    _lastFailure = null;
    _lastFallbackDiagnostic = null;
  }

  void _recordFallback({
    required String operation,
    required AppFailure failure,
    required String fallbackPath,
  }) {
    _lastFailure = null;
    _lastFallbackDiagnostic = CaptureFallbackDiagnostic(
      operation: operation,
      failure: failure,
      fallbackPath: fallbackPath,
    );
  }

  AppResult<T> _failResult<T>(
    AppFailureCode code,
    String message,
    String recoverySuggestion, [
    Object? cause,
    StackTrace? stackTrace,
  ]) {
    _lastFailure = AppFailure(
      code: code,
      message: message,
      recoverySuggestion: recoverySuggestion,
      cause: cause,
      stackTrace: stackTrace,
    );
    return AppResult.failure(_lastFailure!);
  }

  AppResult<T> _failResultIfEmpty<T>(
    AppFailureCode code,
    String message,
    String recoverySuggestion, [
    Object? cause,
    StackTrace? stackTrace,
  ]) {
    final failure = _lastFailure;
    if (failure != null) {
      return AppResult.failure(failure);
    }
    return _failResult(code, message, recoverySuggestion, cause, stackTrace);
  }

  Rect _normalizedRect(Rect rect) {
    return Rect.fromLTRB(
      rect.left < rect.right ? rect.left : rect.right,
      rect.top < rect.bottom ? rect.top : rect.bottom,
      rect.left < rect.right ? rect.right : rect.left,
      rect.top < rect.bottom ? rect.bottom : rect.top,
    );
  }

  bool _isFiniteRect(Rect rect) {
    return rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite;
  }

  bool _isFiniteNullableRect(Rect? rect) {
    return rect == null || _isFiniteRect(rect);
  }

  bool _isFiniteSize(Size? size) {
    return size == null ||
        (size.width.isFinite &&
            size.height.isFinite &&
            size.width >= 0 &&
            size.height >= 0);
  }
}
