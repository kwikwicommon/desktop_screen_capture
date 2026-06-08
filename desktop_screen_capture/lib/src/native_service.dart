import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';

import 'app_error.dart';
import 'capture_messages.dart';
import 'capture_target.dart';

abstract class NativeCaptureApi {
  Future<AppResult<List<NativeDisplay>>> listDisplays();

  Future<AppResult<List<NativeWindow>>> listWindows();

  Future<AppResult<CaptureRegionSelection>> selectRegion();

  Future<AppResult<NativeCaptureFrame>> captureDisplay(
    NativeCaptureRequest request,
  );

  Future<AppResult<NativeCaptureFrame>> captureWindow(
    NativeCaptureRequest request,
  );

  Future<AppResult<NativeCaptureFrame>> captureRegion(
    NativeCaptureRequest request,
  );

  Future<AppResult<NativeEncodedImage>> encodeImage(
    NativeImageEncodeRequest request,
  );
}

abstract class NativeCapabilityApi {
  Future<AppResult<DesktopCapabilitySnapshot>> queryCapabilities();

  Future<AppResult<DesktopPermissionInfo>> requestPermission(
    DesktopPermissionType permissionType,
  );
}

abstract class DesktopCaptureNativeService
    implements NativeCaptureApi, NativeCapabilityApi {}

class PlatformDesktopCaptureNativeService implements DesktopCaptureNativeService {
  final DesktopScreenCapturePlatform? platform;
  final CaptureMessages messages;

  const PlatformDesktopCaptureNativeService({
    this.platform,
    this.messages = const CaptureMessages(),
  });

  DesktopScreenCapturePlatform get _platform =>
      platform ?? DesktopScreenCapturePlatform.instance;

  @override
  Future<AppResult<List<NativeDisplay>>> listDisplays() {
    return _guard(_platform.listDisplays);
  }

  @override
  Future<AppResult<List<NativeWindow>>> listWindows() {
    return _guard(_platform.listWindows);
  }

  @override
  Future<AppResult<CaptureRegionSelection>> selectRegion() {
    return _guard(() async {
      final selection = await _platform.selectRegion();
      return _regionSelectionFromNative(selection);
    });
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureDisplay(
    NativeCaptureRequest request,
  ) {
    return _guard(() => _platform.captureDisplay(request));
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureWindow(
    NativeCaptureRequest request,
  ) {
    return _guard(() => _platform.captureWindow(request));
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureRegion(
    NativeCaptureRequest request,
  ) {
    return _guard(() => _platform.captureRegion(request));
  }

  @override
  Future<AppResult<NativeEncodedImage>> encodeImage(
    NativeImageEncodeRequest request,
  ) {
    return _guard(() => _platform.encodeImage(request));
  }

  @override
  Future<AppResult<DesktopCapabilitySnapshot>> queryCapabilities() {
    return _guard(_platform.queryCapabilities);
  }

  @override
  Future<AppResult<DesktopPermissionInfo>> requestPermission(
    DesktopPermissionType permissionType,
  ) {
    return _guard(() => _platform.requestPermission(permissionType));
  }

  Future<AppResult<T>> _guard<T>(Future<T> Function() invoke) async {
    try {
      return AppResult.success(await invoke());
    } on DesktopScreenCapturePlatformException catch (error) {
      return AppResult.failure(_failureFromPlatformException(error));
    } catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.nativeFailure,
          message: messages.nativeBridgeInvocationFailed,
          recoverySuggestion: messages.inspectPlatformChannelHandler,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  AppFailure _failureFromPlatformException(
    DesktopScreenCapturePlatformException error,
  ) {
    final failure = error.failure;
    return AppFailure(
      code: failure == null
          ? _failureCodeForStatus(error.status)
          : _failureCodeForEnvelope(failure),
      message: error.message.isEmpty
          ? messages.nativeOperationFailed
          : error.message,
      recoverySuggestion: error.recoverySuggestion.isEmpty
          ? _recoverySuggestionForStatus(error.status)
          : error.recoverySuggestion,
      nativeCode: error.nativeCode,
      cause: failure ?? error.cause,
      stackTrace: error.stackTrace,
    );
  }

  AppFailureCode _failureCodeForEnvelope(NativeFailureEnvelope failure) {
    if (failure.recoverability ==
        NativeFailureRecoverability.userActionRequired) {
      switch (failure.domain) {
        case 'permission':
          return AppFailureCode.permissionDenied;
        case 'configuration':
          return AppFailureCode.notConfigured;
      }
    }

    return _failureCodeForStatus(failure.status);
  }

  AppFailureCode _failureCodeForStatus(String status) {
    switch (status) {
      case 'cancelled':
        return AppFailureCode.cancelled;
      case 'invalidInput':
        return AppFailureCode.invalidInput;
      case 'permissionDenied':
      case 'permissionRequired':
        return AppFailureCode.permissionDenied;
      case 'requiresRestart':
        return AppFailureCode.requiresRestart;
      case 'unsupported':
        return AppFailureCode.unsupported;
      case 'unavailable':
        return AppFailureCode.unavailable;
      case 'notFound':
        return AppFailureCode.notFound;
      case 'ioFailure':
        return AppFailureCode.ioFailure;
      case 'notConfigured':
        return AppFailureCode.notConfigured;
      case 'serialization':
        return AppFailureCode.serialization;
      case 'nativeFailure':
        return AppFailureCode.nativeFailure;
      default:
        return AppFailureCode.nativeFailure;
    }
  }

  String _recoverySuggestionForStatus(String status) {
    switch (status) {
      case 'unsupported':
        return messages.useSupportedDesktopBuild;
      case 'serialization':
        return messages.checkPlatformChannelContract;
      case 'permissionDenied':
      case 'permissionRequired':
        return messages.checkRecordingPermission;
      default:
        return messages.inspectPlatformChannelHandler;
    }
  }

  CaptureRegionSelection _regionSelectionFromNative(
    NativeRegionSelection selection,
  ) {
    return CaptureRegionSelection(
      rect: selection.rect,
      sourceSize: selection.sourceSize,
      displayId: selection.displayId,
      displayBoundsLogical: selection.displayBoundsLogical,
      virtualScreenBoundsLogical: selection.virtualScreenBoundsLogical,
      scaleFactor: selection.scaleFactor,
      coordinateSpace: CaptureCoordinateSpace.fromStorage(
        selection.coordinateSpace,
      ),
    );
  }
}

typedef MethodChannelDesktopNativeService = PlatformDesktopCaptureNativeService;
