import 'dart:typed_data';

import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps permissionRequired platform failures to permissionDenied', () async {
    final service = PlatformDesktopCaptureNativeService(
      platform: _FailingPlatform(
        status: 'permissionRequired',
        message: 'Permission is required.',
      ),
    );

    final result = await service.listDisplays();

    expect(result.isFailure, isTrue);
    expect(result.requireFailure.code, AppFailureCode.permissionDenied);
    expect(result.requireFailure.recoverySuggestion, isNotEmpty);
  });

  test('returns invalid input before sending empty images to native encoding',
      () async {
    final service = CaptureImageEncodingService(nativeService: _NativeService());

    final result = await service.encode(
      imageBytes: Uint8List(0),
      format: CaptureOutputFormat.jpeg,
      jpegQuality: 90,
    );

    expect(result.isFailure, isTrue);
    expect(result.requireFailure.code, AppFailureCode.invalidInput);
  });

  test('selectNativeRegion preserves unsupported native failure', () async {
    final service = CaptureServiceImpl(
      nativeService: _UnsupportedRegionSelectionNativeService(),
    );

    final result = await service.selectNativeRegion();

    expect(result.isFailure, isTrue);
    expect(result.requireFailure.code, AppFailureCode.unsupported);
    expect(service.lastFailure?.code, AppFailureCode.unsupported);
    expect(service.lastFallbackDiagnostic, isNull);
  });
}

class _FailingPlatform extends DesktopScreenCapturePlatform {
  final String status;
  final String message;

  _FailingPlatform({
    required this.status,
    required this.message,
  });

  @override
  Future<List<NativeDisplay>> listDisplays() {
    throw DesktopScreenCapturePlatformException(
      status: status,
      message: message,
    );
  }
}

class _NativeService implements DesktopCaptureNativeService {
  @override
  Future<AppResult<NativeCaptureFrame>> captureDisplay(
    NativeCaptureRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureRegion(
    NativeCaptureRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureWindow(
    NativeCaptureRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<NativeEncodedImage>> encodeImage(
    NativeImageEncodeRequest request,
  ) async {
    return AppResult.failure(
      const AppFailure(
        code: AppFailureCode.nativeFailure,
        message: 'Unexpected native call.',
      ),
    );
  }

  @override
  Future<AppResult<List<NativeDisplay>>> listDisplays() async {
    return const AppResult.success(<NativeDisplay>[]);
  }

  @override
  Future<AppResult<List<NativeWindow>>> listWindows() async {
    return const AppResult.success(<NativeWindow>[]);
  }

  @override
  Future<AppResult<DesktopCapabilitySnapshot>> queryCapabilities() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<DesktopPermissionInfo>> requestPermission(
    DesktopPermissionType permissionType,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<CaptureRegionSelection>> selectRegion() async {
    throw UnimplementedError();
  }
}

class _UnsupportedRegionSelectionNativeService
    implements DesktopCaptureNativeService {
  @override
  Future<AppResult<CaptureRegionSelection>> selectRegion() async {
    return const AppResult.failure(
      AppFailure(
        code: AppFailureCode.unsupported,
        message: 'Native region selection is unavailable.',
        recoverySuggestion: 'Use a supported desktop build.',
      ),
    );
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureDisplay(
    NativeCaptureRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureRegion(
    NativeCaptureRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<NativeCaptureFrame>> captureWindow(
    NativeCaptureRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<NativeEncodedImage>> encodeImage(
    NativeImageEncodeRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<NativeDisplay>>> listDisplays() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<NativeWindow>>> listWindows() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<DesktopCapabilitySnapshot>> queryCapabilities() async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<DesktopPermissionInfo>> requestPermission(
    DesktopPermissionType permissionType,
  ) async {
    throw UnimplementedError();
  }
}
