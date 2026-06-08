#ifndef DESKTOP_SCREEN_CAPTURE_WINDOWS_DISPLAY_ENUMERATOR_H_
#define DESKTOP_SCREEN_CAPTURE_WINDOWS_DISPLAY_ENUMERATOR_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include <flutter/encodable_value.h>

namespace desktop_screen_capture_windows {

struct LogicalRect {
  double left = 0;
  double top = 0;
  double right = 0;
  double bottom = 0;
};

struct MonitorDescriptor {
  int64_t id = 0;
  HMONITOR handle = nullptr;
  RECT bounds = {};
  LogicalRect logical_bounds = {};
  double scale_factor = 1.0;
  bool is_primary = false;
  bool is_internal = false;
  std::wstring device_name;
};

class DisplayEnumerator {
 public:
  std::vector<MonitorDescriptor> EnumerateMonitors() const;
  const MonitorDescriptor* FindMonitorById(
      const std::vector<MonitorDescriptor>& monitors,
      int64_t display_id) const;
  const MonitorDescriptor* FindMonitorByHandle(
      const std::vector<MonitorDescriptor>& monitors,
      HMONITOR handle) const;
  flutter::EncodableValue ListDisplaysPayload() const;
  flutter::EncodableValue ListWindowsPayload() const;
};

std::string WideToUtf8(const std::wstring& value);

}  // namespace desktop_screen_capture_windows

#endif  // DESKTOP_SCREEN_CAPTURE_WINDOWS_DISPLAY_ENUMERATOR_H_
