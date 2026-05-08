Pod::Spec.new do |s|
  s.name             = 'issuetracker_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Drop-in issue reporter SDK for Flutter apps.'
  s.description      = <<-DESC
Drop-in issue reporter for Flutter apps. Bridges to the native
IssuetrackerSDK on iOS — shake-to-report, screenshot capture,
annotation, breadcrumbs, crash detection.
                       DESC
  s.homepage         = 'https://issuetracker.no'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Asle Kinnerod' => 'asle78@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # Native iOS SDK that this wrapper bridges to. The example app's
  # Podfile pins it to a local path during development:
  #   pod 'IssuetrackerSDK', :path => '../../../sdk-ios'
  s.dependency 'IssuetrackerSDK', '~> 0.1.0'

  s.platform = :ios, '16.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.9'
end
