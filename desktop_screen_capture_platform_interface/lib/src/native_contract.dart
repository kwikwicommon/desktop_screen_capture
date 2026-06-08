import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

class DesktopNativeMethod {
  static const listDisplays = 'capture.listDisplays';
  static const listWindows = 'capture.listWindows';
  static const captureDisplay = 'capture.captureDisplay';
  static const captureWindow = 'capture.captureWindow';
  static const captureRegion = 'capture.captureRegion';
  static const selectRegion = 'capture.selectRegion';
  static const encodeImage = 'capture.encodeImage';
  static const queryCapabilities = 'capability.queryPermissions';
  static const queryPermissions = queryCapabilities;
  static const requestPermission = 'capability.requestPermission';
}

enum DesktopPermissionType {
  screenRecording,
  microphone,
  camera,
  accessibility,
  fileSystem,
  systemAudio,
}

enum DesktopPermissionState {
  granted,
  denied,
  notDetermined,
  restricted,
  requiresRestart,
  unsupported,
}

enum DesktopFeatureKey {
  displayEnumeration,
  windowEnumeration,
  captureDisplay,
  captureWindow,
  captureRegion,
  imageEncoding,
  nativeRegionSelection,
}

enum DesktopFeatureAvailabilityStatus {
  implemented,
  available,
  requiresPermission,
  requiresDependency,
  degraded,
  notImplemented,
  permissionRequired,
  unsupported,
  notConfigured,
}

enum NativeFailureRecoverability {
  retryable,
  userActionRequired,
  notRecoverable,
  unknown,
}

class NativeFailureEnvelope {
  final String status;
  final String domain;
  final String nativeCode;
  final NativeFailureRecoverability recoverability;
  final String artifactPath;
  final bool requiresRestart;
  final Object? details;

  const NativeFailureEnvelope({
    required this.status,
    this.domain = '',
    this.nativeCode = '',
    this.recoverability = NativeFailureRecoverability.unknown,
    this.artifactPath = '',
    this.requiresRestart = false,
    this.details,
  });

  factory NativeFailureEnvelope.fromMap({
    required String status,
    required Map<dynamic, dynamic> map,
  }) {
    return NativeFailureEnvelope(
      status: status,
      domain: _optionalString(map['domain']),
      nativeCode: _optionalString(map['nativeCode']),
      recoverability: nativeFailureRecoverabilityFromName(
        _optionalString(map['recoverability']),
      ),
      artifactPath: _optionalString(map['artifactPath']),
      requiresRestart: map['requiresRestart'] == true,
      details: map['details'],
    );
  }

  Map<String, Object?> toMap() {
    return {
      'status': status,
      'domain': domain,
      'nativeCode': nativeCode,
      'recoverability': recoverability.name,
      'artifactPath': artifactPath,
      'requiresRestart': requiresRestart,
      'details': details,
    };
  }
}

class DesktopPermissionInfo {
  final DesktopPermissionType type;
  final DesktopPermissionState state;
  final String message;
  final bool requiresRestart;

  const DesktopPermissionInfo({
    required this.type,
    required this.state,
    this.message = '',
    this.requiresRestart = false,
  });

  factory DesktopPermissionInfo.fromMap(Map<dynamic, dynamic> map) {
    return DesktopPermissionInfo(
      type: _readPermissionType(map['type'], 'type'),
      state: _readPermissionState(map['state'], 'state'),
      message: _optionalString(map['message']),
      requiresRestart: map['requiresRestart'] == true,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'type': type.name,
      'state': state.name,
      'message': message,
      'requiresRestart': requiresRestart,
    };
  }
}

class DesktopFeatureAvailability {
  final DesktopFeatureKey feature;
  final DesktopFeatureAvailabilityStatus status;
  final String message;
  final DesktopPermissionType? permissionType;

  const DesktopFeatureAvailability({
    required this.feature,
    required this.status,
    this.message = '',
    this.permissionType,
  });

  factory DesktopFeatureAvailability.fromMap(Map<dynamic, dynamic> map) {
    final permissionTypeName = _nullableString(map['permissionType']);
    return DesktopFeatureAvailability(
      feature: _readFeatureKey(map['feature'], 'feature'),
      status: _readFeatureAvailabilityStatus(map['status'], 'status'),
      message: _optionalString(map['message']),
      permissionType: permissionTypeName == null
          ? null
          : _readPermissionType(permissionTypeName, 'permissionType'),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'feature': feature.name,
      'status': status.name,
      'message': message,
      'permissionType': permissionType?.name,
    };
  }
}

class DesktopCapabilitySnapshot {
  final Map<DesktopPermissionType, DesktopPermissionInfo> permissions;
  final Map<DesktopFeatureKey, DesktopFeatureAvailability> features;

  const DesktopCapabilitySnapshot({
    required this.permissions,
    required this.features,
  });

  factory DesktopCapabilitySnapshot.fromMap(Map<dynamic, dynamic> map) {
    final permissions = <DesktopPermissionType, DesktopPermissionInfo>{};
    final features = <DesktopFeatureKey, DesktopFeatureAvailability>{};

    final permissionList = _readMapList(map['permissions'], 'permissions');
    for (final entry in permissionList) {
      final item = DesktopPermissionInfo.fromMap(entry);
      permissions[item.type] = item;
    }

    final featureList = _readMapList(map['features'], 'features');
    for (final entry in featureList) {
      final item = DesktopFeatureAvailability.fromMap(entry);
      features[item.feature] = item;
    }

    return DesktopCapabilitySnapshot(
      permissions: permissions,
      features: features,
    );
  }
}

class NativeDisplay {
  final int id;
  final String name;
  final Rect bounds;
  final double scaleFactor;
  final bool isPrimary;
  final bool isInternal;

  const NativeDisplay({
    required this.id,
    required this.name,
    required this.bounds,
    required this.scaleFactor,
    this.isPrimary = false,
    this.isInternal = false,
  });

  factory NativeDisplay.fromMap(Map<dynamic, dynamic> map) {
    return NativeDisplay(
      id: _readRequiredInt(map['id'], 'id'),
      name: _optionalString(map['name'], fallback: 'Display'),
      bounds: _readRect(map['bounds'], 'bounds', requirePositiveSize: true),
      scaleFactor: _readPositiveDouble(
        map['scaleFactor'],
        'scaleFactor',
        fallback: 1,
      ),
      isPrimary: map['isPrimary'] as bool? ?? false,
      isInternal: map['isInternal'] as bool? ?? false,
    );
  }
}

class NativeWindow {
  final int id;
  final String title;
  final String appName;
  final Rect bounds;
  final int? displayId;
  final bool isVisible;
  final bool isOnScreen;
  final Uint8List? thumbnailBytes;
  final Uint8List? appIconBytes;

  const NativeWindow({
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

  factory NativeWindow.fromMap(Map<dynamic, dynamic> map) {
    return NativeWindow(
      id: _readRequiredInt(map['id'], 'id'),
      title: _optionalString(map['title']),
      appName: _optionalString(map['appName']),
      bounds: _readRect(map['bounds'], 'bounds', requirePositiveSize: true),
      displayId: _readOptionalInt(map['displayId'], 'displayId'),
      isVisible: map['isVisible'] as bool? ?? true,
      isOnScreen: map['isOnScreen'] as bool? ?? true,
      thumbnailBytes: readNullableBytes(map['thumbnail']),
      appIconBytes: readNullableBytes(map['appIcon']),
    );
  }
}

class NativeRegionSelection {
  final Rect rect;
  final Size sourceSize;
  final int? displayId;
  final Rect? displayBoundsLogical;
  final Rect? virtualScreenBoundsLogical;
  final double scaleFactor;
  final String coordinateSpace;

  const NativeRegionSelection({
    required this.rect,
    required this.sourceSize,
    this.displayId,
    this.displayBoundsLogical,
    this.virtualScreenBoundsLogical,
    this.scaleFactor = 1,
    this.coordinateSpace = 'displayLogical',
  });

  factory NativeRegionSelection.fromMap(Map<dynamic, dynamic> map) {
    return NativeRegionSelection(
      rect: _readRect(map['rect'], 'rect', requirePositiveSize: true),
      sourceSize: _readPositiveSize(map['sourceSize'], 'sourceSize'),
      displayId: _readOptionalInt(map['displayId'], 'displayId'),
      displayBoundsLogical: _readNullableRect(
        map['displayBoundsLogical'],
        'displayBoundsLogical',
        requirePositiveSize: true,
      ),
      virtualScreenBoundsLogical: _readNullableRect(
        map['virtualScreenBoundsLogical'],
        'virtualScreenBoundsLogical',
        requirePositiveSize: true,
      ),
      scaleFactor: _readPositiveDouble(
        map['scaleFactor'],
        'scaleFactor',
        fallback: 1,
      ),
      coordinateSpace: _readCoordinateSpace(map['coordinateSpace']),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'rect': rectToMap(rect),
      'sourceSize': sizeToMap(sourceSize),
      'displayId': displayId,
      'displayBoundsLogical': displayBoundsLogical == null
          ? null
          : rectToMap(displayBoundsLogical!),
      'virtualScreenBoundsLogical': virtualScreenBoundsLogical == null
          ? null
          : rectToMap(virtualScreenBoundsLogical!),
      'scaleFactor': scaleFactor,
      'coordinateSpace': coordinateSpace,
    };
  }
}

class NativePhysicalRect {
  final int left;
  final int top;
  final int width;
  final int height;

  const NativePhysicalRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory NativePhysicalRect.fromRect(Rect rect) {
    final normalized = Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
    final left = normalized.left.floor();
    final top = normalized.top.floor();
    final right = normalized.right.ceil();
    final bottom = normalized.bottom.ceil();
    return NativePhysicalRect(
      left: left,
      top: top,
      width: math.max(0, right - left),
      height: math.max(0, bottom - top),
    );
  }

  Rect get asRect => Rect.fromLTWH(
    left.toDouble(),
    top.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );

  Map<String, Object?> toMap() {
    return {'left': left, 'top': top, 'width': width, 'height': height};
  }

  factory NativePhysicalRect.fromMap(Map<dynamic, dynamic> map) {
    return NativePhysicalRect(
      left: _readRequiredInt(map['left'], 'left'),
      top: _readRequiredInt(map['top'], 'top'),
      width: _readPositiveInt(map['width'], 'width'),
      height: _readPositiveInt(map['height'], 'height'),
    );
  }
}

class NativeCaptureRequest {
  final int? displayId;
  final int? windowId;
  final NativePhysicalRect? region;
  final Rect? expectedWindowBoundsLogical;
  final int? expectedDisplayId;
  final bool includeShadow;
  final bool keepTransparentBackground;
  final int? replacementBackgroundColor;

  const NativeCaptureRequest({
    this.displayId,
    this.windowId,
    this.region,
    this.expectedWindowBoundsLogical,
    this.expectedDisplayId,
    this.includeShadow = true,
    this.keepTransparentBackground = true,
    this.replacementBackgroundColor,
  });

  Map<String, Object?> toMap() {
    return {
      'displayId': displayId,
      'windowId': windowId,
      'region': region?.toMap(),
      'expectedWindowBoundsLogical': expectedWindowBoundsLogical == null
          ? null
          : rectToMap(expectedWindowBoundsLogical!),
      'expectedDisplayId': expectedDisplayId,
      'includeShadow': includeShadow,
      'keepTransparentBackground': keepTransparentBackground,
      'replacementBackgroundColor': replacementBackgroundColor,
    };
  }
}

class NativeImageEncodeRequest {
  final Uint8List imageBytes;
  final String format;
  final int quality;
  final int matteColor;

  const NativeImageEncodeRequest({
    required this.imageBytes,
    required this.format,
    this.quality = 90,
    this.matteColor = 0xFFFFFFFF,
  });

  Map<String, Object?> toMap() {
    return {
      'imageBytes': imageBytes,
      'format': format,
      'quality': quality,
      'matteColor': matteColor,
    };
  }
}

class NativeEncodedImage {
  final Uint8List imageBytes;
  final Size size;
  final String format;
  final String extension;
  final String mimeType;

  const NativeEncodedImage({
    required this.imageBytes,
    required this.size,
    required this.format,
    required this.extension,
    required this.mimeType,
  });

  factory NativeEncodedImage.fromMap(Map<dynamic, dynamic> map) {
    return NativeEncodedImage(
      imageBytes: readBytes(map['imageBytes']),
      size: Size(
        _readPositiveDouble(map['width'], 'width'),
        _readPositiveDouble(map['height'], 'height'),
      ),
      format: map['format'] as String? ?? 'png',
      extension: map['extension'] as String? ?? 'png',
      mimeType: map['mimeType'] as String? ?? 'image/png',
    );
  }
}

class NativeCaptureFrame {
  final Uint8List imageBytes;
  final Size size;
  final int? displayId;
  final int? windowId;
  final double scaleFactor;
  final String? sourcePath;
  final bool isTemporary;

  const NativeCaptureFrame({
    required this.imageBytes,
    required this.size,
    this.displayId,
    this.windowId,
    this.scaleFactor = 1,
    this.sourcePath,
    this.isTemporary = false,
  });

  factory NativeCaptureFrame.fromMap(Map<dynamic, dynamic> map) {
    return NativeCaptureFrame(
      imageBytes: readBytes(map['imageBytes']),
      size: Size(
        _readPositiveDouble(map['width'], 'width'),
        _readPositiveDouble(map['height'], 'height'),
      ),
      displayId: _readOptionalInt(map['displayId'], 'displayId'),
      windowId: _readOptionalInt(map['windowId'], 'windowId'),
      scaleFactor: _readPositiveDouble(
        map['scaleFactor'],
        'scaleFactor',
        fallback: 1,
      ),
      sourcePath: _nullableString(map['sourcePath']),
      isTemporary: map['isTemporary'] as bool? ?? false,
    );
  }
}

Map<String, Object?> rectToMap(Rect rect) {
  return {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
  };
}

Rect rectFromMap(dynamic raw) {
  if (raw is! Map) return Rect.zero;
  final map = raw.cast<dynamic, dynamic>();
  return Rect.fromLTWH(
    (map['x'] as num?)?.toDouble() ?? (map['left'] as num?)?.toDouble() ?? 0,
    (map['y'] as num?)?.toDouble() ?? (map['top'] as num?)?.toDouble() ?? 0,
    (map['width'] as num?)?.toDouble() ?? 0,
    (map['height'] as num?)?.toDouble() ?? 0,
  );
}

Rect? nullableRectFromMap(dynamic raw) {
  if (raw == null) return null;
  return rectFromMap(raw);
}

Map<String, Object?> sizeToMap(Size size) {
  return {'width': size.width, 'height': size.height};
}

Size sizeFromMap(dynamic raw) {
  if (raw is! Map) return Size.zero;
  final map = raw.cast<dynamic, dynamic>();
  return Size(
    (map['width'] as num?)?.toDouble() ?? 0,
    (map['height'] as num?)?.toDouble() ?? 0,
  );
}

Uint8List readBytes(dynamic value) {
  final bytes = readNullableBytes(value);
  if (bytes == null || bytes.isEmpty) {
    throw const FormatException('Expected non-empty image bytes.');
  }
  return bytes;
}

Uint8List? readNullableBytes(dynamic value) {
  if (value == null) return null;
  if (value is Uint8List) return value;
  if (value is ByteBuffer) return value.asUint8List();
  if (value is List) {
    final bytes = <int>[];
    for (final item in value) {
      if (item is! num) return null;
      final byte = item.toInt();
      if (byte < 0 || byte > 255) return null;
      bytes.add(byte);
    }
    return Uint8List.fromList(bytes);
  }
  return null;
}

String _optionalString(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

String? _nullableString(Object? value) {
  return value is String ? value : null;
}

int _readRequiredInt(Object? value, String fieldName) {
  if (value is! num) {
    throw FormatException('Expected numeric $fieldName.');
  }
  final number = value.toDouble();
  if (!number.isFinite) {
    throw FormatException('Expected finite $fieldName.');
  }
  return value.toInt();
}

int? _readOptionalInt(Object? value, String fieldName) {
  if (value == null) return null;
  return _readRequiredInt(value, fieldName);
}

int _readPositiveInt(Object? value, String fieldName) {
  final number = _readRequiredInt(value, fieldName);
  if (number <= 0) {
    throw FormatException('Expected positive $fieldName.');
  }
  return number;
}

double _readPositiveDouble(
  dynamic value,
  String fieldName, {
  double? fallback,
}) {
  if (value == null && fallback != null) return fallback;
  if (value is! num) {
    throw FormatException('Expected numeric $fieldName.');
  }
  final number = value.toDouble();
  if (!number.isFinite || number <= 0) {
    throw FormatException('Expected positive $fieldName.');
  }
  return number;
}

double _readRequiredDouble(Object? value, String fieldName) {
  if (value is! num) {
    throw FormatException('Expected numeric $fieldName.');
  }
  final number = value.toDouble();
  if (!number.isFinite) {
    throw FormatException('Expected finite $fieldName.');
  }
  return number;
}

Rect _readRect(
  Object? value,
  String fieldName, {
  bool requirePositiveSize = false,
}) {
  if (value is! Map) {
    throw FormatException('Expected map $fieldName.');
  }
  final map = value.cast<dynamic, dynamic>();
  final left = _readCoordinate(map['x'] ?? map['left'], '$fieldName.left');
  final top = _readCoordinate(map['y'] ?? map['top'], '$fieldName.top');
  final width = _readRequiredDouble(map['width'], '$fieldName.width');
  final height = _readRequiredDouble(map['height'], '$fieldName.height');
  if (requirePositiveSize && (width <= 0 || height <= 0)) {
    throw FormatException('Expected positive $fieldName size.');
  }
  return Rect.fromLTWH(left, top, width, height);
}

Rect? _readNullableRect(
  Object? value,
  String fieldName, {
  bool requirePositiveSize = false,
}) {
  if (value == null) return null;
  return _readRect(
    value,
    fieldName,
    requirePositiveSize: requirePositiveSize,
  );
}

double _readCoordinate(Object? value, String fieldName) {
  return _readRequiredDouble(value, fieldName);
}

Size _readPositiveSize(Object? value, String fieldName) {
  if (value is! Map) {
    throw FormatException('Expected map $fieldName.');
  }
  final map = value.cast<dynamic, dynamic>();
  final width = _readPositiveDouble(map['width'], '$fieldName.width');
  final height = _readPositiveDouble(map['height'], '$fieldName.height');
  return Size(width, height);
}

List<Map<dynamic, dynamic>> _readMapList(dynamic value, String fieldName) {
  if (value == null) return const <Map<dynamic, dynamic>>[];
  if (value is! List) {
    throw FormatException('Expected list $fieldName.');
  }
  return value.map((entry) {
    if (entry is Map) return entry.cast<dynamic, dynamic>();
    throw FormatException('Expected map entries in $fieldName.');
  }).toList(growable: false);
}

DesktopPermissionType _readPermissionType(Object? value, String fieldName) {
  final name = _requireString(value, fieldName);
  for (final entry in DesktopPermissionType.values) {
    if (entry.name == name) return entry;
  }
  throw FormatException('Unknown $fieldName: $name.');
}

DesktopPermissionState _readPermissionState(Object? value, String fieldName) {
  final name = _requireString(value, fieldName);
  for (final entry in DesktopPermissionState.values) {
    if (entry.name == name) return entry;
  }
  throw FormatException('Unknown $fieldName: $name.');
}

DesktopFeatureKey _readFeatureKey(Object? value, String fieldName) {
  final name = _requireString(value, fieldName);
  for (final entry in DesktopFeatureKey.values) {
    if (entry.name == name) return entry;
  }
  throw FormatException('Unknown $fieldName: $name.');
}

DesktopFeatureAvailabilityStatus _readFeatureAvailabilityStatus(
  Object? value,
  String fieldName,
) {
  final name = _requireString(value, fieldName);
  switch (name) {
    case 'permissionRequired':
    case 'requiresPermission':
      return DesktopFeatureAvailabilityStatus.requiresPermission;
    case 'notConfigured':
    case 'requiresDependency':
      return DesktopFeatureAvailabilityStatus.requiresDependency;
  }
  for (final entry in DesktopFeatureAvailabilityStatus.values) {
    if (entry.name == name) return entry;
  }
  throw FormatException('Unknown $fieldName: $name.');
}

String _readCoordinateSpace(Object? value) {
  final name = _optionalString(value, fallback: 'displayLogical');
  switch (name) {
    case 'displayLogical':
    case 'virtualLogical':
    case 'displayPhysical':
    case 'virtualPhysical':
      return name;
  }
  throw FormatException('Unknown coordinateSpace: $name.');
}

String _requireString(Object? value, String fieldName) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string $fieldName.');
}

DesktopPermissionType permissionTypeFromName(String? name) {
  return DesktopPermissionType.values.firstWhere(
    (value) => value.name == name,
    orElse: () => DesktopPermissionType.screenRecording,
  );
}

DesktopPermissionState permissionStateFromName(String? name) {
  return DesktopPermissionState.values.firstWhere(
    (value) => value.name == name,
    orElse: () => DesktopPermissionState.unsupported,
  );
}

DesktopFeatureKey featureKeyFromName(String? name) {
  return DesktopFeatureKey.values.firstWhere(
    (value) => value.name == name,
    orElse: () => DesktopFeatureKey.captureDisplay,
  );
}

DesktopFeatureAvailabilityStatus featureAvailabilityStatusFromName(
  String? name,
) {
  switch (name) {
    case 'permissionRequired':
      return DesktopFeatureAvailabilityStatus.requiresPermission;
    case 'requiresPermission':
      return DesktopFeatureAvailabilityStatus.requiresPermission;
    case 'notConfigured':
      return DesktopFeatureAvailabilityStatus.requiresDependency;
    case 'requiresDependency':
      return DesktopFeatureAvailabilityStatus.requiresDependency;
  }
  return DesktopFeatureAvailabilityStatus.values.firstWhere(
    (value) => value.name == name,
    orElse: () => DesktopFeatureAvailabilityStatus.unsupported,
  );
}

NativeFailureRecoverability nativeFailureRecoverabilityFromName(String? name) {
  return NativeFailureRecoverability.values.firstWhere(
    (value) => value.name == name,
    orElse: () => NativeFailureRecoverability.unknown,
  );
}
