#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'admoai'
  s.version          = '0.7.0'
  s.summary          = 'AdMoai Flutter SDK native device signals.'
  s.description      = <<-DESC
Native platform channel for the AdMoai Flutter SDK (coarse device category).
                       DESC
  s.homepage         = 'https://admoai.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AdMoai' => 'support@admoai.com' }
  s.source           = { :path => '.' }
  s.source_files = 'admoai/Sources/admoai/**/*.swift'
  s.dependency 'Flutter'
  # Mirrors device_info_plus 11.x (iOS 12.0).
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
