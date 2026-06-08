# desktop_screen_capture

`desktop_screen_capture` 是桌面截图能力的父包，提供截图接口、数据模型、多显示器坐标转换、窗口目标校验、图片裁剪和编码入口。平台原生能力由 `desktop_screen_capture_macos` 和 `desktop_screen_capture_windows` 子包提供。

## 安装

在宿主应用中依赖父包，并按目标平台依赖对应子包：

```yaml
dependencies:
  desktop_screen_capture:
    path: packages/desktop_screen_capture
  desktop_screen_capture_macos:
    path: packages/desktop_screen_capture/desktop_screen_capture_macos
  desktop_screen_capture_windows:
    path: packages/desktop_screen_capture/desktop_screen_capture_windows
```

## 初始化

可以直接注册默认 MethodChannel 服务：

```dart
import 'package:desktop_screen_capture/desktop_screen_capture.dart';

void configureCapture() {
  DesktopScreenCapture.registerWith(
    () => CaptureServiceImpl(
      nativeService: const MethodChannelDesktopNativeService(),
    ),
  );
}
```

如果宿主应用使用 GetX，可以将同一个服务注册到容器：

```dart
import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:get/get.dart';

void registerCaptureBinding() {
  Get.lazyPut<CaptureService>(
    () => CaptureServiceImpl(
      nativeService: const MethodChannelDesktopNativeService(),
    ),
    fenix: true,
  );
}
```

## 基本使用

```dart
import 'package:desktop_screen_capture/desktop_screen_capture.dart';
import 'package:flutter/widgets.dart';

Future<void> captureRegion() async {
  final capture = DesktopScreenCapture.instance;
  final result = await capture.captureRegion(
    const Rect.fromLTWH(0, 0, 640, 360),
  );
  if (result.isFailure) {
    throw StateError(result.requireFailure.toString());
  }
  final bytes = result.requireValue.imageBytes;
  debugPrint('Captured ${bytes.length} bytes.');
}
```

## 错误文案

父包不依赖宿主应用的 i18n。需要本地化错误文案时，注入 `CaptureMessages`：

```dart
final service = CaptureServiceImpl(
  nativeService: const MethodChannelDesktopNativeService(),
  messages: const CaptureMessages(
    screenCaptureFailed: 'Screen capture failed.',
  ),
);
```
