Pod::Spec.new do |s|
  s.name = 'crisp_ios_shell'
  s.version = '0.1.0'
  s.summary = 'Embedded stream-connected ios_system and Dash shell.'
  s.description = 'A single in-process local iOS shell with owned streams, cancellation, bounded output and a Flutter transport.'
  s.homepage = 'https://github.com/CrispStrobe/CrispCloud'
  s.license = { :type => 'AGPL-3.0 with retained third-party notices', :file => '../LICENSE' }
  s.author = { 'CrispCloud' => 'https://github.com/CrispStrobe' }
  s.source = { :path => '.' }
  s.platform = :ios, '15.0'
  s.requires_arc = true
  s.source_files = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/CrispIosShellPlugin.h'
  s.vendored_frameworks = 'Frameworks/*.xcframework'
  s.resource_bundles = { 'CrispIosShellResources' => ['Resources/*'] }
  s.dependency 'Flutter'
  s.dependency 'crisp_ios_files'
  # Commands are embedded, but must be dlopened/dlclosed by ios_system so legacy
  # globals reset. Referencing them through LC_LOAD_DYLIB would keep them alive.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-dead_strip_dylibs',
  }
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -Wl,-dead_strip_dylibs' }
end
