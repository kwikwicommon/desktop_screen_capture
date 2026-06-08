#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <windowsx.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "capture_engine.h"
#include "display_enumerator.h"

namespace desktop_screen_capture_windows {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodChannel;
using flutter::MethodResult;

EncodableMap PermissionPayload(const std::string& type) {
  EncodableMap payload;
  payload[EncodableValue("type")] = EncodableValue(type);
  const bool supported = type == "screenRecording";
  payload[EncodableValue("state")] =
      EncodableValue(supported ? "granted" : "unsupported");
  payload[EncodableValue("message")] = EncodableValue(
      supported ? "" : "This permission is not managed on Windows.");
  payload[EncodableValue("requiresRestart")] = EncodableValue(false);
  return payload;
}

EncodableMap FeaturePayload(const std::string& feature,
                            const std::string& status = "available",
                            const std::string& message = "") {
  EncodableMap payload;
  payload[EncodableValue("feature")] = EncodableValue(feature);
  payload[EncodableValue("status")] = EncodableValue(status);
  payload[EncodableValue("message")] = EncodableValue(message);
  return payload;
}

EncodableValue CapabilitySnapshot() {
  EncodableList permissions;
  permissions.emplace_back(PermissionPayload("screenRecording"));

  EncodableList features;
  features.emplace_back(FeaturePayload("displayEnumeration"));
  features.emplace_back(FeaturePayload("windowEnumeration"));
  features.emplace_back(FeaturePayload("captureDisplay"));
  features.emplace_back(FeaturePayload("captureWindow"));
  features.emplace_back(FeaturePayload("captureRegion"));
  features.emplace_back(FeaturePayload("imageEncoding"));
  features.emplace_back(FeaturePayload(
      "nativeRegionSelection", "available",
      "Native region selection is available on Windows."));

  EncodableMap payload;
  payload[EncodableValue("permissions")] = EncodableValue(permissions);
  payload[EncodableValue("features")] = EncodableValue(features);
  return MakeSuccess(EncodableValue(payload));
}

std::string PermissionTypeFromArguments(const EncodableMap* arguments) {
  if (arguments == nullptr) {
    return "screenRecording";
  }
  const auto* value = FindMapValue(*arguments, "type");
  if (value == nullptr) {
    return "screenRecording";
  }
  if (const auto* text = std::get_if<std::string>(value)) {
    return *text;
  }
  return "screenRecording";
}

RECT NormalizedRect(POINT first, POINT second) {
  RECT rect = {};
  rect.left = std::min(first.x, second.x);
  rect.top = std::min(first.y, second.y);
  rect.right = std::max(first.x, second.x);
  rect.bottom = std::max(first.y, second.y);
  return rect;
}

flutter::EncodableMap LogicalBoundsPayload(const LogicalRect& rect) {
  flutter::EncodableMap payload;
  payload[EncodableValue("left")] = EncodableValue(rect.left);
  payload[EncodableValue("top")] = EncodableValue(rect.top);
  payload[EncodableValue("width")] = EncodableValue(rect.right - rect.left);
  payload[EncodableValue("height")] = EncodableValue(rect.bottom - rect.top);
  return payload;
}

LogicalRect VirtualLogicalBounds(
    const std::vector<MonitorDescriptor>& monitors) {
  if (monitors.empty()) {
    return LogicalRect{};
  }
  LogicalRect bounds = monitors.front().logical_bounds;
  for (const auto& monitor : monitors) {
    bounds.left = std::min(bounds.left, monitor.logical_bounds.left);
    bounds.top = std::min(bounds.top, monitor.logical_bounds.top);
    bounds.right = std::max(bounds.right, monitor.logical_bounds.right);
    bounds.bottom = std::max(bounds.bottom, monitor.logical_bounds.bottom);
  }
  return bounds;
}

const MonitorDescriptor* MonitorForRect(
    const RECT& rect,
    const std::vector<MonitorDescriptor>& monitors) {
  const HMONITOR handle = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  for (const auto& monitor : monitors) {
    if (monitor.handle == handle) {
      return &monitor;
    }
  }
  return nullptr;
}

bool RectsEqual(const RECT& first, const RECT& second) {
  return first.left == second.left &&
         first.top == second.top &&
         first.right == second.right &&
         first.bottom == second.bottom;
}

struct RegionSelectionContext {
  RECT virtual_bounds = {};
  std::vector<MonitorDescriptor> monitors;
  POINT start = {};
  POINT current = {};
  bool dragging = false;
  bool done = false;
  bool cancelled = false;
};

LRESULT CALLBACK RegionSelectionWindowProc(HWND window,
                                           UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) {
  auto* context = reinterpret_cast<RegionSelectionContext*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return TRUE;
  }
  if (context == nullptr) {
    return DefWindowProcW(window, message, wparam, lparam);
  }

  switch (message) {
    case WM_CLOSE:
      context->cancelled = true;
      context->done = true;
      DestroyWindow(window);
      return 0;
    case WM_SETCURSOR:
      SetCursor(LoadCursorW(nullptr, IDC_CROSS));
      return TRUE;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        context->cancelled = true;
        context->done = true;
        DestroyWindow(window);
        return 0;
      }
      if (wparam == VK_RETURN || wparam == VK_SPACE) {
        const RECT rect = NormalizedRect(context->start, context->current);
        context->cancelled = !RectIsLargeEnough(rect, 5);
        context->done = true;
        DestroyWindow(window);
        return 0;
      }
      break;
    case WM_LBUTTONDOWN:
      context->dragging = true;
      context->start = {
          GET_X_LPARAM(lparam) + context->virtual_bounds.left,
          GET_Y_LPARAM(lparam) + context->virtual_bounds.top,
      };
      context->current = context->start;
      SetCapture(window);
      InvalidateRect(window, nullptr, TRUE);
      return 0;
    case WM_MOUSEMOVE:
      if (context->dragging) {
        context->current = {
            GET_X_LPARAM(lparam) + context->virtual_bounds.left,
            GET_Y_LPARAM(lparam) + context->virtual_bounds.top,
        };
        InvalidateRect(window, nullptr, TRUE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (context->dragging) {
        context->dragging = false;
        context->current = {
            GET_X_LPARAM(lparam) + context->virtual_bounds.left,
            GET_Y_LPARAM(lparam) + context->virtual_bounds.top,
        };
        ReleaseCapture();
        const RECT rect = NormalizedRect(context->start, context->current);
        context->cancelled = !RectIsLargeEnough(rect, 5);
        context->done = true;
        DestroyWindow(window);
      }
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC dc = BeginPaint(window, &paint);
      RECT client = {};
      GetClientRect(window, &client);
      HBRUSH overlay_brush = CreateSolidBrush(RGB(0, 0, 0));
      FillRect(dc, &client, overlay_brush);
      DeleteObject(overlay_brush);

      RECT selected = NormalizedRect(context->start, context->current);
      OffsetRect(&selected, -context->virtual_bounds.left,
                 -context->virtual_bounds.top);
      if (RectIsLargeEnough(selected, 1)) {
        HPEN pen = CreatePen(PS_SOLID, 2, RGB(34, 197, 94));
        HGDIOBJ previous_pen = SelectObject(dc, pen);
        HGDIOBJ previous_brush = SelectObject(dc, GetStockObject(HOLLOW_BRUSH));
        Rectangle(dc, selected.left, selected.top, selected.right,
                  selected.bottom);
        SelectObject(dc, previous_brush);
        SelectObject(dc, previous_pen);
        DeleteObject(pen);
      }
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

bool EnsureRegionSelectionWindowClass(HINSTANCE instance) {
  constexpr wchar_t kClassName[] =
      L"DesktopScreenCaptureRegionSelectionWindow";
  WNDCLASSW existing = {};
  if (GetClassInfoW(instance, kClassName, &existing)) {
    return true;
  }

  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = RegionSelectionWindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursorW(nullptr, IDC_CROSS);
  window_class.hbrBackground =
      reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  return RegisterClassW(&window_class) != 0;
}

EncodableValue RegionSelectionPayload(
    const RECT& selected,
    const MonitorDescriptor& monitor,
    const std::vector<MonitorDescriptor>& monitors) {
  RECT local = selected;
  OffsetRect(&local, -monitor.bounds.left, -monitor.bounds.top);

  EncodableMap rect;
  rect[EncodableValue("left")] = EncodableValue(local.left);
  rect[EncodableValue("top")] = EncodableValue(local.top);
  rect[EncodableValue("width")] = EncodableValue(local.right - local.left);
  rect[EncodableValue("height")] = EncodableValue(local.bottom - local.top);

  EncodableMap source_size;
  source_size[EncodableValue("width")] =
      EncodableValue(monitor.bounds.right - monitor.bounds.left);
  source_size[EncodableValue("height")] =
      EncodableValue(monitor.bounds.bottom - monitor.bounds.top);

  EncodableMap payload;
  payload[EncodableValue("rect")] = EncodableValue(rect);
  payload[EncodableValue("sourceSize")] = EncodableValue(source_size);
  payload[EncodableValue("displayId")] = EncodableValue(monitor.id);
  payload[EncodableValue("displayBoundsLogical")] =
      EncodableValue(LogicalBoundsPayload(monitor.logical_bounds));
  payload[EncodableValue("virtualScreenBoundsLogical")] =
      EncodableValue(LogicalBoundsPayload(VirtualLogicalBounds(monitors)));
  payload[EncodableValue("scaleFactor")] =
      EncodableValue(monitor.scale_factor);
  payload[EncodableValue("coordinateSpace")] =
      EncodableValue("displayPhysical");
  return MakeSuccess(EncodableValue(payload));
}

EncodableValue SelectRegionPayload(const DisplayEnumerator& enumerator) {
  RegionSelectionContext context;
  context.virtual_bounds = VirtualScreenBounds();
  context.monitors = enumerator.EnumerateMonitors();
  if (context.monitors.empty()) {
    return MakeFailure("nativeFailure",
                       "No display is available for region selection.",
                       "Connect a display and try again.");
  }

  HINSTANCE instance = GetModuleHandleW(nullptr);
  if (!EnsureRegionSelectionWindowClass(instance)) {
    return MakeFailure(
        "nativeFailure",
        "The region selection window could not be registered.",
        "Restart the app and try again.");
  }

  constexpr wchar_t kClassName[] =
      L"DesktopScreenCaptureRegionSelectionWindow";
  HWND window = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
      kClassName,
      L"Desktop Screen Capture Region Selection",
      WS_POPUP,
      context.virtual_bounds.left,
      context.virtual_bounds.top,
      context.virtual_bounds.right - context.virtual_bounds.left,
      context.virtual_bounds.bottom - context.virtual_bounds.top,
      nullptr,
      nullptr,
      instance,
      &context);
  if (window == nullptr) {
    return MakeFailure("nativeFailure",
                       "The region selection window could not be opened.",
                       "Try the capture again.");
  }

  SetLayeredWindowAttributes(window, 0, 96, LWA_ALPHA);
  ShowWindow(window, SW_SHOW);
  UpdateWindow(window);
  SetForegroundWindow(window);
  SetFocus(window);

  MSG message = {};
  BOOL message_result = 0;
  while (!context.done &&
         (message_result = GetMessageW(&message, nullptr, 0, 0)) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  if (IsWindow(window)) {
    DestroyWindow(window);
  }

  if (message_result == -1) {
    return MakeFailure("nativeFailure",
                       "The region selection message loop failed.",
                       "Try the capture again.");
  }
  if (message_result == 0) {
    PostQuitMessage(static_cast<int>(message.wParam));
  }

  if (!context.done || context.cancelled) {
    return MakeFailure("cancelled",
                       "Region selection was cancelled.",
                       "Start a new capture when ready.",
                       "", "user", "notRecoverable");
  }

  const RECT selected = NormalizedRect(context.start, context.current);
  const MonitorDescriptor* monitor = MonitorForRect(selected, context.monitors);
  if (monitor == nullptr) {
    return MakeFailure("invalidInput",
                       "The selected display could not be resolved.",
                       "Select an area inside a display and try again.");
  }

  RECT clamped = {};
  if (!IntersectRects(selected, monitor->bounds, &clamped) ||
      !RectIsLargeEnough(clamped, 5) ||
      !RectsEqual(selected, clamped)) {
    return MakeFailure("invalidInput",
                       "The selected region crosses display boundaries.",
                       "Select an area inside a single display.");
  }

  return RegionSelectionPayload(clamped, *monitor, context.monitors);
}

}  // namespace

class WindowsCapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<MethodChannel<EncodableValue>>(
        registrar->messenger(), "desktop_screen_capture/native",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<WindowsCapturePlugin>();
    WindowsCapturePlugin* plugin_pointer = plugin.get();

    channel->SetMethodCallHandler(
        [plugin_pointer](const MethodCall<EncodableValue>& call,
                         std::unique_ptr<MethodResult<EncodableValue>> result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  WindowsCapturePlugin() : engine_(&enumerator_) {}

  ~WindowsCapturePlugin() override = default;

 private:
  void HandleMethodCall(
      const MethodCall<EncodableValue>& call,
      std::unique_ptr<MethodResult<EncodableValue>> result) {
    const EncodableValue* arguments_value = call.arguments();
    const EncodableMap* arguments =
        arguments_value == nullptr
            ? nullptr
            : std::get_if<EncodableMap>(arguments_value);
    const std::string& method = call.method_name();

    if (method == "capture.listDisplays") {
      result->Success(MakeSuccess(enumerator_.ListDisplaysPayload()));
      return;
    }
    if (method == "capture.listWindows") {
      result->Success(MakeSuccess(enumerator_.ListWindowsPayload()));
      return;
    }
    if (method == "capture.captureDisplay") {
      result->Success(engine_.CaptureDisplayPayload(arguments));
      return;
    }
    if (method == "capture.captureWindow") {
      result->Success(engine_.CaptureWindowPayload(arguments));
      return;
    }
    if (method == "capture.captureRegion") {
      result->Success(engine_.CaptureRegionPayload(arguments));
      return;
    }
    if (method == "capture.selectRegion") {
      result->Success(SelectRegionPayload(enumerator_));
      return;
    }
    if (method == "capture.encodeImage") {
      result->Success(engine_.EncodeImagePayload(arguments));
      return;
    }
    if (method == "capability.queryPermissions") {
      result->Success(CapabilitySnapshot());
      return;
    }
    if (method == "capability.requestPermission") {
      result->Success(MakeSuccess(EncodableValue(
          PermissionPayload(PermissionTypeFromArguments(arguments)))));
      return;
    }

    result->NotImplemented();
  }

  DisplayEnumerator enumerator_;
  CaptureEngine engine_;
};

}  // namespace desktop_screen_capture_windows

void WindowsCapturePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  desktop_screen_capture_windows::WindowsCapturePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
