import 'dart:typed_data';

import 'package:flutter/material.dart';

enum CaptureTargetType { display, window, region }

enum CaptureCoordinateSpace {
  displayLogical,
  virtualLogical,
  displayPhysical,
  virtualPhysical;

  static CaptureCoordinateSpace fromStorage(Object? value) {
    return CaptureCoordinateSpace.values.firstWhere(
      (space) => space.name == value,
      orElse: () => CaptureCoordinateSpace.displayLogical,
    );
  }
}

class CaptureRegionSelection {
  final Rect rect;
  final Size sourceSize;
  final int? displayId;
  final Rect? displayBoundsLogical;
  final Rect? virtualScreenBoundsLogical;
  final double scaleFactor;
  final CaptureCoordinateSpace coordinateSpace;

  const CaptureRegionSelection({
    required this.rect,
    required this.sourceSize,
    this.displayId,
    this.displayBoundsLogical,
    this.virtualScreenBoundsLogical,
    this.scaleFactor = 1,
    this.coordinateSpace = CaptureCoordinateSpace.displayLogical,
  });

  Rect get normalizedRect {
    return Rect.fromLTRB(
      rect.left < rect.right ? rect.left : rect.right,
      rect.top < rect.bottom ? rect.top : rect.bottom,
      rect.left < rect.right ? rect.right : rect.left,
      rect.top < rect.bottom ? rect.bottom : rect.top,
    );
  }

  CaptureRegionSelection copyWith({
    Rect? rect,
    Size? sourceSize,
    int? displayId,
    bool clearDisplayId = false,
    Rect? displayBoundsLogical,
    bool clearDisplayBoundsLogical = false,
    Rect? virtualScreenBoundsLogical,
    bool clearVirtualScreenBoundsLogical = false,
    double? scaleFactor,
    CaptureCoordinateSpace? coordinateSpace,
  }) {
    return CaptureRegionSelection(
      rect: rect ?? this.rect,
      sourceSize: sourceSize ?? this.sourceSize,
      displayId: clearDisplayId ? null : displayId ?? this.displayId,
      displayBoundsLogical: clearDisplayBoundsLogical
          ? null
          : displayBoundsLogical ?? this.displayBoundsLogical,
      virtualScreenBoundsLogical: clearVirtualScreenBoundsLogical
          ? null
          : virtualScreenBoundsLogical ?? this.virtualScreenBoundsLogical,
      scaleFactor: scaleFactor ?? this.scaleFactor,
      coordinateSpace: coordinateSpace ?? this.coordinateSpace,
    );
  }

  CaptureTargetDescriptor toTargetDescriptor({String title = 'Region'}) {
    return CaptureTargetDescriptor.region(
      boundsLogical: normalizedRect,
      scaleFactor: scaleFactor,
      displayId: displayId,
      displayBoundsLogical: displayBoundsLogical,
      virtualScreenBoundsLogical: virtualScreenBoundsLogical,
      coordinateSpace: coordinateSpace,
      title: title,
    );
  }

  CaptureRegionCropPlan? toFullscreenFallbackCropPlan({
    String targetTitle = 'Region',
  }) {
    final rect = normalizedRect;
    switch (coordinateSpace) {
      case CaptureCoordinateSpace.displayLogical:
        final displayBounds = displayBoundsLogical;
        final virtualBounds = virtualScreenBoundsLogical;
        if (displayBounds != null &&
            virtualBounds != null &&
            !_rectsNear(displayBounds, virtualBounds)) {
          final displaySource = Rect.fromLTWH(
            0,
            0,
            displayBounds.width,
            displayBounds.height,
          );
          if (!_rectContainsRect(displaySource, rect)) return null;
          final virtualRect = rect.shift(
            Offset(
              displayBounds.left - virtualBounds.left,
              displayBounds.top - virtualBounds.top,
            ),
          );
          return _cropPlan(
            selectionRect: virtualRect,
            sourceSize: virtualBounds.size,
            targetTitle: targetTitle,
          );
        }
        final localSourceSize = _firstPositiveSize(
          sourceSize,
          displayBounds?.size,
        );
        return _cropPlan(
          selectionRect: rect,
          sourceSize: localSourceSize,
          targetTitle: targetTitle,
        );
      case CaptureCoordinateSpace.virtualLogical:
        final virtualBounds = virtualScreenBoundsLogical;
        if (displayBoundsLogical != null &&
            !_rectContainsRect(displayBoundsLogical!, rect)) {
          return null;
        }
        if (virtualBounds != null) {
          return _cropPlan(
            selectionRect: rect.shift(
              Offset(-virtualBounds.left, -virtualBounds.top),
            ),
            sourceSize: virtualBounds.size,
            targetTitle: targetTitle,
          );
        }
        return _cropPlan(
          selectionRect: rect,
          sourceSize: sourceSize,
          targetTitle: targetTitle,
        );
      case CaptureCoordinateSpace.displayPhysical:
        final displayBounds = displayBoundsLogical;
        final physicalSourceSize = _firstPositiveSize(
          sourceSize,
          displayBounds == null
              ? null
              : Size(
                  displayBounds.width * _safeScaleFactor(scaleFactor),
                  displayBounds.height * _safeScaleFactor(scaleFactor),
                ),
        );
        return _cropPlan(
          selectionRect: rect,
          sourceSize: physicalSourceSize,
          targetTitle: targetTitle,
        );
      case CaptureCoordinateSpace.virtualPhysical:
        return _cropPlan(
          selectionRect: rect,
          sourceSize: sourceSize,
          targetTitle: targetTitle,
        );
    }
  }

  CaptureRegionCropPlan? _cropPlan({
    required Rect selectionRect,
    required Size sourceSize,
    required String targetTitle,
  }) {
    if (sourceSize.width <= 0 || sourceSize.height <= 0) return null;
    final sourceBounds = Rect.fromLTWH(
      0,
      0,
      sourceSize.width,
      sourceSize.height,
    );
    if (!_rectContainsRect(sourceBounds, selectionRect)) return null;
    return CaptureRegionCropPlan(
      selectionRect: selectionRect,
      sourceSize: sourceSize,
      target: toTargetDescriptor(title: targetTitle),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'rect': rectToJson(rect),
      'sourceSize': sizeToJson(sourceSize),
      'displayId': displayId,
      'displayBoundsLogical': nullableRectToJson(displayBoundsLogical),
      'virtualScreenBoundsLogical': nullableRectToJson(
        virtualScreenBoundsLogical,
      ),
      'scaleFactor': scaleFactor,
      'coordinateSpace': coordinateSpace.name,
    };
  }

  factory CaptureRegionSelection.fromJson(Map<dynamic, dynamic> json) {
    return CaptureRegionSelection(
      rect: rectFromJson(json['rect']),
      sourceSize: sizeFromJson(json['sourceSize']),
      displayId: (json['displayId'] as num?)?.toInt(),
      displayBoundsLogical: nullableRectFromJson(json['displayBoundsLogical']),
      virtualScreenBoundsLogical: nullableRectFromJson(
        json['virtualScreenBoundsLogical'],
      ),
      scaleFactor: _safeScaleFactor(
        (json['scaleFactor'] as num?)?.toDouble() ?? 1,
      ),
      coordinateSpace: CaptureCoordinateSpace.fromStorage(
        json['coordinateSpace'],
      ),
    );
  }
}

class CaptureRegionCropPlan {
  final Rect selectionRect;
  final Size sourceSize;
  final CaptureTargetDescriptor target;

  const CaptureRegionCropPlan({
    required this.selectionRect,
    required this.sourceSize,
    required this.target,
  });
}

class CaptureTargetDescriptor {
  final String id;
  final CaptureTargetType type;
  final String title;
  final String? appName;
  final Rect boundsLogical;
  final Rect boundsPhysical;
  final int? displayId;
  final double scaleFactor;
  final bool supportsShadowToggle;
  final bool supportsTransparency;
  final int? nativeId;
  final Rect? displayBoundsLogical;
  final Rect? virtualScreenBoundsLogical;
  final CaptureCoordinateSpace coordinateSpace;
  final Uint8List? thumbnailBytes;
  final Uint8List? appIconBytes;

  const CaptureTargetDescriptor({
    required this.id,
    required this.type,
    required this.title,
    this.appName,
    required this.boundsLogical,
    required this.boundsPhysical,
    this.displayId,
    this.scaleFactor = 1,
    this.supportsShadowToggle = false,
    this.supportsTransparency = false,
    this.nativeId,
    this.displayBoundsLogical,
    this.virtualScreenBoundsLogical,
    this.coordinateSpace = CaptureCoordinateSpace.displayLogical,
    this.thumbnailBytes,
    this.appIconBytes,
  });

  factory CaptureTargetDescriptor.display({
    required int displayId,
    required String title,
    required Rect boundsLogical,
    required double scaleFactor,
    Rect? virtualScreenBoundsLogical,
    CaptureCoordinateSpace coordinateSpace =
        CaptureCoordinateSpace.virtualLogical,
    Uint8List? thumbnailBytes,
    Uint8List? appIconBytes,
  }) {
    final safeScale = _safeScaleFactor(scaleFactor);
    return CaptureTargetDescriptor(
      id: 'display:$displayId',
      type: CaptureTargetType.display,
      title: title,
      boundsLogical: boundsLogical,
      boundsPhysical: _physicalRect(boundsLogical, safeScale),
      displayId: displayId,
      scaleFactor: safeScale,
      nativeId: displayId,
      displayBoundsLogical: boundsLogical,
      virtualScreenBoundsLogical: virtualScreenBoundsLogical,
      coordinateSpace: coordinateSpace,
      thumbnailBytes: thumbnailBytes,
      appIconBytes: appIconBytes,
    );
  }

  factory CaptureTargetDescriptor.window({
    required int windowId,
    required String title,
    required String appName,
    required Rect boundsLogical,
    required double scaleFactor,
    int? displayId,
    Rect? displayBoundsLogical,
    Rect? virtualScreenBoundsLogical,
    CaptureCoordinateSpace coordinateSpace =
        CaptureCoordinateSpace.virtualLogical,
    Uint8List? thumbnailBytes,
    Uint8List? appIconBytes,
  }) {
    final safeScale = _safeScaleFactor(scaleFactor);
    return CaptureTargetDescriptor(
      id: 'window:$windowId',
      type: CaptureTargetType.window,
      title: title.isEmpty ? appName : title,
      appName: appName,
      boundsLogical: boundsLogical,
      boundsPhysical: _physicalRect(boundsLogical, safeScale),
      displayId: displayId,
      scaleFactor: safeScale,
      supportsShadowToggle: true,
      supportsTransparency: true,
      nativeId: windowId,
      displayBoundsLogical: displayBoundsLogical,
      virtualScreenBoundsLogical: virtualScreenBoundsLogical,
      coordinateSpace: coordinateSpace,
      thumbnailBytes: thumbnailBytes,
      appIconBytes: appIconBytes,
    );
  }

  factory CaptureTargetDescriptor.region({
    required Rect boundsLogical,
    required double scaleFactor,
    int? displayId,
    Rect? displayBoundsLogical,
    Rect? virtualScreenBoundsLogical,
    CaptureCoordinateSpace coordinateSpace =
        CaptureCoordinateSpace.displayLogical,
    String title = 'Region',
  }) {
    final safeScale = _safeScaleFactor(scaleFactor);
    return CaptureTargetDescriptor(
      id:
          'region:${boundsLogical.left},${boundsLogical.top},'
          '${boundsLogical.width},${boundsLogical.height}',
      type: CaptureTargetType.region,
      title: title,
      boundsLogical: boundsLogical,
      boundsPhysical: _physicalRect(boundsLogical, safeScale),
      displayId: displayId,
      scaleFactor: safeScale,
      displayBoundsLogical: displayBoundsLogical,
      virtualScreenBoundsLogical: virtualScreenBoundsLogical,
      coordinateSpace: coordinateSpace,
    );
  }

  CaptureTargetDescriptor copyWith({
    String? id,
    CaptureTargetType? type,
    String? title,
    String? appName,
    Rect? boundsLogical,
    Rect? boundsPhysical,
    int? displayId,
    double? scaleFactor,
    bool? supportsShadowToggle,
    bool? supportsTransparency,
    int? nativeId,
    Rect? displayBoundsLogical,
    Rect? virtualScreenBoundsLogical,
    CaptureCoordinateSpace? coordinateSpace,
    Uint8List? thumbnailBytes,
    bool clearThumbnailBytes = false,
    Uint8List? appIconBytes,
    bool clearAppIconBytes = false,
  }) {
    return CaptureTargetDescriptor(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      appName: appName ?? this.appName,
      boundsLogical: boundsLogical ?? this.boundsLogical,
      boundsPhysical: boundsPhysical ?? this.boundsPhysical,
      displayId: displayId ?? this.displayId,
      scaleFactor: scaleFactor ?? this.scaleFactor,
      supportsShadowToggle: supportsShadowToggle ?? this.supportsShadowToggle,
      supportsTransparency: supportsTransparency ?? this.supportsTransparency,
      nativeId: nativeId ?? this.nativeId,
      displayBoundsLogical: displayBoundsLogical ?? this.displayBoundsLogical,
      virtualScreenBoundsLogical:
          virtualScreenBoundsLogical ?? this.virtualScreenBoundsLogical,
      coordinateSpace: coordinateSpace ?? this.coordinateSpace,
      thumbnailBytes: clearThumbnailBytes
          ? null
          : thumbnailBytes ?? this.thumbnailBytes,
      appIconBytes: clearAppIconBytes
          ? null
          : appIconBytes ?? this.appIconBytes,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'appName': appName,
      'boundsLogical': rectToJson(boundsLogical),
      'boundsPhysical': rectToJson(boundsPhysical),
      'displayId': displayId,
      'scaleFactor': scaleFactor,
      'supportsShadowToggle': supportsShadowToggle,
      'supportsTransparency': supportsTransparency,
      'nativeId': nativeId,
      'displayBoundsLogical': nullableRectToJson(displayBoundsLogical),
      'virtualScreenBoundsLogical': nullableRectToJson(
        virtualScreenBoundsLogical,
      ),
      'coordinateSpace': coordinateSpace.name,
      'thumbnailBytes': bytesToJson(thumbnailBytes),
      'appIconBytes': bytesToJson(appIconBytes),
    };
  }

  factory CaptureTargetDescriptor.fromJson(Map<String, dynamic> json) {
    return CaptureTargetDescriptor(
      id: json['id'] as String? ?? '',
      type: CaptureTargetType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => CaptureTargetType.region,
      ),
      title: json['title'] as String? ?? '',
      appName: json['appName'] as String?,
      boundsLogical: rectFromJson(json['boundsLogical']),
      boundsPhysical: rectFromJson(json['boundsPhysical']),
      displayId: (json['displayId'] as num?)?.toInt(),
      scaleFactor: _safeScaleFactor(
        (json['scaleFactor'] as num?)?.toDouble() ?? 1,
      ),
      supportsShadowToggle: json['supportsShadowToggle'] as bool? ?? false,
      supportsTransparency: json['supportsTransparency'] as bool? ?? false,
      nativeId: (json['nativeId'] as num?)?.toInt(),
      displayBoundsLogical: nullableRectFromJson(json['displayBoundsLogical']),
      virtualScreenBoundsLogical: nullableRectFromJson(
        json['virtualScreenBoundsLogical'],
      ),
      coordinateSpace: CaptureCoordinateSpace.fromStorage(
        json['coordinateSpace'],
      ),
      thumbnailBytes: bytesFromJson(json['thumbnailBytes']),
      appIconBytes: bytesFromJson(json['appIconBytes']),
    );
  }
}

class FullscreenCaptureOptions {
  final int? selectedDisplayId;
  final bool rememberLastDisplay;

  const FullscreenCaptureOptions({
    this.selectedDisplayId,
    this.rememberLastDisplay = true,
  });

  Map<String, Object?> toJson() {
    return {
      'selectedDisplayId': selectedDisplayId,
      'rememberLastDisplay': rememberLastDisplay,
    };
  }
}

class WindowCaptureOptions {
  final bool includeShadow;
  final bool keepTransparentBackground;
  final Color? replacementBackgroundColor;

  const WindowCaptureOptions({
    this.includeShadow = true,
    this.keepTransparentBackground = true,
    this.replacementBackgroundColor,
  });

  WindowCaptureOptions copyWith({
    bool? includeShadow,
    bool? keepTransparentBackground,
    Color? replacementBackgroundColor,
    bool clearReplacementBackgroundColor = false,
  }) {
    return WindowCaptureOptions(
      includeShadow: includeShadow ?? this.includeShadow,
      keepTransparentBackground:
          keepTransparentBackground ?? this.keepTransparentBackground,
      replacementBackgroundColor: clearReplacementBackgroundColor
          ? null
          : replacementBackgroundColor ?? this.replacementBackgroundColor,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'includeShadow': includeShadow,
      'keepTransparentBackground': keepTransparentBackground,
      'replacementBackgroundColor': replacementBackgroundColor?.toARGB32(),
    };
  }

  factory WindowCaptureOptions.fromJson(Map<String, dynamic> json) {
    final colorValue = (json['replacementBackgroundColor'] as num?)?.toInt();
    return WindowCaptureOptions(
      includeShadow: json['includeShadow'] as bool? ?? true,
      keepTransparentBackground:
          json['keepTransparentBackground'] as bool? ?? true,
      replacementBackgroundColor: colorValue == null ? null : Color(colorValue),
    );
  }
}

class CaptureTargetResolver {
  const CaptureTargetResolver();

  CaptureTargetDescriptor? targetAtPosition(
    Offset position,
    Iterable<CaptureTargetDescriptor> targets,
  ) {
    for (final target in targets) {
      if (target.boundsLogical.contains(position)) {
        return target;
      }
    }
    return null;
  }

  CaptureTargetDescriptor? displayForTarget(
    CaptureTargetDescriptor target,
    Iterable<CaptureTargetDescriptor> displays,
  ) {
    final displayId = target.displayId;
    if (displayId != null) {
      for (final display in displays) {
        if (display.type == CaptureTargetType.display &&
            display.displayId == displayId) {
          return display;
        }
      }
    }
    for (final display in displays) {
      if (display.type != CaptureTargetType.display) continue;
      if (display.boundsLogical.overlaps(target.boundsLogical) ||
          display.boundsLogical.contains(target.boundsLogical.center)) {
        return display;
      }
    }
    return null;
  }
}

Rect unionRects(Iterable<Rect> rects) {
  final iterator = rects.iterator;
  if (!iterator.moveNext()) return Rect.zero;
  var result = iterator.current;
  while (iterator.moveNext()) {
    result = result.expandToInclude(iterator.current);
  }
  return result;
}

Map<String, Object?> rectToJson(Rect rect) {
  return {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
  };
}

Map<String, Object?> sizeToJson(Size size) {
  return {'width': size.width, 'height': size.height};
}

Map<String, Object?>? nullableRectToJson(Rect? rect) {
  return rect == null ? null : rectToJson(rect);
}

Rect rectFromJson(Object? raw) {
  if (raw is! Map) return Rect.zero;
  final map = raw.cast<dynamic, dynamic>();
  return Rect.fromLTWH(
    (map['left'] as num?)?.toDouble() ?? (map['x'] as num?)?.toDouble() ?? 0,
    (map['top'] as num?)?.toDouble() ?? (map['y'] as num?)?.toDouble() ?? 0,
    (map['width'] as num?)?.toDouble() ?? 0,
    (map['height'] as num?)?.toDouble() ?? 0,
  );
}

Rect? nullableRectFromJson(Object? raw) {
  if (raw == null) return null;
  return rectFromJson(raw);
}

Size sizeFromJson(Object? raw) {
  if (raw is! Map) return Size.zero;
  final map = raw.cast<dynamic, dynamic>();
  return Size(
    (map['width'] as num?)?.toDouble() ?? 0,
    (map['height'] as num?)?.toDouble() ?? 0,
  );
}

List<int>? bytesToJson(Uint8List? bytes) {
  return bytes == null ? null : List<int>.from(bytes);
}

Uint8List? bytesFromJson(Object? raw) {
  if (raw is Uint8List) return raw;
  if (raw is List) {
    final bytes = <int>[];
    for (final item in raw) {
      if (item is! num) return null;
      final byte = item.toInt();
      if (byte < 0 || byte > 255) return null;
      bytes.add(byte);
    }
    return Uint8List.fromList(bytes);
  }
  return null;
}

Size _firstPositiveSize(Size first, Size? second) {
  if (first.width > 0 && first.height > 0) return first;
  if (second != null && second.width > 0 && second.height > 0) return second;
  return Size.zero;
}

Rect _physicalRect(Rect logical, double scaleFactor) {
  return Rect.fromLTWH(
    logical.left * scaleFactor,
    logical.top * scaleFactor,
    logical.width * scaleFactor,
    logical.height * scaleFactor,
  );
}

double _safeScaleFactor(double scaleFactor) {
  return !scaleFactor.isFinite || scaleFactor <= 0 ? 1.0 : scaleFactor;
}

bool _rectContainsRect(Rect outer, Rect inner) {
  const tolerance = 0.5;
  return inner.left >= outer.left - tolerance &&
      inner.top >= outer.top - tolerance &&
      inner.right <= outer.right + tolerance &&
      inner.bottom <= outer.bottom + tolerance;
}

bool _rectsNear(Rect first, Rect second) {
  const tolerance = 1.0;
  return (first.left - second.left).abs() <= tolerance &&
      (first.top - second.top).abs() <= tolerance &&
      (first.width - second.width).abs() <= tolerance &&
      (first.height - second.height).abs() <= tolerance;
}
