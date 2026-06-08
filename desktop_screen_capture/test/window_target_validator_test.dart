import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects stale window target', () {
    const validator = WindowTargetValidator();
    final target = CaptureTargetDescriptor.window(
      windowId: 10,
      title: 'Editor',
      appName: 'Editor',
      boundsLogical: const Rect.fromLTWH(0, 0, 400, 300),
      scaleFactor: 1,
      displayId: 1,
    );

    final result = validator.validate(
      target: target,
      windows: const [],
      displays: const [
        DisplayInfo(
          id: 1,
          name: 'Primary',
          bounds: Rect.fromLTWH(0, 0, 800, 600),
          scaleFactor: 1,
          isPrimary: true,
        ),
      ],
    );

    expect(result.isFailure, isTrue);
    expect(result.requireFailure.code, AppFailureCode.unavailable);
    expect(result.requireFailure.cause, containsPair('reason', 'stale'));
  });

  test('returns refreshed window target when selected target is still valid', () {
    const validator = WindowTargetValidator();
    final target = CaptureTargetDescriptor.window(
      windowId: 10,
      title: 'Editor',
      appName: 'Editor',
      boundsLogical: const Rect.fromLTWH(100, 100, 400, 300),
      scaleFactor: 1,
      displayId: 1,
    );

    final result = validator.validate(
      target: target,
      windows: const [
        WindowInfo(
          id: 10,
          title: 'Editor',
          appName: 'Editor',
          bounds: Rect.fromLTWH(102, 101, 401, 299),
          displayId: 1,
        ),
      ],
      displays: const [
        DisplayInfo(
          id: 1,
          name: 'Primary',
          bounds: Rect.fromLTWH(0, 0, 800, 600),
          scaleFactor: 2,
          isPrimary: true,
        ),
      ],
    );

    expect(result.isSuccess, isTrue);
    expect(result.requireValue.nativeId, 10);
    expect(result.requireValue.scaleFactor, 2);
    expect(result.requireValue.displayBoundsLogical,
        const Rect.fromLTWH(0, 0, 800, 600));
  });
}
