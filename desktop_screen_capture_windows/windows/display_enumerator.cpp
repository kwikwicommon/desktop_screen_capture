#include "display_enumerator.h"

#include <dwmapi.h>
#include <shellscalingapi.h>
#include <windows.h>

#include <algorithm>
#include <limits>
#include <string>
#include <vector>

#include <flutter/encodable_value.h>

namespace desktop_screen_capture_windows {
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

double SafeScaleFactor(double scale_factor) {
  return scale_factor <= 0 ? 1.0 : scale_factor;
}

double RectWidth(const LogicalRect& rect) {
  return rect.right - rect.left;
}

double RectHeight(const LogicalRect& rect) {
  return rect.bottom - rect.top;
}

bool LogicalRectIsValid(const LogicalRect& rect) {
  return RectWidth(rect) > 0 && RectHeight(rect) > 0;
}

LogicalRect MakeLocalLogicalRect(const RECT& rect, double scale_factor) {
  const double scale = SafeScaleFactor(scale_factor);
  return LogicalRect{
      static_cast<double>(rect.left) / scale,
      static_cast<double>(rect.top) / scale,
      static_cast<double>(rect.right) / scale,
      static_cast<double>(rect.bottom) / scale,
  };
}

void AssignLogicalBounds(std::vector<MonitorDescriptor>* monitors) {
  if (monitors == nullptr || monitors->empty()) {
    return;
  }

  const auto primary = std::find_if(
      monitors->begin(), monitors->end(),
      [](const MonitorDescriptor& monitor) { return monitor.is_primary; });
  if (primary == monitors->end()) {
    for (auto& monitor : *monitors) {
      monitor.logical_bounds = MakeLocalLogicalRect(monitor.bounds,
                                                    monitor.scale_factor);
    }
    return;
  }

  const RECT primary_bounds = primary->bounds;
  const double primary_scale = SafeScaleFactor(primary->scale_factor);
  const double primary_width =
      static_cast<double>(primary_bounds.right - primary_bounds.left) /
      primary_scale;
  const double primary_height =
      static_cast<double>(primary_bounds.bottom - primary_bounds.top) /
      primary_scale;

  for (auto& monitor : *monitors) {
    const double scale = SafeScaleFactor(monitor.scale_factor);
    const double width =
        static_cast<double>(monitor.bounds.right - monitor.bounds.left) /
        scale;
    const double height =
        static_cast<double>(monitor.bounds.bottom - monitor.bounds.top) /
        scale;

    double left = 0;
    if (monitor.bounds.right <= primary_bounds.left) {
      const double gap =
          static_cast<double>(primary_bounds.left - monitor.bounds.right) /
          primary_scale;
      left = -gap - width;
    } else if (monitor.bounds.left >= primary_bounds.right) {
      const double gap =
          static_cast<double>(monitor.bounds.left - primary_bounds.right) /
          primary_scale;
      left = primary_width + gap;
    } else {
      left =
          static_cast<double>(monitor.bounds.left - primary_bounds.left) /
          primary_scale;
    }

    double top = 0;
    if (monitor.bounds.bottom <= primary_bounds.top) {
      const double gap =
          static_cast<double>(primary_bounds.top - monitor.bounds.bottom) /
          primary_scale;
      top = -gap - height;
    } else if (monitor.bounds.top >= primary_bounds.bottom) {
      const double gap =
          static_cast<double>(monitor.bounds.top - primary_bounds.bottom) /
          primary_scale;
      top = primary_height + gap;
    } else {
      top =
          static_cast<double>(monitor.bounds.top - primary_bounds.top) /
          primary_scale;
    }

    monitor.logical_bounds = LogicalRect{
        left,
        top,
        left + width,
        top + height,
    };
  }
}

BOOL CALLBACK MonitorEnumProc(HMONITOR monitor,
                              HDC,
                              LPRECT,
                              LPARAM user_data) {
  auto* monitors = reinterpret_cast<std::vector<MonitorDescriptor>*>(user_data);
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(MONITORINFOEXW);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }

  UINT dpi_x = 96;
  UINT dpi_y = 96;
  double scale_factor = 1.0;
  if (SUCCEEDED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) &&
      dpi_x > 0) {
    scale_factor = static_cast<double>(dpi_x) / 96.0;
  }

  MonitorDescriptor descriptor;
  descriptor.id = static_cast<int64_t>(monitors->size()) + 1;
  descriptor.handle = monitor;
  descriptor.bounds = info.rcMonitor;
  descriptor.logical_bounds = MakeLocalLogicalRect(info.rcMonitor,
                                                   scale_factor);
  descriptor.scale_factor = scale_factor;
  descriptor.is_primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  descriptor.is_internal = false;
  descriptor.device_name = info.szDevice;
  monitors->push_back(descriptor);
  return TRUE;
}

BOOL IsAltTabWindow(HWND window) {
  if (!IsWindowVisible(window)) {
    return FALSE;
  }
  LONG ex_style = GetWindowLongW(window, GWL_EXSTYLE);
  if ((ex_style & WS_EX_TOOLWINDOW) != 0) {
    return FALSE;
  }
  HWND owner = GetWindow(window, GW_OWNER);
  return owner == nullptr;
}

bool RectIsValid(const RECT& rect, int minimum = 1) {
  const int64_t width =
      static_cast<int64_t>(rect.right) - static_cast<int64_t>(rect.left);
  const int64_t height =
      static_cast<int64_t>(rect.bottom) - static_cast<int64_t>(rect.top);
  return width >= minimum && height >= minimum &&
         width <= std::numeric_limits<int>::max() &&
         height <= std::numeric_limits<int>::max();
}

bool IsWindowCloaked(HWND window) {
  BOOL cloaked = FALSE;
  return SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                         sizeof(cloaked))) &&
         cloaked == TRUE;
}

bool GetWindowFrameBounds(HWND window, RECT* rect) {
  if (rect == nullptr) {
    return false;
  }
  RECT frame = {};
  if (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS,
                                      &frame, sizeof(frame))) &&
      RectIsValid(frame)) {
    *rect = frame;
    return true;
  }
  return GetWindowRect(window, rect) == TRUE && RectIsValid(*rect);
}

std::wstring WindowText(HWND window) {
  int length = GetWindowTextLengthW(window);
  if (length <= 0) {
    return L"";
  }
  std::wstring text(static_cast<size_t>(length + 1), L'\0');
  int copied = GetWindowTextW(window, text.data(), length + 1);
  text.resize(static_cast<size_t>(std::max(copied, 0)));
  return text;
}

std::string FileNameFromPath(const std::wstring& path) {
  if (path.empty()) {
    return "";
  }
  const size_t slash = path.find_last_of(L"\\/");
  return WideToUtf8(slash == std::wstring::npos ? path
                                                : path.substr(slash + 1));
}

std::string ProcessNameForWindow(HWND window) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0) {
    return "";
  }

  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (process == nullptr) {
    return "";
  }
  std::string result;
  DWORD size = MAX_PATH;
  std::vector<wchar_t> path(size);
  while (true) {
    DWORD required_size = static_cast<DWORD>(path.size());
    if (QueryFullProcessImageNameW(process, 0, path.data(), &required_size)) {
      result = FileNameFromPath(std::wstring(path.data(), required_size));
      break;
    }
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER ||
        path.size() >= 32768) {
      break;
    }
    path.resize(path.size() * 2);
  }
  CloseHandle(process);
  return result;
}

EncodableMap MakeLogicalBoundsPayload(const LogicalRect& rect) {
  EncodableMap payload;
  payload[EncodableValue("left")] = EncodableValue(rect.left);
  payload[EncodableValue("top")] = EncodableValue(rect.top);
  payload[EncodableValue("width")] = EncodableValue(RectWidth(rect));
  payload[EncodableValue("height")] = EncodableValue(RectHeight(rect));
  return payload;
}

const MonitorDescriptor* FindMonitorByHandleInternal(
    const std::vector<MonitorDescriptor>& monitors,
    HMONITOR handle) {
  for (const auto& monitor : monitors) {
    if (monitor.handle == handle) {
      return &monitor;
    }
  }
  return nullptr;
}

LogicalRect WindowLogicalBounds(const RECT& window_bounds,
                                const MonitorDescriptor* monitor) {
  if (monitor == nullptr || !LogicalRectIsValid(monitor->logical_bounds)) {
    return MakeLocalLogicalRect(window_bounds, 1.0);
  }

  const double scale = SafeScaleFactor(monitor->scale_factor);
  const double left = monitor->logical_bounds.left +
                      static_cast<double>(window_bounds.left -
                                          monitor->bounds.left) /
                          scale;
  const double top = monitor->logical_bounds.top +
                     static_cast<double>(window_bounds.top -
                                         monitor->bounds.top) /
                         scale;
  return LogicalRect{
      left,
      top,
      left + static_cast<double>(window_bounds.right - window_bounds.left) /
                 scale,
      top + static_cast<double>(window_bounds.bottom - window_bounds.top) /
                scale,
  };
}

struct WindowEnumContext {
  std::vector<MonitorDescriptor> monitors;
  EncodableList windows;
};

BOOL CALLBACK WindowEnumProc(HWND window, LPARAM user_data) {
  auto* context = reinterpret_cast<WindowEnumContext*>(user_data);
  if (context == nullptr || !IsAltTabWindow(window) || IsWindowCloaked(window)) {
    return TRUE;
  }

  RECT bounds = {};
  if (!GetWindowFrameBounds(window, &bounds)) {
    return TRUE;
  }
  if (!RectIsValid(bounds, 21)) {
    return TRUE;
  }

  std::wstring title_w = WindowText(window);
  std::string app_name = ProcessNameForWindow(window);
  std::string title = WideToUtf8(title_w);
  if (title.empty()) {
    title = app_name;
  }
  if (title.empty()) {
    return TRUE;
  }

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
  const MonitorDescriptor* monitor_descriptor =
      FindMonitorByHandleInternal(context->monitors, monitor);
  const LogicalRect logical_bounds =
      WindowLogicalBounds(bounds, monitor_descriptor);

  EncodableMap payload;
  payload[EncodableValue("id")] =
      EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(window)));
  payload[EncodableValue("title")] = EncodableValue(title);
  payload[EncodableValue("appName")] = EncodableValue(app_name);
  payload[EncodableValue("bounds")] =
      EncodableValue(MakeLogicalBoundsPayload(logical_bounds));
  payload[EncodableValue("isVisible")] = EncodableValue(true);
  payload[EncodableValue("isOnScreen")] = EncodableValue(true);

  if (monitor != nullptr) {
    if (monitor_descriptor != nullptr) {
      payload[EncodableValue("displayId")] =
          EncodableValue(monitor_descriptor->id);
    }
  }

  context->windows.emplace_back(payload);
  return TRUE;
}

}  // namespace

std::vector<MonitorDescriptor> DisplayEnumerator::EnumerateMonitors() const {
  std::vector<MonitorDescriptor> monitors;
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc,
                      reinterpret_cast<LPARAM>(&monitors));
  AssignLogicalBounds(&monitors);
  return monitors;
}

const MonitorDescriptor* DisplayEnumerator::FindMonitorById(
    const std::vector<MonitorDescriptor>& monitors,
    int64_t display_id) const {
  if (monitors.empty()) {
    return nullptr;
  }
  if (display_id != 0) {
    for (const auto& monitor : monitors) {
      if (monitor.id == display_id) {
        return &monitor;
      }
    }
    return nullptr;
  }
  for (const auto& monitor : monitors) {
    if (monitor.is_primary) {
      return &monitor;
    }
  }
  return &monitors.front();
}

const MonitorDescriptor* DisplayEnumerator::FindMonitorByHandle(
    const std::vector<MonitorDescriptor>& monitors,
    HMONITOR handle) const {
  return FindMonitorByHandleInternal(monitors, handle);
}

EncodableValue DisplayEnumerator::ListDisplaysPayload() const {
  EncodableList displays;
  for (const auto& monitor : EnumerateMonitors()) {
    EncodableMap payload;
    payload[EncodableValue("id")] = EncodableValue(monitor.id);
    payload[EncodableValue("name")] =
        EncodableValue(WideToUtf8(monitor.device_name));
    payload[EncodableValue("bounds")] =
        EncodableValue(MakeLogicalBoundsPayload(monitor.logical_bounds));
    payload[EncodableValue("scaleFactor")] =
        EncodableValue(monitor.scale_factor);
    payload[EncodableValue("isPrimary")] =
        EncodableValue(monitor.is_primary);
    payload[EncodableValue("isInternal")] =
        EncodableValue(monitor.is_internal);
    displays.emplace_back(payload);
  }
  return EncodableValue(displays);
}

EncodableValue DisplayEnumerator::ListWindowsPayload() const {
  WindowEnumContext context;
  context.monitors = EnumerateMonitors();
  EnumWindows(WindowEnumProc, reinterpret_cast<LPARAM>(&context));
  return EncodableValue(context.windows);
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return "";
  }
  if (value.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
    return "";
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size <= 0) {
    return "";
  }
  std::string output(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), output.data(), size,
                      nullptr, nullptr);
  return output;
}

}  // namespace desktop_screen_capture_windows
