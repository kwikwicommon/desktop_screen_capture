import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects non-finite selection geometry while scaling crop rects', () {
    final rect = CaptureImageUtils.scaleSelectionToImage(
      selectionRect: const Rect.fromLTWH(double.nan, 0, 10, 10),
      sourceSize: const Size(100, 100),
      imageSize: const Size(200, 200),
    );

    expect(rect, Rect.zero);
  });

  test('rejects non-finite source and image sizes while scaling crop rects', () {
    final rect = CaptureImageUtils.scaleSelectionToImage(
      selectionRect: const Rect.fromLTWH(0, 0, 10, 10),
      sourceSize: const Size(double.infinity, 100),
      imageSize: const Size(200, 200),
    );

    expect(rect, Rect.zero);
  });
}
