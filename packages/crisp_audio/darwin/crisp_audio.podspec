Pod::Spec.new do |s|
  s.name             = 'crisp_audio'
  s.version          = '0.1.0'
  s.summary          = 'CrispCloud offline audio editing.'
  s.description      = 'Offline WAV, FLAC and MP3 decoding with PCM16 WAV editing and export.'
  s.homepage         = 'https://github.com/CrispStrobe/CrispCloud'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'CrispCloud contributors' => 'https://github.com/CrispStrobe/CrispCloud' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/crisp_audio.cpp'
  s.static_framework = true
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'YES'
  }
  # The functions are reached through FFI, so there is no source-language
  # reference from the app. Keep this translation unit in static release links.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_crisp_audio_abi_version'
  }
  s.resource_bundles = {
    'crisp_audio_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
end
