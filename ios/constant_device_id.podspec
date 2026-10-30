Pod::Spec.new do |s|
  s.name             = 'constant_device_id'
  s.version          = '0.2.0'
  s.summary          = 'A Flutter plugin for permanent device identification.'
  s.description      = <<-DESC
    A Flutter plugin that provides a permanent device identifier that persists
    across app reinstalls. Uses Widevine DRM on Android and the iOS Keychain
    for hardware-level persistence.
  DESC
  s.homepage         = 'https://github.com/your-org/constant_device_id'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Organization' => 'dev@your-org.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'constant_device_id/Sources/constant_device_id/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
