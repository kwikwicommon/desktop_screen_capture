#ifndef DESKTOP_SCREEN_CAPTURE_WINDOWS_CAPTURE_ENGINE_H_
#define DESKTOP_SCREEN_CAPTURE_WINDOWS_CAPTURE_ENGINE_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

#include <flutter/encodable_value.h>

#include "display_enumerator.h"

namespace desktop_screen_capture_windows {

struct BitmapFrame {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> bgra;
};

class CaptureEngine {
 public:
  explicit CaptureEngine(DisplayEnumerator* enumerator);

  flutter::EncodableValue CaptureDisplayPayload(
      const flutter::EncodableMap* arguments) const;
  flutter::EncodableValue CaptureWindowPayload(
      const flutter::EncodableMap* arguments) const;
  flutter::EncodableValue CaptureRegionPayload(
      const flutter::EncodableMap* arguments) const;
  flutter::EncodableValue EncodeImagePayload(
      const flutter::EncodableMap* arguments) const;

 private:
  DisplayEnumerator* enumerator_;

  bool CaptureRectBgra(const RECT& rect,
                       BitmapFrame* frame,
                       std::string* error) const;
  bool CaptureDisplayDxgi(const MonitorDescriptor& monitor,
                          BitmapFrame* frame,
                          std::string* error) const;
  bool CaptureWindowBgra(HWND window,
                         BitmapFrame* frame,
                         std::string* error) const;
  bool DecodeImageBytes(const std::vector<uint8_t>& bytes,
                        BitmapFrame* frame,
                        std::string* error) const;
};

flutter::EncodableValue MakeSuccess(const flutter::EncodableValue& payload);
flutter::EncodableValue MakeFailure(const std::string& status,
                                    const std::string& message,
                                    const std::string& recovery_suggestion,
                                    const std::string& native_code = "",
                                    const std::string& domain = "",
                                    const std::string& recoverability =
                                        "retryable");
const flutter::EncodableValue* FindMapValue(
    const flutter::EncodableMap& map,
    const char* key);
int64_t ReadInt(const flutter::EncodableValue* value);
int ReadInt32(const flutter::EncodableValue* value, int fallback = 0);
bool ReadPhysicalRect(const flutter::EncodableMap& arguments,
                      const char* key,
                      RECT* rect);
bool RectIsLargeEnough(const RECT& rect, int minimum = 1);
bool IntersectRects(const RECT& first, const RECT& second, RECT* output);
RECT VirtualScreenBounds();

}  // namespace desktop_screen_capture_windows

#endif  // DESKTOP_SCREEN_CAPTURE_WINDOWS_CAPTURE_ENGINE_H_
