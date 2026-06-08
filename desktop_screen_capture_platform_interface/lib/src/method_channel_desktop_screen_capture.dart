import 'package:flutter/services.dart';

import 'native_contract.dart';
import 'platform.dart';
import 'platform_exception.dart';

class MethodChannelDesktopScreenCapture extends DesktopScreenCapturePlatform {
  static const MethodChannel defaultChannel = MethodChannel(
    'desktop_screen_capture/native',
  );

  final MethodChannel channel;

  MethodChannelDesktopScreenCapture({
    this.channel = defaultChannel,
  });

  @override
  Future<List<NativeDisplay>> listDisplays() {
    return _invokePayload(
      DesktopNativeMethod.listDisplays,
      parser: (payload) => _parseList(payload, NativeDisplay.fromMap),
    );
  }

  @override
  Future<List<NativeWindow>> listWindows() {
    return _invokePayload(
      DesktopNativeMethod.listWindows,
      parser: (payload) => _parseList(payload, NativeWindow.fromMap),
    );
  }

  @override
  Future<NativeRegionSelection> selectRegion() {
    return _invokePayload(
      DesktopNativeMethod.selectRegion,
      parser: (payload) => NativeRegionSelection.fromMap(_asMap(payload)),
    );
  }

  @override
  Future<NativeCaptureFrame> captureDisplay(NativeCaptureRequest request) {
    return _invokePayload(
      DesktopNativeMethod.captureDisplay,
      arguments: request.toMap(),
      parser: (payload) => NativeCaptureFrame.fromMap(_asMap(payload)),
    );
  }

  @override
  Future<NativeCaptureFrame> captureWindow(NativeCaptureRequest request) {
    return _invokePayload(
      DesktopNativeMethod.captureWindow,
      arguments: request.toMap(),
      parser: (payload) => NativeCaptureFrame.fromMap(_asMap(payload)),
    );
  }

  @override
  Future<NativeCaptureFrame> captureRegion(NativeCaptureRequest request) {
    return _invokePayload(
      DesktopNativeMethod.captureRegion,
      arguments: request.toMap(),
      parser: (payload) => NativeCaptureFrame.fromMap(_asMap(payload)),
    );
  }

  @override
  Future<NativeEncodedImage> encodeImage(NativeImageEncodeRequest request) {
    return _invokePayload(
      DesktopNativeMethod.encodeImage,
      arguments: request.toMap(),
      parser: (payload) => NativeEncodedImage.fromMap(_asMap(payload)),
    );
  }

  @override
  Future<DesktopCapabilitySnapshot> queryCapabilities() {
    return _invokePayload(
      DesktopNativeMethod.queryCapabilities,
      parser: (payload) => DesktopCapabilitySnapshot.fromMap(_asMap(payload)),
    );
  }

  @override
  Future<DesktopPermissionInfo> requestPermission(
    DesktopPermissionType permissionType,
  ) {
    return _invokePayload(
      DesktopNativeMethod.requestPermission,
      arguments: {'type': permissionType.name},
      parser: (payload) => DesktopPermissionInfo.fromMap(_asMap(payload)),
    );
  }

  Future<T> _invokePayload<T>(
    String method, {
    Map<String, Object?>? arguments,
    required T Function(Object? payload) parser,
  }) async {
    final envelope = await invokeEnvelope(method, arguments: arguments);
    try {
      return parser(envelope['payload']);
    } catch (error, stackTrace) {
      throw DesktopScreenCapturePlatformException(
        status: 'serialization',
        message: 'Failed to parse native payload.',
        recoverySuggestion: 'Check the desktop_screen_capture channel contract.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Map<dynamic, dynamic>> invokeEnvelope(
    String method, {
    Map<String, Object?>? arguments,
  }) async {
    try {
      final raw = await channel.invokeMethod<Object?>(method, arguments);
      final envelope = _asMap(raw);
      final status = _statusFromEnvelope(envelope);
      if (status == 'success') return envelope;

      final failureMap = _asOptionalMap(envelope['failure']);
      final failure = NativeFailureEnvelope.fromMap(
        status: status,
        map: failureMap,
      );
      throw DesktopScreenCapturePlatformException.fromFailure(
        failure: failure,
        message: _stringOrDefault(
          failureMap['message'],
          'Native operation failed.',
        ),
        recoverySuggestion: _stringOrDefault(
          failureMap['recoverySuggestion'],
          '',
        ),
        cause: failureMap['details'],
      );
    } on DesktopScreenCapturePlatformException {
      rethrow;
    } on MissingPluginException catch (error, stackTrace) {
      throw DesktopScreenCapturePlatformException(
        status: 'unsupported',
        message: 'The desktop_screen_capture native plugin is not registered.',
        recoverySuggestion: 'Use a supported desktop build.',
        cause: error,
        stackTrace: stackTrace,
      );
    } on PlatformException catch (error, stackTrace) {
      throw DesktopScreenCapturePlatformException(
        status: 'nativeFailure',
        message: error.message ?? error.code,
        recoverySuggestion: '',
        nativeCode: error.code,
        cause: error.details,
        stackTrace: stackTrace,
      );
    } on FormatException catch (error, stackTrace) {
      throw DesktopScreenCapturePlatformException(
        status: 'serialization',
        message: 'Failed to parse native response envelope.',
        recoverySuggestion: 'Check the desktop_screen_capture channel contract.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  List<T> _parseList<T>(
    Object? payload,
    T Function(Map<dynamic, dynamic> map) parser,
  ) {
    if (payload is! List) {
      throw const FormatException('Expected a list payload.');
    }
    return payload.map((item) => parser(_asMap(item))).toList(growable: false);
  }

  Map<dynamic, dynamic> _asMap(Object? raw) {
    if (raw is Map) return raw.cast<dynamic, dynamic>();
    throw const FormatException('Expected a map payload.');
  }

  Map<dynamic, dynamic> _asOptionalMap(Object? raw) {
    if (raw == null) return const <dynamic, dynamic>{};
    return _asMap(raw);
  }

  String _statusFromEnvelope(Map<dynamic, dynamic> envelope) {
    final status = envelope['status'];
    if (status is String && status.isNotEmpty) return status;
    throw const FormatException('Expected a non-empty status field.');
  }

  String _stringOrDefault(Object? value, String fallback) {
    return value is String ? value : fallback;
  }
}
