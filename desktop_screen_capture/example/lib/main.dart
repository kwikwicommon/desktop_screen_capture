import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:flutter/widgets.dart';

void configureCapture() {
  DesktopScreenCapture.registerWith(() => CaptureServiceImpl());
}

Future<CaptureResult> capturePrimaryDisplay() async {
  final result = await DesktopScreenCapture.instance.captureFullscreen();
  if (result.isFailure) {
    throw StateError(result.requireFailure.toString());
  }
  return result.requireValue;
}

Future<CaptureResult> captureFixedRegion() async {
  final result = await DesktopScreenCapture.instance.captureRegion(
    const Rect.fromLTWH(0, 0, 640, 360),
  );
  if (result.isFailure) {
    throw StateError(result.requireFailure.toString());
  }
  return result.requireValue;
}
