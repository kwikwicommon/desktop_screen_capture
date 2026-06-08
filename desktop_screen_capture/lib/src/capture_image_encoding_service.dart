import 'dart:typed_data';

import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';

import 'app_error.dart';
import 'capture_messages.dart';
import 'capture_service.dart';
import 'native_service.dart';

class EncodedCaptureImage {
  final Uint8List imageBytes;
  final String format;
  final String extension;
  final String mimeType;

  const EncodedCaptureImage({
    required this.imageBytes,
    required this.format,
    required this.extension,
    required this.mimeType,
  });
}

class CaptureImageEncodingService {
  final NativeCaptureApi nativeService;
  final CaptureMessages messages;

  CaptureImageEncodingService({
    NativeCaptureApi? nativeService,
    DesktopScreenCapturePlatform? platform,
    this.messages = const CaptureMessages(),
  }) : nativeService =
           nativeService ??
           PlatformDesktopCaptureNativeService(
             platform: platform,
             messages: messages,
           );

  Future<AppResult<EncodedCaptureImage>> encode({
    required Uint8List imageBytes,
    required CaptureOutputFormat format,
    required int jpegQuality,
    int matteColor = 0xFFFFFFFF,
  }) async {
    if (imageBytes.isEmpty) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.invalidInput,
          message: messages.encodedImageEmpty,
          recoverySuggestion: messages.tryCaptureAgain,
        ),
      );
    }

    if (format == CaptureOutputFormat.png && _hasPngSignature(imageBytes)) {
      return AppResult.success(
        EncodedCaptureImage(
          imageBytes: imageBytes,
          format: format.name,
          extension: extensionForFormat(format),
          mimeType: mimeTypeForFormat(format),
        ),
      );
    }

    final nativeResult = await nativeService.encodeImage(
      NativeImageEncodeRequest(
        imageBytes: imageBytes,
        format: format.name,
        quality: _clampQuality(jpegQuality),
        matteColor: matteColor,
      ),
    );
    if (nativeResult.isFailure) {
      return AppResult.failure(nativeResult.requireFailure);
    }

    final encoded = nativeResult.requireValue;
    if (encoded.imageBytes.isEmpty) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.ioFailure,
          message: messages.encodedImageEmpty,
          recoverySuggestion: messages.tryCaptureAgain,
        ),
      );
    }

    return AppResult.success(
      EncodedCaptureImage(
        imageBytes: encoded.imageBytes,
        format: encoded.format,
        extension: encoded.extension,
        mimeType: encoded.mimeType,
      ),
    );
  }

  static String extensionForFormat(CaptureOutputFormat format) {
    switch (format) {
      case CaptureOutputFormat.png:
        return 'png';
      case CaptureOutputFormat.jpeg:
        return 'jpeg';
      case CaptureOutputFormat.webp:
        return 'webp';
    }
  }

  static String mimeTypeForFormat(CaptureOutputFormat format) {
    switch (format) {
      case CaptureOutputFormat.png:
        return 'image/png';
      case CaptureOutputFormat.jpeg:
        return 'image/jpeg';
      case CaptureOutputFormat.webp:
        return 'image/webp';
    }
  }

  int _clampQuality(int value) {
    if (value < 1) return 1;
    if (value > 100) return 100;
    return value;
  }

  bool _hasPngSignature(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }
}
