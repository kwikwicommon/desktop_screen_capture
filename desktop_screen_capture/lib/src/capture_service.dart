import 'dart:typed_data';

import 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart';
import 'package:flutter/material.dart';

import 'app_error.dart';
import 'capture_target.dart';
import 'native_service.dart';

enum CaptureMode { region, fullscreen, window, scrolling }

enum CaptureOutputFormat {
  png,
  jpeg,
  webp;

  static CaptureOutputFormat fromStorage(Object? value) {
    return CaptureOutputFormat.values.firstWhere(
      (format) => format.name == value,
      orElse: () => CaptureOutputFormat.png,
    );
  }
}

class CaptureResult {
  final Uint8List imageBytes;
  final Size size;
  final DateTime capturedAt;
  final String? sourcePath;
  final bool isTemporary;
  final int? displayId;
  final int? windowId;
  final double scaleFactor;
  final CaptureTargetDescriptor? target;
  final WindowCaptureOptions? windowOptions;
  final CaptureMode captureMode;

  CaptureResult({
    required this.imageBytes,
    required this.size,
    DateTime? capturedAt,
    this.sourcePath,
    this.isTemporary = false,
    this.displayId,
    this.windowId,
    this.scaleFactor = 1,
    this.target,
    this.windowOptions,
    this.captureMode = CaptureMode.region,
  }) : capturedAt = capturedAt ?? DateTime.now();
}

class CaptureFallbackDiagnostic {
  final String operation;
  final AppFailure failure;
  final String fallbackPath;
  final DateTime createdAt;

  CaptureFallbackDiagnostic({
    required this.operation,
    required this.failure,
    required this.fallbackPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

abstract class CaptureService {
  AppFailure? get lastFailure;

  CaptureFallbackDiagnostic? get lastFallbackDiagnostic;

  Future<AppResult<CaptureRegionSelection>> selectNativeRegion();

  Future<AppResult<CaptureResult>> captureRegion(
    Rect region, {
    Size? sourceSize,
    int? displayId,
    Rect? displayBoundsLogical,
    Rect? virtualScreenBoundsLogical,
    double? scaleFactor,
    CaptureCoordinateSpace coordinateSpace =
        CaptureCoordinateSpace.displayLogical,
  });

  Future<AppResult<CaptureResult>> captureFullscreen({int displayId = 0});

  Future<AppResult<CaptureResult>> captureDisplay(
    CaptureTargetDescriptor target, {
    FullscreenCaptureOptions options = const FullscreenCaptureOptions(),
  });

  Future<AppResult<CaptureResult>> captureWindow(
    CaptureTargetDescriptor target, {
    WindowCaptureOptions options = const WindowCaptureOptions(),
  });

  Future<AppResult<List<DisplayInfo>>> getDisplays();

  Future<AppResult<List<WindowInfo>>> getWindows();

  Future<AppResult<List<CaptureTargetDescriptor>>> listDisplayTargets();

  Future<AppResult<List<CaptureTargetDescriptor>>> listWindowTargets();
}

class DisplayInfo {
  final int id;
  final String name;
  final Rect bounds;
  final double scaleFactor;
  final bool isPrimary;
  final bool isInternal;

  const DisplayInfo({
    required this.id,
    required this.name,
    required this.bounds,
    required this.scaleFactor,
    this.isPrimary = false,
    this.isInternal = false,
  });
}

class WindowInfo {
  final int id;
  final String title;
  final String appName;
  final Rect bounds;
  final int? displayId;
  final bool isVisible;
  final bool isOnScreen;
  final Uint8List? thumbnailBytes;
  final Uint8List? appIconBytes;

  const WindowInfo({
    required this.id,
    required this.title,
    required this.appName,
    required this.bounds,
    this.displayId,
    this.isVisible = true,
    this.isOnScreen = true,
    this.thumbnailBytes,
    this.appIconBytes,
  });
}

typedef CaptureServiceFactory = CaptureService Function();

class DesktopScreenCapture {
  static CaptureServiceFactory? _factory;

  DesktopScreenCapture._();

  static void registerWith(CaptureServiceFactory factory) {
    _factory = factory;
  }

  static CaptureService get instance {
    final factory = _factory;
    if (factory == null) {
      throw StateError('DesktopScreenCapture has not been registered.');
    }
    return factory();
  }

  static Future<AppResult<DesktopCapabilitySnapshot>> queryCapabilities({
    DesktopScreenCapturePlatform? platform,
  }) {
    return PlatformDesktopCaptureNativeService(
      platform: platform,
    ).queryCapabilities();
  }

  static Future<AppResult<DesktopPermissionInfo>> requestPermission(
    DesktopPermissionType permissionType, {
    DesktopScreenCapturePlatform? platform,
  }) {
    return PlatformDesktopCaptureNativeService(
      platform: platform,
    ).requestPermission(permissionType);
  }
}
