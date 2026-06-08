import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_desktop_screen_capture.dart';
import 'native_contract.dart';

abstract class DesktopScreenCapturePlatform extends PlatformInterface {
  static final Object _token = Object();

  static DesktopScreenCapturePlatform _instance =
      MethodChannelDesktopScreenCapture();

  DesktopScreenCapturePlatform() : super(token: _token);

  static DesktopScreenCapturePlatform get instance => _instance;

  static set instance(DesktopScreenCapturePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<List<NativeDisplay>> listDisplays() {
    throw UnimplementedError('listDisplays() has not been implemented.');
  }

  Future<List<NativeWindow>> listWindows() {
    throw UnimplementedError('listWindows() has not been implemented.');
  }

  Future<NativeRegionSelection> selectRegion() {
    throw UnimplementedError('selectRegion() has not been implemented.');
  }

  Future<NativeCaptureFrame> captureDisplay(NativeCaptureRequest request) {
    throw UnimplementedError('captureDisplay() has not been implemented.');
  }

  Future<NativeCaptureFrame> captureWindow(NativeCaptureRequest request) {
    throw UnimplementedError('captureWindow() has not been implemented.');
  }

  Future<NativeCaptureFrame> captureRegion(NativeCaptureRequest request) {
    throw UnimplementedError('captureRegion() has not been implemented.');
  }

  Future<NativeEncodedImage> encodeImage(NativeImageEncodeRequest request) {
    throw UnimplementedError('encodeImage() has not been implemented.');
  }

  Future<DesktopCapabilitySnapshot> queryCapabilities() {
    throw UnimplementedError('queryCapabilities() has not been implemented.');
  }

  Future<DesktopPermissionInfo> requestPermission(
    DesktopPermissionType permissionType,
  ) {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }
}
