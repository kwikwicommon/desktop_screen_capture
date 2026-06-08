#include "capture_engine.h"

#include <d3d11.h>
#include <dwmapi.h>
#include <dxgi1_2.h>
#include <objidl.h>
#include <wincodec.h>
#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

#include <flutter/encodable_value.h>
#include <wrl/client.h>

namespace desktop_screen_capture_windows {
namespace {

using Microsoft::WRL::ComPtr;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const GUID kContainerFormatWebp = {
    0xe094b0e2,
    0x67f2,
    0x45b3,
    {0xb0, 0xea, 0x11, 0x53, 0x37, 0xca, 0x7c, 0xf3}};

constexpr size_t kBgraBytesPerPixel = 4;
constexpr size_t kBgrBytesPerPixel = 3;

class ScopedComInitializer {
 public:
  ScopedComInitializer()
      : result_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}

  ~ScopedComInitializer() {
    if (result_ == S_OK || result_ == S_FALSE) {
      CoUninitialize();
    }
  }

  bool IsReady() const {
    return SUCCEEDED(result_) || result_ == RPC_E_CHANGED_MODE;
  }

  HRESULT result() const { return result_; }

 private:
  HRESULT result_;
};

class ScopedScreenDc {
 public:
  ScopedScreenDc() : dc_(GetDC(nullptr)) {}

  ~ScopedScreenDc() {
    if (dc_ != nullptr) {
      ReleaseDC(nullptr, dc_);
    }
  }

  HDC get() const { return dc_; }

 private:
  HDC dc_ = nullptr;
};

class ScopedMemoryDc {
 public:
  explicit ScopedMemoryDc(HDC source) : dc_(CreateCompatibleDC(source)) {}

  ~ScopedMemoryDc() {
    if (dc_ != nullptr) {
      DeleteDC(dc_);
    }
  }

  HDC get() const { return dc_; }

 private:
  HDC dc_ = nullptr;
};

class ScopedBitmap {
 public:
  explicit ScopedBitmap(HBITMAP bitmap) : bitmap_(bitmap) {}

  ~ScopedBitmap() {
    if (bitmap_ != nullptr) {
      DeleteObject(bitmap_);
    }
  }

  HBITMAP get() const { return bitmap_; }

 private:
  HBITMAP bitmap_ = nullptr;
};

class ScopedSelectedObject {
 public:
  ScopedSelectedObject(HDC dc, HGDIOBJ object)
      : dc_(dc), previous_(SelectObject(dc, object)) {}

  ~ScopedSelectedObject() {
    if (dc_ != nullptr && previous_ != nullptr && previous_ != HGDI_ERROR) {
      SelectObject(dc_, previous_);
    }
  }

  bool IsReady() const {
    return previous_ != nullptr && previous_ != HGDI_ERROR;
  }

 private:
  HDC dc_ = nullptr;
  HGDIOBJ previous_ = nullptr;
};

class ScopedDxgiFrame {
 public:
  explicit ScopedDxgiFrame(IDXGIOutputDuplication* duplication)
      : duplication_(duplication) {}

  ~ScopedDxgiFrame() {
    if (duplication_ != nullptr && acquired_) {
      duplication_->ReleaseFrame();
    }
  }

  void MarkAcquired() { acquired_ = true; }

 private:
  IDXGIOutputDuplication* duplication_ = nullptr;
  bool acquired_ = false;
};

struct ArgbColor {
  uint8_t alpha = 255;
  uint8_t red = 255;
  uint8_t green = 255;
  uint8_t blue = 255;
};

ArgbColor ParseArgb(uint32_t argb) {
  ArgbColor color;
  color.alpha = static_cast<uint8_t>((argb >> 24) & 0xff);
  color.red = static_cast<uint8_t>((argb >> 16) & 0xff);
  color.green = static_cast<uint8_t>((argb >> 8) & 0xff);
  color.blue = static_cast<uint8_t>(argb & 0xff);
  return color;
}

bool CheckedImageBufferSize(int width,
                            int height,
                            size_t bytes_per_pixel,
                            size_t* size) {
  if (size == nullptr || width <= 0 || height <= 0 ||
      bytes_per_pixel == 0) {
    return false;
  }
  const auto safe_width = static_cast<size_t>(width);
  const auto safe_height = static_cast<size_t>(height);
  if (safe_width > std::numeric_limits<size_t>::max() / safe_height) {
    return false;
  }
  const size_t pixels = safe_width * safe_height;
  if (pixels > std::numeric_limits<size_t>::max() / bytes_per_pixel) {
    return false;
  }
  *size = pixels * bytes_per_pixel;
  return true;
}

bool FrameHasExpectedSize(const BitmapFrame& frame) {
  size_t expected_size = 0;
  return CheckedImageBufferSize(frame.width, frame.height, kBgraBytesPerPixel,
                                &expected_size) &&
         frame.bgra.size() >= expected_size;
}

uint8_t BlendChannel(uint8_t source, uint8_t alpha, uint8_t matte) {
  const int inverse_alpha = 255 - alpha;
  return static_cast<uint8_t>(
      (static_cast<int>(source) * alpha +
       static_cast<int>(matte) * inverse_alpha + 127) /
      255);
}

bool FrameHasOnlyZeroAlpha(const BitmapFrame& frame) {
  if (frame.bgra.size() < 4) {
    return false;
  }
  for (size_t index = 3; index < frame.bgra.size(); index += 4) {
    if (frame.bgra[index] != 0) {
      return false;
    }
  }
  return true;
}

void SetOpaqueAlpha(BitmapFrame* frame) {
  if (frame == nullptr) {
    return;
  }
  for (size_t index = 3; index < frame->bgra.size(); index += 4) {
    frame->bgra[index] = 255;
  }
}

void EnsureUsableAlpha(BitmapFrame* frame) {
  if (frame != nullptr && FrameHasOnlyZeroAlpha(*frame)) {
    SetOpaqueAlpha(frame);
  }
}

void FlattenFrame(BitmapFrame* frame, uint32_t argb) {
  if (frame == nullptr) {
    return;
  }
  const ArgbColor matte = ParseArgb(argb);
  for (size_t index = 0; index + 3 < frame->bgra.size(); index += 4) {
    const uint8_t source_alpha = frame->bgra[index + 3];
    const uint8_t effective_alpha =
        static_cast<uint8_t>((static_cast<int>(source_alpha) * matte.alpha) /
                             255);
    frame->bgra[index] =
        BlendChannel(frame->bgra[index], effective_alpha, matte.blue);
    frame->bgra[index + 1] =
        BlendChannel(frame->bgra[index + 1], effective_alpha, matte.green);
    frame->bgra[index + 2] =
        BlendChannel(frame->bgra[index + 2], effective_alpha, matte.red);
    frame->bgra[index + 3] = 255;
  }
}

std::vector<uint8_t> BgrBytesFlattened(const BitmapFrame& frame,
                                       uint32_t argb) {
  const ArgbColor matte = ParseArgb(argb);
  std::vector<uint8_t> output;
  size_t output_size = 0;
  if (!CheckedImageBufferSize(frame.width, frame.height, kBgrBytesPerPixel,
                              &output_size)) {
    return output;
  }
  output.resize(output_size);
  for (int y = 0; y < frame.height; ++y) {
    for (int x = 0; x < frame.width; ++x) {
      const size_t source_index =
          (static_cast<size_t>(y) * frame.width + x) * 4;
      const size_t target_index =
          (static_cast<size_t>(y) * frame.width + x) * 3;
      const uint8_t source_alpha = frame.bgra[source_index + 3];
      const uint8_t effective_alpha =
          static_cast<uint8_t>((static_cast<int>(source_alpha) * matte.alpha) /
                               255);
      output[target_index] =
          BlendChannel(frame.bgra[source_index], effective_alpha, matte.blue);
      output[target_index + 1] = BlendChannel(
          frame.bgra[source_index + 1], effective_alpha, matte.green);
      output[target_index + 2] = BlendChannel(
          frame.bgra[source_index + 2], effective_alpha, matte.red);
    }
  }
  return output;
}

bool GetWindowFrameBounds(HWND window, RECT* rect) {
  if (rect == nullptr) {
    return false;
  }
  RECT frame = {};
  if (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS,
                                      &frame, sizeof(frame))) &&
      RectIsLargeEnough(frame)) {
    *rect = frame;
    return true;
  }
  return GetWindowRect(window, rect) == TRUE;
}

bool IsWindowCloaked(HWND window) {
  BOOL cloaked = FALSE;
  return SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                         sizeof(cloaked))) &&
         cloaked == TRUE;
}

bool IsWindowResponsive(HWND window) {
  DWORD_PTR result = 0;
  return SendMessageTimeoutW(window, WM_NULL, 0, 0,
                             SMTO_ABORTIFHUNG | SMTO_BLOCK, 100, &result) != 0;
}

HRESULT CreateWicFactory(ComPtr<IWICImagingFactory>* factory) {
  return CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                          CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(factory->GetAddressOf()));
}

HRESULT StreamBytes(IStream* stream, std::vector<uint8_t>* bytes) {
  if (stream == nullptr || bytes == nullptr) {
    return E_INVALIDARG;
  }
  STATSTG stat = {};
  HRESULT hr = stream->Stat(&stat, STATFLAG_NONAME);
  if (FAILED(hr)) {
    return hr;
  }
  const ULONGLONG stream_size = stat.cbSize.QuadPart;
  if (stream_size >
      static_cast<ULONGLONG>(std::numeric_limits<size_t>::max())) {
    return E_OUTOFMEMORY;
  }
  HGLOBAL global = nullptr;
  hr = GetHGlobalFromStream(stream, &global);
  if (FAILED(hr)) {
    return hr;
  }
  const SIZE_T size = static_cast<SIZE_T>(stream_size);
  const void* data = GlobalLock(global);
  if (data == nullptr) {
    return E_FAIL;
  }
  const auto* first = static_cast<const uint8_t*>(data);
  bytes->assign(first, first + size);
  GlobalUnlock(global);
  return S_OK;
}

HRESULT EncodeFrame(const BitmapFrame& frame,
                    const GUID& container_format,
                    int quality,
                    uint32_t matte_color,
                    std::vector<uint8_t>* bytes) {
  if (bytes == nullptr || !FrameHasExpectedSize(frame)) {
    return E_INVALIDARG;
  }

  ScopedComInitializer com;
  if (!com.IsReady()) {
    return com.result();
  }

  ComPtr<IWICImagingFactory> factory;
  HRESULT hr = CreateWicFactory(&factory);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IStream> stream;
  hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IWICBitmapEncoder> encoder;
  hr = factory->CreateEncoder(container_format, nullptr, &encoder);
  if (FAILED(hr)) {
    return hr;
  }

  hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  if (FAILED(hr)) {
    return hr;
  }

  ComPtr<IWICBitmapFrameEncode> frame_encoder;
  ComPtr<IPropertyBag2> properties;
  hr = encoder->CreateNewFrame(&frame_encoder, &properties);
  if (FAILED(hr)) {
    return hr;
  }

  if (properties != nullptr &&
      (container_format == GUID_ContainerFormatJpeg ||
       container_format == kContainerFormatWebp)) {
    PROPBAG2 option = {};
    option.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
    VARIANT value = {};
    VariantInit(&value);
    value.vt = VT_R4;
    value.fltVal = static_cast<float>(std::clamp(quality, 1, 100)) / 100.0f;
    properties->Write(1, &option, &value);
    VariantClear(&value);
  }

  hr = frame_encoder->Initialize(properties.Get());
  if (FAILED(hr)) {
    return hr;
  }

  hr = frame_encoder->SetSize(static_cast<UINT>(frame.width),
                              static_cast<UINT>(frame.height));
  if (FAILED(hr)) {
    return hr;
  }

  const bool encode_jpeg = container_format == GUID_ContainerFormatJpeg;
  std::vector<uint8_t> flattened_bgr;
  const BYTE* pixel_data =
      reinterpret_cast<const BYTE*>(frame.bgra.data());
  size_t stride_value =
      static_cast<size_t>(frame.width) * kBgraBytesPerPixel;
  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
  if (encode_jpeg) {
    flattened_bgr = BgrBytesFlattened(frame, matte_color);
    if (flattened_bgr.empty()) {
      return E_INVALIDARG;
    }
    pixel_data = reinterpret_cast<const BYTE*>(flattened_bgr.data());
    stride_value = static_cast<size_t>(frame.width) * kBgrBytesPerPixel;
    pixel_format = GUID_WICPixelFormat24bppBGR;
  }
  if (stride_value > std::numeric_limits<UINT>::max()) {
    return E_INVALIDARG;
  }
  const UINT stride = static_cast<UINT>(stride_value);
  WICPixelFormatGUID accepted_pixel_format = pixel_format;
  hr = frame_encoder->SetPixelFormat(&accepted_pixel_format);
  if (FAILED(hr)) {
    return hr;
  }
  if (!IsEqualGUID(accepted_pixel_format, pixel_format)) {
    return WINCODEC_ERR_UNSUPPORTEDPIXELFORMAT;
  }

  const size_t buffer_size_value =
      static_cast<size_t>(stride) * static_cast<size_t>(frame.height);
  if (buffer_size_value > std::numeric_limits<UINT>::max()) {
    return E_INVALIDARG;
  }
  const UINT buffer_size = static_cast<UINT>(buffer_size_value);
  hr = frame_encoder->WritePixels(
      static_cast<UINT>(frame.height), stride, buffer_size,
      const_cast<BYTE*>(pixel_data));
  if (FAILED(hr)) {
    return hr;
  }

  hr = frame_encoder->Commit();
  if (FAILED(hr)) {
    return hr;
  }
  hr = encoder->Commit();
  if (FAILED(hr)) {
    return hr;
  }
  return StreamBytes(stream.Get(), bytes);
}

EncodableValue MakeImagePayload(const BitmapFrame& frame,
                                int64_t display_id,
                                int64_t window_id,
                                double scale_factor) {
  std::vector<uint8_t> png;
  HRESULT hr = EncodeFrame(frame, GUID_ContainerFormatPng, 90, 0xffffffff, &png);
  if (FAILED(hr)) {
    return MakeFailure("ioFailure", "The captured image could not be encoded.",
                       "Try the capture again.");
  }
  EncodableMap payload;
  payload[EncodableValue("imageBytes")] = EncodableValue(png);
  payload[EncodableValue("width")] = EncodableValue(frame.width);
  payload[EncodableValue("height")] = EncodableValue(frame.height);
  payload[EncodableValue("scaleFactor")] = EncodableValue(scale_factor);
  payload[EncodableValue("isTemporary")] = EncodableValue(false);
  if (display_id != 0) {
    payload[EncodableValue("displayId")] = EncodableValue(display_id);
  }
  if (window_id != 0) {
    payload[EncodableValue("windowId")] = EncodableValue(window_id);
  }
  return MakeSuccess(EncodableValue(payload));
}

std::string HResultToString(HRESULT hr) {
  char buffer[32] = {};
  snprintf(buffer, sizeof(buffer), "0x%08lx", static_cast<unsigned long>(hr));
  return buffer;
}

bool ReadBool(const EncodableValue* value, bool fallback) {
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* result = std::get_if<bool>(value)) {
    return *result;
  }
  return fallback;
}

uint32_t ReadArgb(const EncodableValue* value, uint32_t fallback) {
  const int64_t raw = ReadInt(value);
  if (raw == 0 && value == nullptr) {
    return fallback;
  }
  return static_cast<uint32_t>(raw);
}

}  // namespace

bool RectIsLargeEnough(const RECT& rect, int minimum) {
  const int64_t width =
      static_cast<int64_t>(rect.right) - static_cast<int64_t>(rect.left);
  const int64_t height =
      static_cast<int64_t>(rect.bottom) - static_cast<int64_t>(rect.top);
  return width >= minimum && height >= minimum &&
         width <= std::numeric_limits<int>::max() &&
         height <= std::numeric_limits<int>::max();
}

bool IntersectRects(const RECT& first, const RECT& second, RECT* output) {
  RECT intersection = {};
  if (!IntersectRect(&intersection, &first, &second)) {
    return false;
  }
  if (output != nullptr) {
    *output = intersection;
  }
  return RectIsLargeEnough(intersection);
}

RECT VirtualScreenBounds() {
  RECT rect = {};
  rect.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
  rect.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
  rect.right = rect.left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
  rect.bottom = rect.top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
  return rect;
}

CaptureEngine::CaptureEngine(DisplayEnumerator* enumerator)
    : enumerator_(enumerator) {}

EncodableValue CaptureEngine::CaptureDisplayPayload(
    const EncodableMap* arguments) const {
  const int64_t display_id =
      arguments == nullptr ? 0 : ReadInt(FindMapValue(*arguments, "displayId"));
  const auto monitors = enumerator_->EnumerateMonitors();
  const MonitorDescriptor* monitor =
      enumerator_->FindMonitorById(monitors, display_id);
  if (monitor == nullptr) {
    return MakeFailure("nativeFailure", "No display is available to capture.",
                       "Connect a display and try again.");
  }

  BitmapFrame frame;
  std::string error;
  if (!CaptureDisplayDxgi(*monitor, &frame, &error) &&
      !CaptureRectBgra(monitor->bounds, &frame, &error)) {
    return MakeFailure("nativeFailure", error,
                       "Check the selected display and try again.");
  }
  return MakeImagePayload(frame, monitor->id, 0, monitor->scale_factor);
}

EncodableValue CaptureEngine::CaptureRegionPayload(
    const EncodableMap* arguments) const {
  if (arguments == nullptr) {
    return MakeFailure("invalidInput",
                       "A physical pixel region is required for region capture.",
                       "Select a region and retry the capture.");
  }

  RECT region = {};
  if (!ReadPhysicalRect(*arguments, "region", &region)) {
    return MakeFailure("invalidInput",
                       "A physical pixel region is required for region capture.",
                       "Select a region and retry the capture.");
  }

  const int64_t display_id = ReadInt(FindMapValue(*arguments, "displayId"));
  double scale_factor = 1.0;
  if (display_id != 0) {
    const auto monitors = enumerator_->EnumerateMonitors();
    const MonitorDescriptor* monitor =
        enumerator_->FindMonitorById(monitors, display_id);
    if (monitor == nullptr) {
      return MakeFailure("nativeFailure", "The target display was not found.",
                         "Refresh the display list and try again.");
    }
    OffsetRect(&region, monitor->bounds.left, monitor->bounds.top);
    RECT clamped = {};
    if (!IntersectRects(region, monitor->bounds, &clamped)) {
      return MakeFailure("invalidInput",
                         "The selected region is outside the target display.",
                         "Select an area inside the display and try again.");
    }
    region = clamped;
    scale_factor = monitor->scale_factor;
  } else {
    RECT clamped = {};
    if (!IntersectRects(region, VirtualScreenBounds(), &clamped)) {
      return MakeFailure("invalidInput",
                         "The selected region is outside the desktop.",
                         "Select a visible area and try again.");
    }
    region = clamped;
  }

  BitmapFrame frame;
  std::string error;
  if (!CaptureRectBgra(region, &frame, &error)) {
    return MakeFailure("nativeFailure", error,
                       "Check the selected region and try again.");
  }
  return MakeImagePayload(frame, display_id, 0, scale_factor);
}

EncodableValue CaptureEngine::CaptureWindowPayload(
    const EncodableMap* arguments) const {
  const int64_t window_id =
      arguments == nullptr ? 0 : ReadInt(FindMapValue(*arguments, "windowId"));
  HWND window = reinterpret_cast<HWND>(static_cast<intptr_t>(window_id));
  if (window == nullptr || !IsWindow(window)) {
    return MakeFailure("nativeFailure", "The selected window was not found.",
                       "Refresh the window list and try again.");
  }
  if (IsIconic(window)) {
    return MakeFailure("nativeFailure", "The selected window is minimized.",
                       "Restore the window and try again.");
  }
  if (!IsWindowVisible(window) || IsWindowCloaked(window)) {
    return MakeFailure("nativeFailure",
                       "The selected window is not currently capturable.",
                       "Restore the window and try again.");
  }

  const bool keep_transparent_background =
      arguments == nullptr
          ? true
          : ReadBool(FindMapValue(*arguments, "keepTransparentBackground"),
                     true);
  const uint32_t replacement_background_color =
      arguments == nullptr
          ? 0xffffffff
          : ReadArgb(FindMapValue(*arguments, "replacementBackgroundColor"),
                     0xffffffff);
  const HMONITOR monitor_handle =
      MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  int64_t display_id = 0;
  double scale_factor = 1.0;
  const auto monitors = enumerator_->EnumerateMonitors();
  const MonitorDescriptor* monitor =
      enumerator_->FindMonitorByHandle(monitors, monitor_handle);
  if (monitor != nullptr) {
    display_id = monitor->id;
    scale_factor = monitor->scale_factor;
  }

  BitmapFrame frame;
  std::string error;
  if (!CaptureWindowBgra(window, &frame, &error)) {
    return MakeFailure("nativeFailure", error,
                       "Make sure the window is still visible and try again.");
  }
  if (keep_transparent_background) {
    EnsureUsableAlpha(&frame);
  } else {
    FlattenFrame(&frame, replacement_background_color);
  }
  return MakeImagePayload(frame, display_id, window_id, scale_factor);
}

EncodableValue CaptureEngine::EncodeImagePayload(
    const EncodableMap* arguments) const {
  if (arguments == nullptr) {
    return MakeFailure("invalidInput", "Image bytes are required for encoding.",
                       "Capture an image and try again.");
  }
  const auto* bytes_value = FindMapValue(*arguments, "imageBytes");
  const auto* bytes = bytes_value == nullptr
                          ? nullptr
                          : std::get_if<std::vector<uint8_t>>(bytes_value);
  if (bytes == nullptr || bytes->empty()) {
    return MakeFailure("invalidInput", "Image bytes are required for encoding.",
                       "Capture an image and try again.");
  }

  BitmapFrame frame;
  std::string error;
  if (!DecodeImageBytes(*bytes, &frame, &error)) {
    return MakeFailure("ioFailure", error, "Try the capture again.");
  }

  std::string format = "png";
  if (const auto* value = FindMapValue(*arguments, "format")) {
    if (const auto* text = std::get_if<std::string>(value)) {
      format = *text;
    }
  }
  const int quality = ReadInt32(FindMapValue(*arguments, "quality"), 90);
  const uint32_t matte_color =
      ReadArgb(FindMapValue(*arguments, "matteColor"), 0xffffffff);

  GUID container = GUID_ContainerFormatPng;
  std::string extension = "png";
  std::string mime_type = "image/png";
  if (format == "jpeg") {
    container = GUID_ContainerFormatJpeg;
    extension = "jpeg";
    mime_type = "image/jpeg";
  } else if (format == "webp") {
    container = kContainerFormatWebp;
    extension = "webp";
    mime_type = "image/webp";
  } else if (format != "png") {
    return MakeFailure("invalidInput",
                       "The requested image format is not supported.",
                       "Choose PNG, JPEG, or WebP.",
                       "", "native", "notRecoverable");
  }

  std::vector<uint8_t> encoded;
  HRESULT hr = EncodeFrame(frame, container, quality, matte_color, &encoded);
  if (FAILED(hr)) {
    return MakeFailure(format == "webp" ? "unsupported" : "ioFailure",
                       "The capture image could not be encoded.",
                       format == "webp" ? "Install a WebP WIC encoder or use PNG/JPEG."
                                        : "Try the capture again.",
                       HResultToString(hr));
  }

  EncodableMap payload;
  payload[EncodableValue("imageBytes")] = EncodableValue(encoded);
  payload[EncodableValue("width")] = EncodableValue(frame.width);
  payload[EncodableValue("height")] = EncodableValue(frame.height);
  payload[EncodableValue("format")] = EncodableValue(format);
  payload[EncodableValue("extension")] = EncodableValue(extension);
  payload[EncodableValue("mimeType")] = EncodableValue(mime_type);
  return MakeSuccess(EncodableValue(payload));
}

bool CaptureEngine::CaptureRectBgra(const RECT& rect,
                                    BitmapFrame* frame,
                                    std::string* error) const {
  const int64_t width64 =
      static_cast<int64_t>(rect.right) - static_cast<int64_t>(rect.left);
  const int64_t height64 =
      static_cast<int64_t>(rect.bottom) - static_cast<int64_t>(rect.top);
  if (width64 <= 0 || height64 <= 0 ||
      width64 > std::numeric_limits<int>::max() ||
      height64 > std::numeric_limits<int>::max() || frame == nullptr) {
    if (error != nullptr) {
      *error = "The requested capture rectangle is empty.";
    }
    return false;
  }
  const int width = static_cast<int>(width64);
  const int height = static_cast<int>(height64);
  size_t buffer_size = 0;
  if (!CheckedImageBufferSize(width, height, kBgraBytesPerPixel,
                              &buffer_size)) {
    if (error != nullptr) {
      *error = "The requested capture rectangle is too large.";
    }
    return false;
  }

  ScopedScreenDc source_dc;
  if (source_dc.get() == nullptr) {
    if (error != nullptr) {
      *error = "The screen device context could not be opened.";
    }
    return false;
  }

  ScopedMemoryDc memory_dc(source_dc.get());
  if (memory_dc.get() == nullptr) {
    if (error != nullptr) {
      *error = "The capture device context could not be created.";
    }
    return false;
  }

  BITMAPINFO bitmap_info = {};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  ScopedBitmap bitmap(CreateDIBSection(source_dc.get(), &bitmap_info,
                                       DIB_RGB_COLORS, &bits, nullptr, 0));
  if (bitmap.get() == nullptr || bits == nullptr) {
    if (error != nullptr) {
      *error = "The capture bitmap could not be allocated.";
    }
    return false;
  }

  ScopedSelectedObject selected_bitmap(memory_dc.get(), bitmap.get());
  if (!selected_bitmap.IsReady()) {
    if (error != nullptr) {
      *error = "The capture bitmap could not be selected.";
    }
    return false;
  }
  const BOOL copied =
      BitBlt(memory_dc.get(), 0, 0, width, height, source_dc.get(), rect.left,
             rect.top, SRCCOPY | CAPTUREBLT);
  GdiFlush();

  if (copied) {
    const auto* data = static_cast<const uint8_t*>(bits);
    frame->width = width;
    frame->height = height;
    frame->bgra.assign(data, data + buffer_size);
    SetOpaqueAlpha(frame);
  }

  if (!copied && error != nullptr) {
    *error = "The screen pixels could not be copied.";
  }
  return copied == TRUE;
}

bool CaptureEngine::CaptureDisplayDxgi(const MonitorDescriptor& monitor,
                                       BitmapFrame* frame,
                                       std::string* error) const {
  if (frame == nullptr) {
    return false;
  }

  ComPtr<IDXGIFactory1> factory;
  HRESULT hr = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI factory creation failed: " + HResultToString(hr);
    }
    return false;
  }

  ComPtr<IDXGIAdapter1> selected_adapter;
  ComPtr<IDXGIOutput> selected_output;
  HMONITOR target_monitor = monitor.handle;

  for (UINT adapter_index = 0;; ++adapter_index) {
    ComPtr<IDXGIAdapter1> adapter;
    if (factory->EnumAdapters1(adapter_index, &adapter) == DXGI_ERROR_NOT_FOUND) {
      break;
    }
    for (UINT output_index = 0;; ++output_index) {
      ComPtr<IDXGIOutput> output;
      if (adapter->EnumOutputs(output_index, &output) == DXGI_ERROR_NOT_FOUND) {
        break;
      }
      DXGI_OUTPUT_DESC desc = {};
      if (SUCCEEDED(output->GetDesc(&desc)) && desc.Monitor == target_monitor) {
        selected_adapter = adapter;
        selected_output = output;
        break;
      }
    }
    if (selected_output != nullptr) {
      break;
    }
  }

  if (selected_adapter == nullptr || selected_output == nullptr) {
    if (error != nullptr) {
      *error = "The selected display output was not found through DXGI.";
    }
    return false;
  }

  D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };
  D3D_FEATURE_LEVEL feature_level = D3D_FEATURE_LEVEL_11_0;
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  hr = D3D11CreateDevice(selected_adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN,
                         nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                         feature_levels, ARRAYSIZE(feature_levels),
                         D3D11_SDK_VERSION, &device, &feature_level, &context);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "D3D11 device creation failed: " + HResultToString(hr);
    }
    return false;
  }

  ComPtr<IDXGIOutput1> output1;
  hr = selected_output.As(&output1);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI output duplication is unavailable: " + HResultToString(hr);
    }
    return false;
  }

  ComPtr<IDXGIOutputDuplication> duplication;
  hr = output1->DuplicateOutput(device.Get(), &duplication);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI desktop duplication failed: " + HResultToString(hr);
    }
    return false;
  }

  DXGI_OUTDUPL_FRAME_INFO frame_info = {};
  ComPtr<IDXGIResource> desktop_resource;
  hr = duplication->AcquireNextFrame(250, &frame_info, &desktop_resource);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI desktop frame acquisition failed: " + HResultToString(hr);
    }
    return false;
  }
  ScopedDxgiFrame acquired_frame(duplication.Get());
  acquired_frame.MarkAcquired();

  ComPtr<ID3D11Texture2D> texture;
  hr = desktop_resource.As(&texture);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI desktop frame texture was unavailable: " +
               HResultToString(hr);
    }
    return false;
  }

  D3D11_TEXTURE2D_DESC desc = {};
  texture->GetDesc(&desc);
  D3D11_TEXTURE2D_DESC staging_desc = desc;
  staging_desc.BindFlags = 0;
  staging_desc.MiscFlags = 0;
  staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  staging_desc.Usage = D3D11_USAGE_STAGING;

  ComPtr<ID3D11Texture2D> staging;
  hr = device->CreateTexture2D(&staging_desc, nullptr, &staging);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI staging texture creation failed: " + HResultToString(hr);
    }
    return false;
  }

  context->CopyResource(staging.Get(), texture.Get());
  D3D11_MAPPED_SUBRESOURCE mapped = {};
  hr = context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "DXGI desktop frame mapping failed: " + HResultToString(hr);
    }
    return false;
  }

  if (desc.Width > static_cast<UINT>(std::numeric_limits<int>::max()) ||
      desc.Height > static_cast<UINT>(std::numeric_limits<int>::max())) {
    context->Unmap(staging.Get(), 0);
    if (error != nullptr) {
      *error = "The selected display frame is too large.";
    }
    return false;
  }
  const int width = static_cast<int>(desc.Width);
  const int height = static_cast<int>(desc.Height);
  size_t buffer_size = 0;
  if (!CheckedImageBufferSize(width, height, kBgraBytesPerPixel,
                              &buffer_size)) {
    context->Unmap(staging.Get(), 0);
    if (error != nullptr) {
      *error = "The selected display frame is too large.";
    }
    return false;
  }
  const size_t row_bytes =
      static_cast<size_t>(width) * kBgraBytesPerPixel;
  if (mapped.RowPitch < row_bytes) {
    context->Unmap(staging.Get(), 0);
    if (error != nullptr) {
      *error = "DXGI desktop frame row pitch is invalid.";
    }
    return false;
  }
  frame->width = width;
  frame->height = height;
  frame->bgra.resize(buffer_size);
  const auto* source = static_cast<const uint8_t*>(mapped.pData);
  for (int row = 0; row < height; ++row) {
    std::memcpy(frame->bgra.data() + static_cast<size_t>(row) * row_bytes,
                source + static_cast<size_t>(row) * mapped.RowPitch,
                row_bytes);
  }
  SetOpaqueAlpha(frame);

  context->Unmap(staging.Get(), 0);
  return true;
}

bool CaptureEngine::CaptureWindowBgra(HWND window,
                                      BitmapFrame* frame,
                                      std::string* error) const {
  RECT rect = {};
  if (!GetWindowFrameBounds(window, &rect)) {
    if (error != nullptr) {
      *error = "The selected window bounds could not be read.";
    }
    return false;
  }

  const int64_t width64 =
      static_cast<int64_t>(rect.right) - static_cast<int64_t>(rect.left);
  const int64_t height64 =
      static_cast<int64_t>(rect.bottom) - static_cast<int64_t>(rect.top);
  if (width64 <= 0 || height64 <= 0 ||
      width64 > std::numeric_limits<int>::max() ||
      height64 > std::numeric_limits<int>::max() || frame == nullptr) {
    if (error != nullptr) {
      *error = "The selected window is empty.";
    }
    return false;
  }
  const int width = static_cast<int>(width64);
  const int height = static_cast<int>(height64);
  size_t buffer_size = 0;
  if (!CheckedImageBufferSize(width, height, kBgraBytesPerPixel,
                              &buffer_size)) {
    if (error != nullptr) {
      *error = "The selected window is too large.";
    }
    return false;
  }

  ScopedScreenDc screen_dc;
  if (screen_dc.get() == nullptr) {
    if (error != nullptr) {
      *error = "The window capture device context could not be created.";
    }
    return false;
  }

  ScopedMemoryDc memory_dc(screen_dc.get());
  if (memory_dc.get() == nullptr) {
    if (error != nullptr) {
      *error = "The window capture device context could not be created.";
    }
    return false;
  }

  BITMAPINFO bitmap_info = {};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = width;
  bitmap_info.bmiHeader.biHeight = -height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  ScopedBitmap bitmap(CreateDIBSection(screen_dc.get(), &bitmap_info,
                                       DIB_RGB_COLORS, &bits, nullptr, 0));
  if (bitmap.get() == nullptr || bits == nullptr) {
    if (error != nullptr) {
      *error = "The window capture bitmap could not be allocated.";
    }
    return false;
  }

  ScopedSelectedObject selected_bitmap(memory_dc.get(), bitmap.get());
  if (!selected_bitmap.IsReady()) {
    if (error != nullptr) {
      *error = "The window capture bitmap could not be selected.";
    }
    return false;
  }
  BOOL copied = FALSE;
  if (IsWindowResponsive(window)) {
    copied = PrintWindow(window, memory_dc.get(), PW_RENDERFULLCONTENT);
  }
  if (!copied) {
    copied = BitBlt(memory_dc.get(), 0, 0, width, height, screen_dc.get(),
                    rect.left, rect.top, SRCCOPY | CAPTUREBLT);
  }
  GdiFlush();

  if (copied) {
    const auto* data = static_cast<const uint8_t*>(bits);
    frame->width = width;
    frame->height = height;
    frame->bgra.assign(data, data + buffer_size);
  }

  if (!copied && error != nullptr) {
    *error = "The selected window pixels could not be copied.";
  }
  return copied == TRUE;
}

bool CaptureEngine::DecodeImageBytes(const std::vector<uint8_t>& bytes,
                                     BitmapFrame* frame,
                                     std::string* error) const {
  if (bytes.empty() || frame == nullptr) {
    return false;
  }

  HGLOBAL global = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (global == nullptr) {
    if (error != nullptr) {
      *error = "The image decode buffer could not be allocated.";
    }
    return false;
  }
  void* destination = GlobalLock(global);
  if (destination == nullptr) {
    GlobalFree(global);
    if (error != nullptr) {
      *error = "The image decode buffer could not be opened.";
    }
    return false;
  }
  std::memcpy(destination, bytes.data(), bytes.size());
  GlobalUnlock(global);

  ScopedComInitializer com;
  if (!com.IsReady()) {
    GlobalFree(global);
    if (error != nullptr) {
      *error = "Windows Imaging Component is unavailable.";
    }
    return false;
  }

  ComPtr<IStream> stream;
  HRESULT hr = CreateStreamOnHGlobal(global, TRUE, &stream);
  if (FAILED(hr)) {
    GlobalFree(global);
    if (error != nullptr) {
      *error = "The image bytes could not be opened.";
    }
    return false;
  }

  ComPtr<IWICImagingFactory> factory;
  hr = CreateWicFactory(&factory);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "Windows Imaging Component is unavailable.";
    }
    return false;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  hr = factory->CreateDecoderFromStream(
      stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "The capture image could not be decoded for encoding.";
    }
    return false;
  }

  ComPtr<IWICBitmapFrameDecode> source_frame;
  hr = decoder->GetFrame(0, &source_frame);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "The capture image frame could not be read.";
    }
    return false;
  }

  ComPtr<IWICFormatConverter> converter;
  hr = factory->CreateFormatConverter(&converter);
  if (FAILED(hr)) {
    return false;
  }
  hr = converter->Initialize(source_frame.Get(), GUID_WICPixelFormat32bppBGRA,
                             WICBitmapDitherTypeNone, nullptr, 0.0,
                             WICBitmapPaletteTypeCustom);
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "The capture image could not be converted for encoding.";
    }
    return false;
  }

  UINT width = 0;
  UINT height = 0;
  hr = converter->GetSize(&width, &height);
  if (FAILED(hr) || width == 0 || height == 0 ||
      width > static_cast<UINT>(std::numeric_limits<int>::max()) ||
      height > static_cast<UINT>(std::numeric_limits<int>::max()) ||
      width > std::numeric_limits<UINT>::max() / kBgraBytesPerPixel) {
    if (error != nullptr) {
      *error = "The capture image dimensions could not be read.";
    }
    return false;
  }
  const UINT stride = width * 4;
  const size_t output_size =
      static_cast<size_t>(stride) * static_cast<size_t>(height);
  if (height > 0 &&
      output_size / static_cast<size_t>(height) != static_cast<size_t>(stride)) {
    if (error != nullptr) {
      *error = "The capture image is too large to decode.";
    }
    return false;
  }
  if (output_size > std::numeric_limits<UINT>::max()) {
    if (error != nullptr) {
      *error = "The capture image is too large to decode.";
    }
    return false;
  }
  std::vector<uint8_t> output(output_size);
  hr = converter->CopyPixels(nullptr, stride, static_cast<UINT>(output.size()),
                             output.data());
  if (FAILED(hr)) {
    if (error != nullptr) {
      *error = "The capture image pixels could not be read.";
    }
    return false;
  }

  frame->width = static_cast<int>(width);
  frame->height = static_cast<int>(height);
  frame->bgra = std::move(output);
  return true;
}

EncodableValue MakeSuccess(const EncodableValue& payload) {
  EncodableMap envelope;
  envelope[EncodableValue("status")] = EncodableValue("success");
  envelope[EncodableValue("payload")] = payload;
  return EncodableValue(envelope);
}

EncodableValue MakeFailure(const std::string& status,
                           const std::string& message,
                           const std::string& recovery_suggestion,
                           const std::string& native_code,
                           const std::string& domain,
                           const std::string& recoverability) {
  EncodableMap failure;
  failure[EncodableValue("message")] = EncodableValue(message);
  failure[EncodableValue("recoverySuggestion")] =
      EncodableValue(recovery_suggestion);
  failure[EncodableValue("nativeCode")] = EncodableValue(native_code);
  failure[EncodableValue("requiresRestart")] = EncodableValue(false);
  failure[EncodableValue("domain")] =
      EncodableValue(domain.empty() ? status : domain);
  failure[EncodableValue("recoverability")] = EncodableValue(recoverability);
  failure[EncodableValue("artifactPath")] = EncodableValue("");

  EncodableMap envelope;
  envelope[EncodableValue("status")] = EncodableValue(status);
  envelope[EncodableValue("failure")] = EncodableValue(failure);
  return EncodableValue(envelope);
}

const EncodableValue* FindMapValue(const EncodableMap& map, const char* key) {
  auto iterator = map.find(EncodableValue(key));
  if (iterator == map.end()) {
    return nullptr;
  }
  return &iterator->second;
}

int64_t ReadInt(const EncodableValue* value) {
  if (value == nullptr) {
    return 0;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<double>(value)) {
    if (!std::isfinite(*number) ||
        *number < static_cast<double>(std::numeric_limits<int64_t>::min()) ||
        *number > static_cast<double>(std::numeric_limits<int64_t>::max())) {
      return 0;
    }
    return static_cast<int64_t>(*number);
  }
  return 0;
}

int ReadInt32(const EncodableValue* value, int fallback) {
  const int64_t result = ReadInt(value);
  if (result == 0) {
    return fallback;
  }
  if (result < std::numeric_limits<int>::min() ||
      result > std::numeric_limits<int>::max()) {
    return fallback;
  }
  return static_cast<int>(result);
}

bool ReadPhysicalRect(const EncodableMap& arguments,
                      const char* key,
                      RECT* rect) {
  if (rect == nullptr) {
    return false;
  }
  const auto* value = FindMapValue(arguments, key);
  const auto* map = value == nullptr ? nullptr : std::get_if<EncodableMap>(value);
  if (map == nullptr) {
    return false;
  }
  const int64_t left = ReadInt(FindMapValue(*map, "left"));
  const int64_t top = ReadInt(FindMapValue(*map, "top"));
  const int64_t width = ReadInt(FindMapValue(*map, "width"));
  const int64_t height = ReadInt(FindMapValue(*map, "height"));
  if (width <= 0 || height <= 0 ||
      width > std::numeric_limits<int>::max() ||
      height > std::numeric_limits<int>::max() ||
      left > std::numeric_limits<int64_t>::max() - width ||
      top > std::numeric_limits<int64_t>::max() - height) {
    return false;
  }
  const int64_t right = left + width;
  const int64_t bottom = top + height;
  if (left < std::numeric_limits<LONG>::min() ||
      top < std::numeric_limits<LONG>::min() ||
      right > std::numeric_limits<LONG>::max() ||
      bottom > std::numeric_limits<LONG>::max() ||
      right <= left || bottom <= top) {
    return false;
  }
  rect->left = static_cast<LONG>(left);
  rect->top = static_cast<LONG>(top);
  rect->right = static_cast<LONG>(right);
  rect->bottom = static_cast<LONG>(bottom);
  return true;
}

}  // namespace desktop_screen_capture_windows
