import 'package:flutter/material.dart';

import 'app_error.dart';
import 'capture_messages.dart';
import 'capture_service.dart';
import 'capture_target.dart';

class WindowTargetValidator {
  final CaptureMessages messages;

  const WindowTargetValidator({
    this.messages = const CaptureMessages(),
  });

  AppResult<CaptureTargetDescriptor> validate({
    required CaptureTargetDescriptor target,
    required List<WindowInfo> windows,
    required List<DisplayInfo> displays,
  }) {
    final windowId = target.nativeId ?? 0;
    WindowInfo? currentWindow;
    for (final window in windows) {
      if (window.id == windowId) {
        currentWindow = window;
        break;
      }
    }

    if (currentWindow == null ||
        !currentWindow.isVisible ||
        !currentWindow.isOnScreen ||
        currentWindow.bounds.width <= 20 ||
        currentWindow.bounds.height <= 20) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.unavailable,
          message: messages.windowCaptureFailed,
          recoverySuggestion: messages.refreshWindowList,
          cause: {'windowId': windowId, 'reason': 'stale'},
        ),
      );
    }

    if (!windowBoundsStillMatch(target.boundsLogical, currentWindow.bounds)) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.unavailable,
          message: messages.windowCaptureFailed,
          recoverySuggestion: messages.refreshWindowList,
          cause: {
            'windowId': windowId,
            'reason': 'boundsChanged',
            'selectedBounds': target.boundsLogical.toString(),
            'currentBounds': currentWindow.bounds.toString(),
          },
        ),
      );
    }

    if (target.displayId != null &&
        currentWindow.displayId != null &&
        target.displayId != currentWindow.displayId) {
      return AppResult.failure(
        AppFailure(
          code: AppFailureCode.unavailable,
          message: messages.windowCaptureFailed,
          recoverySuggestion: messages.refreshWindowList,
          cause: {
            'windowId': windowId,
            'reason': 'displayChanged',
            'selectedDisplayId': target.displayId,
            'currentDisplayId': currentWindow.displayId,
          },
        ),
      );
    }

    final virtualBounds = unionRects(
      displays.map((display) => display.bounds),
    );
    return AppResult.success(
      windowTargetFromInfo(currentWindow, displays, virtualBounds),
    );
  }

  CaptureTargetDescriptor windowTargetFromInfo(
    WindowInfo window,
    List<DisplayInfo> displays,
    Rect virtualBounds,
  ) {
    final display = displayForWindow(window, displays);
    final scaleFactor = display?.scaleFactor ?? 1;
    return CaptureTargetDescriptor.window(
      windowId: window.id,
      title: window.title,
      appName: window.appName,
      boundsLogical: window.bounds,
      displayId: window.displayId ?? display?.id,
      scaleFactor: scaleFactor,
      displayBoundsLogical: display?.bounds,
      virtualScreenBoundsLogical: virtualBounds,
      thumbnailBytes: window.thumbnailBytes,
      appIconBytes: window.appIconBytes,
    );
  }

  DisplayInfo? displayForWindow(
    WindowInfo window,
    List<DisplayInfo> displays,
  ) {
    for (final display in displays) {
      if (window.displayId != null && display.id == window.displayId) {
        return display;
      }
    }
    for (final display in displays) {
      if (display.bounds.contains(window.bounds.center) ||
          display.bounds.overlaps(window.bounds)) {
        return display;
      }
    }
    return displays.isEmpty ? null : displays.first;
  }

  bool windowBoundsStillMatch(Rect selected, Rect current) {
    const tolerance = 8.0;
    return (selected.left - current.left).abs() <= tolerance &&
        (selected.top - current.top).abs() <= tolerance &&
        (selected.width - current.width).abs() <= tolerance &&
        (selected.height - current.height).abs() <= tolerance;
  }
}
