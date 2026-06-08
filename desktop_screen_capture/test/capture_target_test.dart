import 'dart:typed_data';

import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes non-finite descriptor scale factors', () {
    final target = CaptureTargetDescriptor.display(
      displayId: 1,
      title: 'Primary',
      boundsLogical: const Rect.fromLTWH(0, 0, 100, 80),
      scaleFactor: double.nan,
    );

    expect(target.scaleFactor, 1);
    expect(target.boundsPhysical, const Rect.fromLTWH(0, 0, 100, 80));
  });

  test('rejects malformed byte arrays during target deserialization', () {
    final target = CaptureTargetDescriptor.fromJson({
      'id': 'window:1',
      'type': 'window',
      'title': 'Editor',
      'boundsLogical': {
        'left': 0,
        'top': 0,
        'width': 100,
        'height': 80,
      },
      'boundsPhysical': {
        'left': 0,
        'top': 0,
        'width': 100,
        'height': 80,
      },
      'thumbnailBytes': [1, -1, 2],
      'appIconBytes': Uint8List.fromList([1, 2, 3]),
    });

    expect(target.thumbnailBytes, isNull);
    expect(target.appIconBytes, Uint8List.fromList([1, 2, 3]));
  });

  test('treats malformed geometry maps as zero rects', () {
    final rect = rectFromJson('not a map');
    final size = sizeFromJson('not a map');

    expect(rect, Rect.zero);
    expect(size, Size.zero);
  });
}
