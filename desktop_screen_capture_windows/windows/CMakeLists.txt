cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "desktop_screen_capture_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "windows_capture_plugin")

list(APPEND PLUGIN_SOURCES
  "windows_capture_plugin.cpp"
  "capture_engine.cpp"
  "display_enumerator.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  "include/desktop_screen_capture_windows/windows_capture_plugin.h"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  d3d11
  dxgi
  dwmapi
  ole32
  oleaut32
  shcore
  windowscodecs
)

set(desktop_screen_capture_windows_bundled_libraries
  ""
  PARENT_SCOPE
)
