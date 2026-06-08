library desktop_screen_capture_macos;

import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';

class DesktopScreenCaptureMacosPlatform extends MethodChannelDesktopScreenCapture {
  DesktopScreenCaptureMacosPlatform();

  static void registerWith() {
    DesktopScreenCapturePlatform.instance = DesktopScreenCaptureMacosPlatform();
  }
}

class DesktopScreenCaptureMacos {
  const DesktopScreenCaptureMacos._();

  static void registerWith() => DesktopScreenCaptureMacosPlatform.registerWith();
}
