cmake_minimum_required(VERSION 3.13)
project(crisp_audio LANGUAGES CXX)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/native")
set(crisp_audio_bundled_libraries "$<TARGET_FILE:crisp_audio>" PARENT_SCOPE)
