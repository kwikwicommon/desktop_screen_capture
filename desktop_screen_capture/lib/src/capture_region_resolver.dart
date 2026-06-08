import 'package:flutter/material.dart';

import 'app_error.dart';
import 'capture_messages.dart';
import 'capture_service.dart';
import 'capture_target.dart';

class ResolvedCaptureRegionRequest {
  final Rect physicalRegion;
  final DisplayInfo? display;
  final CaptureTargetDescriptor target;

  const ResolvedCaptureRegionRequest({
    required this.physicalRegion,
    required this.display,
    required this.target,
  });
}

class CaptureRegionResolver {
  final CaptureMessages messages;

  const CaptureRegionResolver({
    this.messages = const CaptureMessages(),
  });

  AppResult<ResolvedCaptureRegionRequest> resolve({
    required CaptureRegionSelection selection,
    required List<DisplayInfo> displays,
  }) {
    if (!isFiniteRect(selection.normalizedRect) ||
        !isFiniteSize(selection.sourceSize) ||
        !isFiniteNullableRect(selection.displayBoundsLogical) ||
        !isFiniteNullableRect(selection.virtualScreenBoundsLogical) ||
        !selection.scaleFactor.isFinite) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.invalidInput,
          message: messages.regionOutsideTargetDisplay,
          recoverySuggestion: messages.selectAreaInsideSingleDisplay,
        ),
      );
    }

    final display = selectDisplayForSelection(selection, displays);
    final requiresDisplay =
        selection.displayId != null ||
        selection.coordinateSpace == CaptureCoordinateSpace.displayLogical ||
        selection.coordinateSpace == CaptureCoordinateSpace.displayPhysical ||
        selection.coordinateSpace == CaptureCoordinateSpace.virtualLogical ||
        selection.coordinateSpace == CaptureCoordinateSpace.virtualPhysical;
    if (requiresDisplay && display == null) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.invalidInput,
          message: messages.selectedDisplayUnresolved,
          recoverySuggestion: messages.refreshDisplayTargets,
        ),
      );
    }

    final localRect = displayLocalSelectionRect(selection, display);
    if (localRect == null || localRect.width < 1 || localRect.height < 1) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.invalidInput,
          message: messages.regionOutsideTargetDisplay,
          recoverySuggestion: messages.selectAreaInsideSingleDisplay,
        ),
      );
    }

    final scale = scaleForSelection(selection, display);
    final physicalRect = physicalRectForSelection(
      localRect,
      scale,
      selection.coordinateSpace,
    );
    if (!isFiniteRect(physicalRect) ||
        physicalRect.width < 1 ||
        physicalRect.height < 1) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.invalidInput,
          message: messages.regionOutsideTargetDisplay,
          recoverySuggestion: messages.selectAreaInsideSingleDisplay,
        ),
      );
    }
    final target = selection
        .copyWith(
          rect: selection.normalizedRect,
          sourceSize: targetSourceSizeForSelection(selection, display),
          displayId: display?.id ?? selection.displayId,
          displayBoundsLogical:
              selection.displayBoundsLogical ?? display?.bounds,
          virtualScreenBoundsLogical:
              selection.virtualScreenBoundsLogical ??
              unionRects(displays.map((item) => item.bounds)),
          scaleFactor: scale,
          coordinateSpace: selection.coordinateSpace,
        )
        .toTargetDescriptor();

    return AppResult.success(
      ResolvedCaptureRegionRequest(
        physicalRegion: physicalRect,
        display: display,
        target: target,
      ),
    );
  }

  DisplayInfo? selectDisplayForSelection(
    CaptureRegionSelection selection,
    List<DisplayInfo> displays,
  ) {
    for (final display in displays) {
      if (selection.displayId != null && display.id == selection.displayId) {
        return display;
      }
    }

    final displayBounds = selection.displayBoundsLogical;
    if (displayBounds != null) {
      for (final display in displays) {
        if (rectsNear(display.bounds, displayBounds)) {
          return display;
        }
      }
    }

    final rect = selection.normalizedRect;
    if (selection.coordinateSpace == CaptureCoordinateSpace.virtualLogical ||
        selection.coordinateSpace == CaptureCoordinateSpace.virtualPhysical) {
      for (final display in displays) {
        final bounds = displayBoundsForSelection(display, selection);
        if (rectContainsRect(bounds, rect)) {
          return display;
        }
      }
      for (final display in displays) {
        final bounds = displayBoundsForSelection(display, selection);
        if (bounds.overlaps(rect)) {
          return display;
        }
      }
    }

    if (selection.sourceSize.width > 0 && selection.sourceSize.height > 0) {
      final display = selectDisplayForSourceSize(
        selection.sourceSize,
        displays,
      );
      if (display != null) return display;
    }

    for (final display in displays) {
      if (display.isPrimary) return display;
    }
    return displays.isEmpty ? null : displays.first;
  }

  Rect? displayLocalSelectionRect(
    CaptureRegionSelection selection,
    DisplayInfo? display,
  ) {
    final rect = selection.normalizedRect;
    switch (selection.coordinateSpace) {
      case CaptureCoordinateSpace.displayLogical:
        if (!localRectFitsDisplaySource(selection, display, false)) {
          return null;
        }
        return rect;
      case CaptureCoordinateSpace.displayPhysical:
        if (!localRectFitsDisplaySource(selection, display, true)) {
          return null;
        }
        return rect;
      case CaptureCoordinateSpace.virtualLogical:
        final bounds = display?.bounds ?? selection.displayBoundsLogical;
        if (bounds == null || !rectContainsRect(bounds, rect)) {
          return null;
        }
        return rect.shift(Offset(-bounds.left, -bounds.top));
      case CaptureCoordinateSpace.virtualPhysical:
        final bounds = display == null
            ? scaledRect(
                selection.displayBoundsLogical,
                safeScaleFactor(selection.scaleFactor),
              )
            : physicalDisplayBounds(display);
        if (bounds == null || !rectContainsRect(bounds, rect)) {
          return null;
        }
        return rect.shift(Offset(-bounds.left, -bounds.top));
    }
  }

  Rect physicalRectForSelection(
    Rect localRect,
    double scale,
    CaptureCoordinateSpace coordinateSpace,
  ) {
    switch (coordinateSpace) {
      case CaptureCoordinateSpace.displayPhysical:
      case CaptureCoordinateSpace.virtualPhysical:
        return localRect;
      case CaptureCoordinateSpace.displayLogical:
      case CaptureCoordinateSpace.virtualLogical:
        return Rect.fromLTWH(
          localRect.left * scale,
          localRect.top * scale,
          localRect.width * scale,
          localRect.height * scale,
        );
    }
  }

  double scaleForSelection(
    CaptureRegionSelection selection,
    DisplayInfo? display,
  ) {
    if (selection.coordinateSpace == CaptureCoordinateSpace.displayPhysical ||
        selection.coordinateSpace == CaptureCoordinateSpace.virtualPhysical) {
      return 1;
    }
    if (selection.scaleFactor > 0 && selection.scaleFactor != 1) {
      return selection.scaleFactor;
    }
    return safeScaleFactor(display?.scaleFactor ?? 1);
  }

  DisplayInfo? selectDisplayForSourceSize(
    Size sourceSize,
    List<DisplayInfo> displays,
  ) {
    const tolerance = 1.0;
    for (final display in displays) {
      final bounds = display.bounds;
      if ((bounds.width - sourceSize.width).abs() <= tolerance &&
          (bounds.height - sourceSize.height).abs() <= tolerance) {
        return display;
      }
    }

    for (final display in displays) {
      final scaledSize = Size(
        display.bounds.width * display.scaleFactor,
        display.bounds.height * display.scaleFactor,
      );
      if ((scaledSize.width - sourceSize.width).abs() <= tolerance &&
          (scaledSize.height - sourceSize.height).abs() <= tolerance) {
        return display;
      }
    }

    return null;
  }

  Size targetSourceSizeForSelection(
    CaptureRegionSelection selection,
    DisplayInfo? display,
  ) {
    if (selection.sourceSize.width > 0 && selection.sourceSize.height > 0) {
      return selection.sourceSize;
    }
    if (display == null) return Size.zero;
    switch (selection.coordinateSpace) {
      case CaptureCoordinateSpace.displayPhysical:
      case CaptureCoordinateSpace.virtualPhysical:
        final scale = safeScaleFactor(display.scaleFactor);
        return Size(display.bounds.width * scale, display.bounds.height * scale);
      case CaptureCoordinateSpace.displayLogical:
      case CaptureCoordinateSpace.virtualLogical:
        return display.bounds.size;
    }
  }

  Rect displayBoundsForSelection(
    DisplayInfo display,
    CaptureRegionSelection selection,
  ) {
    if (selection.coordinateSpace == CaptureCoordinateSpace.virtualPhysical) {
      return physicalDisplayBounds(display);
    }
    return display.bounds;
  }

  Rect physicalDisplayBounds(DisplayInfo display) {
    final scale = safeScaleFactor(display.scaleFactor);
    return Rect.fromLTWH(
      display.bounds.left * scale,
      display.bounds.top * scale,
      display.bounds.width * scale,
      display.bounds.height * scale,
    );
  }

  Rect? scaledRect(Rect? rect, double scale) {
    if (rect == null) return null;
    return Rect.fromLTWH(
      rect.left * scale,
      rect.top * scale,
      rect.width * scale,
      rect.height * scale,
    );
  }

  bool localRectFitsDisplaySource(
    CaptureRegionSelection selection,
    DisplayInfo? display,
    bool isPhysical,
  ) {
    final rect = selection.normalizedRect;
    final sourceSize = displaySourceSize(selection, display, isPhysical);
    if (sourceSize.width <= 0 || sourceSize.height <= 0) {
      return true;
    }
    return rectContainsRect(
      Rect.fromLTWH(0, 0, sourceSize.width, sourceSize.height),
      rect,
    );
  }

  Size displaySourceSize(
    CaptureRegionSelection selection,
    DisplayInfo? display,
    bool isPhysical,
  ) {
    if (selection.sourceSize.width > 0 && selection.sourceSize.height > 0) {
      return selection.sourceSize;
    }
    final logicalSize =
        display?.bounds.size ?? selection.displayBoundsLogical?.size;
    if (logicalSize == null) return Size.zero;
    if (!isPhysical) return logicalSize;
    final scale = display == null
        ? safeScaleFactor(selection.scaleFactor)
        : safeScaleFactor(display.scaleFactor);
    return Size(logicalSize.width * scale, logicalSize.height * scale);
  }

  bool isFiniteRect(Rect rect) {
    return rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite;
  }

  bool isFiniteNullableRect(Rect? rect) {
    return rect == null || isFiniteRect(rect);
  }

  bool isFiniteSize(Size size) {
    return size.width.isFinite &&
        size.height.isFinite &&
        size.width >= 0 &&
        size.height >= 0;
  }

  double safeScaleFactor(double scaleFactor) {
    return scaleFactor.isFinite && scaleFactor > 0 ? scaleFactor : 1;
  }

  bool rectContainsRect(Rect outer, Rect inner) {
    const tolerance = 0.5;
    return inner.left >= outer.left - tolerance &&
        inner.top >= outer.top - tolerance &&
        inner.right <= outer.right + tolerance &&
        inner.bottom <= outer.bottom + tolerance;
  }

  bool rectsNear(Rect first, Rect second) {
    const tolerance = 1.0;
    return (first.left - second.left).abs() <= tolerance &&
        (first.top - second.top).abs() <= tolerance &&
        (first.width - second.width).abs() <= tolerance &&
        (first.height - second.height).abs() <= tolerance;
  }
}
