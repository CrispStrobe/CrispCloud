Pod::Spec.new do |s|
  s.name             = 'crisp_ios_files'
  s.version          = '0.1.0'
  s.summary          = 'Scoped iOS folders and coordinated file access.'
  s.description      = 'Native document picker, durable bookmarks, independent access leases and coordinated provider operations.'
  s.homepage         = 'https://github.com/CrispStrobe/CrispCloud'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'CrispCloud' => 'https://github.com/CrispStrobe' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift', 'ScopeCore/Sources/CrispIosFilesCore/**/*.swift'
  s.resource_bundles = { 'crisp_ios_files_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
