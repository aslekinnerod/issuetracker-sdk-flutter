Pod::Spec.new do |s|
  s.name             = 'issuetracker_sdk'
  s.version          = '0.5.0'
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

  # Native iOS SDK that this wrapper bridges to. Pinned exactly, and to
  # the same version android/build.gradle pins — a range here would let
  # one release of this wrapper bridge to native 0.6 on Android and 0.9
  # on iOS, against an API surface the Swift bridge never saw. Bump both
  # pins in the same commit; tool/check_versions.sh enforces that they
  # agree. The example app's Podfile prefers a sibling ../../../sdk-ios
  # checkout when one exists, so local SDK edits still land immediately.
  # 0.6.0: tester attestation (ADR-0005) — setTesterToken/clearTesterToken.
  #
  # NOTE: IssuetrackerSDK 0.6.0 is not on CocoaPods trunk yet (trunk has
  # no IssuetrackerSDK at all, and sdk-ios is tagged 0.5.1). The iOS CI
  # job stays red — correctly — until sdk-ios cuts and pushes 0.6.0.
  s.dependency 'IssuetrackerSDK', '0.6.0'

  s.platform = :ios, '16.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.9'
end
