# SPDX-License-Identifier: MIT
# Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
# Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
cmake_minimum_required(VERSION 3.13)
project(file_viewer_documents LANGUAGES CXX)

set(PLUGIN_NAME file_viewer_documents_plugin)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(GMODULE REQUIRED IMPORTED_TARGET gmodule-2.0)

# WebKit is optional at build time and dynamically loaded at runtime. A machine
# without it can still launch the application and use other document viewers.
option(FILE_VIEWER_DOCUMENTS_WEBKITGTK "Compile the embedded WebKitGTK document host" ON)
if(FILE_VIEWER_DOCUMENTS_WEBKITGTK)
  pkg_check_modules(WEBKITGTK QUIET IMPORTED_TARGET webkit2gtk-4.1>=2.48.4)
endif()

add_library(${PLUGIN_NAME} SHARED file_viewer_documents_plugin.cc)
apply_standard_settings(${PLUGIN_NAME})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK PkgConfig::GMODULE ${CMAKE_DL_LIBS})

if(FILE_VIEWER_DOCUMENTS_WEBKITGTK AND WEBKITGTK_FOUND AND NOT CMAKE_VERSION VERSION_LESS 3.19)
  pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE FILE_VIEWER_DOCUMENTS_HAS_WEBKITGTK=1)
  target_include_directories(${PLUGIN_NAME} SYSTEM PRIVATE ${WEBKITGTK_INCLUDE_DIRS})
  target_compile_options(${PLUGIN_NAME} PRIVATE ${WEBKITGTK_CFLAGS_OTHER}
    -Wno-deprecated-declarations)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::EPOXY)
  add_executable(file_viewer_documents_webkit_probe webkit_runtime_probe.cc)
  apply_standard_settings(file_viewer_documents_webkit_probe)
  target_compile_features(file_viewer_documents_webkit_probe PRIVATE cxx_std_17)
  target_compile_options(file_viewer_documents_webkit_probe PRIVATE -Wno-deprecated-declarations)
  target_link_libraries(file_viewer_documents_webkit_probe PRIVATE PkgConfig::WEBKITGTK)
  add_dependencies(${PLUGIN_NAME} file_viewer_documents_webkit_probe)
  # Flutter first removes/recreates its bundle and installs bundled libraries
  # as non-executable FILES. Defer this executable's install until the parent's
  # install rules are complete, preserving its mode in any consuming app.
  cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL install
    TARGETS file_viewer_documents_webkit_probe RUNTIME DESTINATION lib COMPONENT Runtime)
  message(STATUS "file_viewer_documents: WebKitGTK4.1 host enabled; system runtime is loaded on demand")
else()
  message(STATUS "file_viewer_documents: unavailable-host stub (document rendering requires WebKitGTK4.1 >=2.48.4 headers and CMake >=3.19)")
endif()

# Never copy a partial browser runtime into Flutter's bundle. Distribution
# packages provide WebKit, its subprocesses, sandbox helper and security updates.
set(file_viewer_documents_bundled_libraries "" PARENT_SCOPE)
