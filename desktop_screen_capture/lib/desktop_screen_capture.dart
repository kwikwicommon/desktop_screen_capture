library desktop_screen_capture;

export 'package:desktop_screen_capture_platform_interface/desktop_screen_capture_platform_interface.dart'
    show
        DesktopCapabilitySnapshot,
        DesktopFeatureAvailability,
        DesktopFeatureAvailabilityStatus,
        DesktopFeatureKey,
        DesktopPermissionInfo,
        DesktopPermissionState,
        DesktopPermissionType;

export 'src/app_error.dart';
export 'src/capture_image_encoding_service.dart';
export 'src/capture_image_utils.dart';
export 'src/capture_messages.dart';
export 'src/capture_region_resolver.dart';
export 'src/capture_service.dart';
export 'src/capture_service_impl.dart';
export 'src/capture_target.dart';
export 'src/native_service.dart';
export 'src/window_target_validator.dart';
