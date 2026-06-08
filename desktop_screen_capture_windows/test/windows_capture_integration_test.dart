import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';
import 'package:desktop_screen_capture_windows/desktop_screen_capture_windows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = DesktopScreenCapturePlatform.instance;
  const channel = MethodChannel('desktop_screen_capture/native');

  tearDown(() {
    DesktopScreenCapturePlatform.instance = originalPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registerWith installs Windows platform implementation', () {
    DesktopScreenCaptureWindowsPlatform.registerWith();

    expect(
      DesktopScreenCapturePlatform.instance,
      isA<DesktopScreenCaptureWindowsPlatform>(),
    );
  });

  test('MethodChannel method names are stable', () async {
    String? methodName;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodName = call.method;
          return {
            'status': 'success',
            'payload': {
              'imageBytes': Uint8List.fromList([9, 8, 7]),
              'width': 150,
              'height': 75,
              'displayId': 7,
              'scaleFactor': 1.5,
              'isTemporary': false,
            },
          };
        });

    await DesktopScreenCaptureWindowsPlatform().captureRegion(
      const NativeCaptureRequest(
        displayId: 7,
        region: NativePhysicalRect(left: 15, top: 30, width: 150, height: 75),
      ),
    );

    expect(methodName, DesktopNativeMethod.captureRegion);
  });

  test('listDisplays envelope is parsed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return {
            'status': 'success',
            'payload': [
              {
                'id': 7,
                'name': 'Primary',
                'bounds': {'left': 0, 'top': 0, 'width': 800, 'height': 600},
                'scaleFactor': 1.5,
                'isPrimary': true,
                'isInternal': false,
              },
            ],
          };
        });

    final displays = await DesktopScreenCaptureWindowsPlatform().listDisplays();

    expect(displays.single.id, 7);
    expect(displays.single.scaleFactor, 1.5);
  });

  test('listWindows envelope is parsed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return {
            'status': 'success',
            'payload': [
              {
                'id': 30,
                'title': 'Browser',
                'appName': 'Edge',
                'bounds': {'left': 50, 'top': 60, 'width': 900, 'height': 700},
                'displayId': 7,
                'isVisible': true,
                'isOnScreen': true,
              },
            ],
          };
        });

    final windows = await DesktopScreenCaptureWindowsPlatform().listWindows();

    expect(windows.single.id, 30);
    expect(windows.single.title, 'Browser');
  });

  test('selectRegion envelope is parsed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, DesktopNativeMethod.selectRegion);
          return {
            'status': 'success',
            'payload': {
              'rect': {'left': 20, 'top': 30, 'width': 400, 'height': 240},
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
        });

    final selection = await DesktopScreenCaptureWindowsPlatform()
        .selectRegion();

    expect(selection.displayId, 2);
    expect(selection.rect, const Rect.fromLTWH(20, 30, 400, 240));
    expect(selection.sourceSize, const Size(1920, 1080));
    expect(selection.displayBoundsLogical?.left, -1280);
    expect(selection.virtualScreenBoundsLogical?.width, 3200);
    expect(selection.scaleFactor, 1.5);
    expect(selection.coordinateSpace, 'displayPhysical');
  });

  test('selectRegion cancelled failure is mapped', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, DesktopNativeMethod.selectRegion);
          return {
            'status': 'cancelled',
            'failure': {
              'message': 'Region selection was cancelled.',
              'recoverySuggestion': 'Start a new capture when ready.',
              'recoverability': 'notRecoverable',
            },
          };
        });

    expect(
      DesktopScreenCaptureWindowsPlatform().selectRegion(),
      throwsA(
        isA<DesktopScreenCapturePlatformException>()
            .having((error) => error.status, 'status', 'cancelled')
            .having(
              (error) => error.failure?.recoverability,
              'recoverability',
              NativeFailureRecoverability.notRecoverable,
            ),
      ),
    );
  });

  test('queryCapabilities reports native region selection available', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, DesktopNativeMethod.queryCapabilities);
          return {
            'status': 'success',
            'payload': {
              'permissions': [
                {'type': 'screenRecording', 'state': 'granted'},
              ],
              'features': [
                {'feature': 'nativeRegionSelection', 'status': 'available'},
              ],
            },
          };
        });

    final snapshot = await DesktopScreenCaptureWindowsPlatform()
        .queryCapabilities();

    expect(
      snapshot.features[DesktopFeatureKey.nativeRegionSelection]?.status,
      DesktopFeatureAvailabilityStatus.available,
    );
  });

  test('capture failure recoverability is mapped', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return {
            'status': 'ioFailure',
            'failure': {
              'message': 'Capture failed.',
              'recoverySuggestion': 'Try again.',
              'recoverability': 'retryable',
            },
          };
        });

    expect(
      DesktopScreenCaptureWindowsPlatform().captureWindow(
        const NativeCaptureRequest(windowId: 10),
      ),
      throwsA(
        isA<DesktopScreenCapturePlatformException>().having(
          (error) => error.failure?.recoverability,
          'recoverability',
          NativeFailureRecoverability.retryable,
        ),
      ),
    );
  });
}
