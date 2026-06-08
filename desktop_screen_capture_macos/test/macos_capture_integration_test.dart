
import 'package:desktop_screen_capture_macos/desktop_screen_capture_macos.dart';
import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';
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

  test('registerWith installs macOS platform implementation', () {
    DesktopScreenCaptureMacosPlatform.registerWith();

    expect(
      DesktopScreenCapturePlatform.instance,
      isA<DesktopScreenCaptureMacosPlatform>(),
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
          'imageBytes': Uint8List.fromList([1, 2, 3]),
          'width': 10,
          'height': 8,
          'displayId': 42,
          'scaleFactor': 2.0,
          'isTemporary': false,
        },
      };
    });

    await DesktopScreenCaptureMacosPlatform().captureDisplay(
      const NativeCaptureRequest(displayId: 42),
    );

    expect(methodName, DesktopNativeMethod.captureDisplay);
  });

  test('listDisplays envelope is parsed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return {
        'status': 'success',
        'payload': [
          {
            'id': 42,
            'name': 'Built-in Display',
            'bounds': {'left': 0, 'top': 0, 'width': 1440, 'height': 900},
            'scaleFactor': 2.0,
            'isPrimary': true,
            'isInternal': true,
          },
        ],
      };
    });

    final displays = await DesktopScreenCaptureMacosPlatform().listDisplays();

    expect(displays.single.id, 42);
    expect(displays.single.isInternal, isTrue);
  });

  test('listWindows envelope is parsed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return {
        'status': 'success',
        'payload': [
          {
            'id': 7,
            'title': 'Editor',
            'appName': 'Code',
            'bounds': {'left': 10, 'top': 20, 'width': 800, 'height': 600},
            'displayId': 42,
            'isVisible': true,
            'isOnScreen': true,
          },
        ],
      };
    });

    final windows = await DesktopScreenCaptureMacosPlatform().listWindows();

    expect(windows.single.id, 7);
    expect(windows.single.appName, 'Code');
  });

  test('permission required status is mapped', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return {
        'status': 'success',
        'payload': {
          'permissions': [
            {
              'type': 'screenRecording',
              'state': 'notDetermined',
              'message': 'Permission required.',
              'requiresRestart': false,
            },
          ],
          'features': [
            {
              'feature': 'captureDisplay',
              'status': 'permissionRequired',
              'message': 'Permission required.',
              'permissionType': 'screenRecording',
            },
          ],
        },
      };
    });

    final snapshot = await DesktopScreenCaptureMacosPlatform()
        .queryCapabilities();

    expect(
      snapshot.features[DesktopFeatureKey.captureDisplay]?.status,
      DesktopFeatureAvailabilityStatus.requiresPermission,
    );
  });

  test('unsupported macOS version status is mapped', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return {
        'status': 'success',
        'payload': {
          'permissions': const [],
          'features': [
            {
              'feature': 'captureDisplay',
              'status': 'unsupported',
              'message': 'Requires macOS 12.3 or later.',
            },
          ],
        },
      };
    });

    final snapshot = await DesktopScreenCaptureMacosPlatform()
        .queryCapabilities();

    expect(
      snapshot.features[DesktopFeatureKey.captureDisplay]?.status,
      DesktopFeatureAvailabilityStatus.unsupported,
    );
  });
}
