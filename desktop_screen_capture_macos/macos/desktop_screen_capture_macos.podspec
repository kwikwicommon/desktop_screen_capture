Pod::Spec.new do |s|
  s.name = 'desktop_screen_capture_macos'
  s.version = '0.1.0'
  s.summary = 'macOS implementation for desktop_screen_capture.'
  s.description = 'ScreenCaptureKit based macOS implementation for desktop_screen_capture.'
  s.homepage = 'https://kwikwi.net'
  s.license = { :type => 'MIT' }
  s.author = { 'Kwikwi' => 'dev@kwikwi.net' }
  s.source = { :path => '.' }
  s.source_files = 'desktop_screen_capture_macos/Sources/desktop_screen_capture_macos/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.3'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES'
  }
end
