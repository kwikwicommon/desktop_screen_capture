import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves virtual logical region to display local physical region', () {
    const resolver = CaptureRegionResolver();
    final result = resolver.resolve(
      selection: const CaptureRegionSelection(
        rect: Rect.fromLTWH(210, 20, 50, 40),
        sourceSize: Size.zero,
        coordinateSpace: CaptureCoordinateSpace.virtualLogical,
      ),
      displays: const [
        DisplayInfo(
          id: 1,
          name: 'Primary',
          bounds: Rect.fromLTWH(0, 0, 200, 100),
          scaleFactor: 1,
          isPrimary: true,
        ),
        DisplayInfo(
          id: 2,
          name: 'Secondary',
          bounds: Rect.fromLTWH(200, 0, 200, 100),
          scaleFactor: 2,
        ),
      ],
    );

    expect(result.isSuccess, isTrue);
    final request = result.requireValue;
    expect(request.display?.id, 2);
    expect(request.physicalRegion, const Rect.fromLTWH(20, 40, 100, 80));
    expect(request.target.displayId, 2);
    expect(request.target.boundsLogical, const Rect.fromLTWH(210, 20, 50, 40));
  });

  test('rejects virtual region crossing display boundary', () {
    const resolver = CaptureRegionResolver();
    final result = resolver.resolve(
      selection: const CaptureRegionSelection(
        rect: Rect.fromLTWH(190, 10, 40, 40),
        sourceSize: Size.zero,
        coordinateSpace: CaptureCoordinateSpace.virtualLogical,
      ),
      displays: const [
        DisplayInfo(
          id: 1,
          name: 'Primary',
          bounds: Rect.fromLTWH(0, 0, 200, 100),
          scaleFactor: 1,
          isPrimary: true,
        ),
        DisplayInfo(
          id: 2,
          name: 'Secondary',
          bounds: Rect.fromLTWH(200, 0, 200, 100),
          scaleFactor: 2,
        ),
      ],
    );

    expect(result.isFailure, isTrue);
    expect(result.requireFailure.code, AppFailureCode.invalidInput);
  });

  test('rejects display logical region outside display source', () {
    const resolver = CaptureRegionResolver();
    final result = resolver.resolve(
      selection: const CaptureRegionSelection(
        rect: Rect.fromLTWH(790, 10, 20, 20),
        sourceSize: Size.zero,
        displayId: 1,
      ),
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
    expect(result.requireFailure.code, AppFailureCode.invalidInput);
  });

  test('resolves virtual physical region to display local physical region', () {
    const resolver = CaptureRegionResolver();
    final result = resolver.resolve(
      selection: const CaptureRegionSelection(
        rect: Rect.fromLTWH(420, 40, 100, 80),
        sourceSize: Size.zero,
        coordinateSpace: CaptureCoordinateSpace.virtualPhysical,
      ),
      displays: const [
        DisplayInfo(
          id: 1,
          name: 'Primary',
          bounds: Rect.fromLTWH(0, 0, 200, 100),
          scaleFactor: 2,
          isPrimary: true,
        ),
        DisplayInfo(
          id: 2,
          name: 'Secondary',
          bounds: Rect.fromLTWH(200, 0, 200, 100),
          scaleFactor: 2,
        ),
      ],
    );

    expect(result.isSuccess, isTrue);
    final request = result.requireValue;
    expect(request.display?.id, 2);
    expect(request.physicalRegion, const Rect.fromLTWH(20, 40, 100, 80));
  });

  test('rejects non-finite region geometry', () {
    const resolver = CaptureRegionResolver();
    final result = resolver.resolve(
      selection: const CaptureRegionSelection(
        rect: Rect.fromLTWH(double.nan, 0, 10, 10),
        sourceSize: Size.zero,
      ),
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
    expect(result.requireFailure.code, AppFailureCode.invalidInput);
  });
}
