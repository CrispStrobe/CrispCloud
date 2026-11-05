cmake_minimum_required(VERSION 3.10)
project(crisp_audio LANGUAGES CXX)

add_library(crisp_audio SHARED crisp_audio.cpp)
target_compile_features(crisp_audio PRIVATE cxx_std_17)
target_compile_definitions(crisp_audio PRIVATE _FILE_OFFSET_BITS=64)
set_target_properties(crisp_audio PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  OUTPUT_NAME crisp_audio
)

if(MSVC)
  target_compile_definitions(crisp_audio PRIVATE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(crisp_audio PRIVATE /EHsc)
else()
  target_compile_options(crisp_audio PRIVATE -fexceptions)
endif()

if(UNIX AND NOT APPLE)
  target_link_libraries(crisp_audio PRIVATE m)
endif()

if(ANDROID)
  # Required for devices running with 16 KiB memory pages. NDK r28 also
  # defaults to this; make the property explicit for older build hosts.
  target_link_libraries(crisp_audio PRIVATE "-Wl,-z,max-page-size=16384")
endif()
