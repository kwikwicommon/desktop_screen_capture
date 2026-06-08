import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = DesktopScreenCapturePlatform.instance;

  tearDown(() {
    DesktopScreenCapturePlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          null,
        );
  });

  test('default instance is method channel implementation', () {
    expect(
      DesktopScreenCapturePlatform.instance,
      isA<MethodChannelDesktopScreenCapture>(),
    );
  });

  test('mock platform can replace default instance', () {
    final platform = MockDesktopScreenCapturePlatform();

    DesktopScreenCapturePlatform.instance = platform;

    expect(DesktopScreenCapturePlatform.instance, same(platform));
  });

  test('token verification rejects invalid platform', () {
    expect(
      () => DesktopScreenCapturePlatform.instance =
          InvalidDesktopScreenCapturePlatform(),
      throwsAssertionError,
    );
  });

  test('method channel parses success envelope', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            expect(call.method, DesktopNativeMethod.listDisplays);
            return {
              'status': 'success',
              'payload': [
                {
                  'id': 12,
                  'name': 'Main',
                  'bounds': {'left': 0, 'top': 0, 'width': 800, 'height': 600},
                  'scaleFactor': 2.0,
                  'isPrimary': true,
                  'isInternal': false,
                },
              ],
            };
          },
        );

    final displays = await MethodChannelDesktopScreenCapture().listDisplays();

    expect(displays, hasLength(1));
    expect(displays.single.id, 12);
    expect(displays.single.scaleFactor, 2);
  });

  test('method channel maps failure envelope', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            return {
              'status': 'unsupported',
              'failure': {
                'message': 'Not supported.',
                'recoverySuggestion': 'Use fallback.',
                'nativeCode': 'UNSUPPORTED',
                'recoverability': 'notRecoverable',
                'requiresRestart': true,
              },
            };
          },
        );

    expect(
      MethodChannelDesktopScreenCapture().listWindows,
      throwsA(
        isA<DesktopScreenCapturePlatformException>()
            .having((error) => error.status, 'status', 'unsupported')
            .having((error) => error.nativeCode, 'nativeCode', 'UNSUPPORTED')
            .having((error) => error.requiresRestart, 'requiresRestart', isTrue)
            .having(
              (error) => error.failure?.requiresRestart,
              'failure.requiresRestart',
              isTrue,
            ),
      ),
    );
  });

  test('method channel maps malformed failure fields defensively', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            return {
              'status': 'permissionDenied',
              'failure': {
                'message': 404,
                'recoverySuggestion': <String>['retry'],
                'nativeCode': 500,
                'recoverability': 12,
                'domain': false,
              },
            };
          },
        );

    expect(
      MethodChannelDesktopScreenCapture().listWindows(),
      throwsA(
        isA<DesktopScreenCapturePlatformException>()
            .having(
              (error) => error.message,
              'message',
              'Native operation failed.',
            )
            .having((error) => error.nativeCode, 'nativeCode', '')
            .having(
              (error) => error.failure?.recoverability,
              'recoverability',
              NativeFailureRecoverability.unknown,
            ),
      ),
    );
  });

  test('method channel rejects malformed success payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            return {
              'status': 'success',
              'payload': {'unexpected': true},
            };
          },
        );

    expect(
      MethodChannelDesktopScreenCapture().listDisplays(),
      throwsA(
        isA<DesktopScreenCapturePlatformException>().having(
          (error) => error.status,
          'status',
          'serialization',
        ),
      ),
    );
  });

  test('method channel rejects missing display bounds', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            return {
              'status': 'success',
              'payload': [
                {'id': 12, 'name': 'Main', 'scaleFactor': 2.0},
              ],
            };
          },
        );

    expect(
      MethodChannelDesktopScreenCapture().listDisplays(),
      throwsA(
        isA<DesktopScreenCapturePlatformException>().having(
          (error) => error.status,
          'status',
          'serialization',
        ),
      ),
    );
  });

  test(
    'method channel rejects invalid region selection coordinate space',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannelDesktopScreenCapture.defaultChannel,
            (call) async {
              return {
                'status': 'success',
                'payload': {
                  'rect': {'left': 0, 'top': 0, 'width': 100, 'height': 50},
                  'sourceSize': {'width': 200, 'height': 100},
                  'scaleFactor': 1,
                  'coordinateSpace': 'windowLogical',
                },
              };
            },
          );

      expect(
        MethodChannelDesktopScreenCapture().selectRegion(),
        throwsA(
          isA<DesktopScreenCapturePlatformException>().having(
            (error) => error.status,
            'status',
            'serialization',
          ),
        ),
      );
    },
  );

  test(
    'method channel parses Windows display-physical selection fixture',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannelDesktopScreenCapture.defaultChannel,
            (call) async {
              expect(call.method, DesktopNativeMethod.selectRegion);
              return {
                'status': 'success',
                'payload': {
                  'rect': {'left': 16, 'top': 24, 'width': 640, 'height': 360},
                  'sourceSize': {'width': 1920, 'height': 1080},
                  'displayId': 2,
                  'displayBoundsLogical': {
                    'left': -1280,
                    'top': 0,
                    'width': 1280,
                    'height': 720,
                  },
                  'virtualScreenBoundsLogical': {
                    'left': -1280,
                    'top': 0,
                    'width': 3200,
                    'height': 1080,
                  },
                  'scaleFactor': 1.5,
                  'coordinateSpace': 'displayPhysical',
                },
              };
            },
          );

      final selection = await MethodChannelDesktopScreenCapture()
          .selectRegion();

      expect(selection.rect, const Rect.fromLTWH(16, 24, 640, 360));
      expect(selection.sourceSize, const Size(1920, 1080));
      expect(selection.displayId, 2);
      expect(
        selection.displayBoundsLogical,
        const Rect.fromLTWH(-1280, 0, 1280, 720),
      );
      expect(
        selection.virtualScreenBoundsLogical,
        const Rect.fromLTWH(-1280, 0, 3200, 1080),
      );
      expect(selection.scaleFactor, 1.5);
      expect(selection.coordinateSpace, 'displayPhysical');
    },
  );

  test(
    'method channel parses macOS display-logical selection fixture',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannelDesktopScreenCapture.defaultChannel,
            (call) async {
              expect(call.method, DesktopNativeMethod.selectRegion);
              return {
                'status': 'success',
                'payload': {
                  'rect': {'left': 12, 'top': 18, 'width': 320, 'height': 180},
                  'sourceSize': {'width': 1512, 'height': 982},
                  'displayId': 11,
                  'displayBoundsLogical': {
                    'left': 0,
                    'top': 0,
                    'width': 1512,
                    'height': 982,
                  },
                  'virtualScreenBoundsLogical': {
                    'left': -1280,
                    'top': 0,
                    'width': 2792,
                    'height': 982,
                  },
                  'scaleFactor': 2,
                  'coordinateSpace': 'displayLogical',
                },
              };
            },
          );

      final selection = await MethodChannelDesktopScreenCapture()
          .selectRegion();

      expect(selection.rect, const Rect.fromLTWH(12, 18, 320, 180));
      expect(selection.sourceSize, const Size(1512, 982));
      expect(selection.displayId, 11);
      expect(selection.scaleFactor, 2);
      expect(selection.coordinateSpace, 'displayLogical');
      expect(selection.virtualScreenBoundsLogical?.left, -1280);
    },
  );

  test('method channel rejects unknown capability feature key', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            return {
              'status': 'success',
              'payload': {
                'permissions': [
                  {'type': 'screenRecording', 'state': 'granted'},
                ],
                'features': [
                  {'feature': 'futureCaptureMode', 'status': 'available'},
                ],
              },
            };
          },
        );

    expect(
      MethodChannelDesktopScreenCapture().queryCapabilities(),
      throwsA(
        isA<DesktopScreenCapturePlatformException>().having(
          (error) => error.status,
          'status',
          'serialization',
        ),
      ),
    );
  });

  test('method channel rejects empty capture frame bytes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelDesktopScreenCapture.defaultChannel,
          (call) async {
            return {
              'status': 'success',
              'payload': {
                'imageBytes': Uint8List(0),
                'width': 10,
                'height': 10,
              },
            };
          },
        );

    expect(
      MethodChannelDesktopScreenCapture().captureDisplay(
        const NativeCaptureRequest(),
      ),
      throwsA(
        isA<DesktopScreenCapturePlatformException>().having(
          (error) => error.status,
          'status',
          'serialization',
        ),
      ),
    );
  });

  test('native physical rect covers fractional source bounds', () {
    final rect = NativePhysicalRect.fromRect(
      const Rect.fromLTWH(10.2, 3.8, 4.1, 5.1),
    );

    expect(rect.left, 10);
    expect(rect.top, 3);
    expect(rect.width, 5);
    expect(rect.height, 6);
  });
}

class MockDesktopScreenCapturePlatform
    with MockPlatformInterfaceMixin
    implements DesktopScreenCapturePlatform {
  @override
  Future<NativeCaptureFrame> captureDisplay(NativeCaptureRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<NativeCaptureFrame> captureRegion(NativeCaptureRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<NativeCaptureFrame> captureWindow(NativeCaptureRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<NativeEncodedImage> encodeImage(NativeImageEncodeRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<List<NativeDisplay>> listDisplays() {
    throw UnimplementedError();
  }

  @override
  Future<List<NativeWindow>> listWindows() {
    throw UnimplementedError();
  }

  @override
  Future<DesktopCapabilitySnapshot> queryCapabilities() {
    throw UnimplementedError();
  }

  @override
  Future<DesktopPermissionInfo> requestPermission(
    DesktopPermissionType permissionType,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<NativeRegionSelection> selectRegion() {
    throw UnimplementedError();
  }
}

class InvalidDesktopScreenCapturePlatform
    implements DesktopScreenCapturePlatform {
  @override
  Future<NativeCaptureFrame> captureDisplay(NativeCaptureRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<NativeCaptureFrame> captureRegion(NativeCaptureRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<NativeCaptureFrame> captureWindow(NativeCaptureRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<NativeEncodedImage> encodeImage(NativeImageEncodeRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<List<NativeDisplay>> listDisplays() {
    throw UnimplementedError();
  }

  @override
  Future<List<NativeWindow>> listWindows() {
    throw UnimplementedError();
  }

  @override
  Future<DesktopCapabilitySnapshot> queryCapabilities() {
    throw UnimplementedError();
  }

  @override
  Future<DesktopPermissionInfo> requestPermission(
    DesktopPermissionType permissionType,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<NativeRegionSelection> selectRegion() {
    throw UnimplementedError();
  }
}
