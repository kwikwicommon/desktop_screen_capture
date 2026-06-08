library desktop_screen_capture_windows;

import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';

class DesktopScreenCaptureWindowsPlatform
    extends MethodChannelDesktopScreenCapture {
  DesktopScreenCaptureWindowsPlatform();

  static void registerWith() {
    DesktopScreenCapturePlatform.instance =
        DesktopScreenCaptureWindowsPlatform();
  }
}

class DesktopScreenCaptureWindows {
  const DesktopScreenCaptureWindows._();

  static void registerWith() =>
      DesktopScreenCaptureWindowsPlatform.registerWith();
}
