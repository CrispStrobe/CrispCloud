cmake_minimum_required(VERSION 3.13)
project(crisp_ebook_reader LANGUAGES CXX)

set(PLUGIN_NAME crisp_ebook_reader_plugin)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(GMODULE REQUIRED IMPORTED_TARGET gmodule-2.0)

# WebKit is optional at build time and dynamically loaded at runtime. A machine
# without it can still launch the application and use the portable reader.
option(CRISP_EBOOK_WEBKITGTK "Compile the embedded WebKitGTK ebook host" ON)
if(CRISP_EBOOK_WEBKITGTK)
  pkg_check_modules(WEBKITGTK QUIET webkit2gtk-4.1>=2.40)
endif()

add_library(${PLUGIN_NAME} SHARED crisp_ebook_reader_plugin.cc)
apply_standard_settings(${PLUGIN_NAME})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK PkgConfig::GMODULE)

if(CRISP_EBOOK_WEBKITGTK AND WEBKITGTK_FOUND)
  pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE CRISP_EBOOK_HAS_WEBKITGTK=1)
  target_include_directories(${PLUGIN_NAME} SYSTEM PRIVATE ${WEBKITGTK_INCLUDE_DIRS})
  target_compile_options(${PLUGIN_NAME} PRIVATE ${WEBKITGTK_CFLAGS_OTHER}
    -Wno-deprecated-declarations)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::EPOXY)
  message(STATUS "crisp_ebook_reader: WebKitGTK4.1 host enabled; system runtime is loaded on demand")
else()
  message(STATUS "crisp_ebook_reader: portable-only build (WebKitGTK4.1 >=2.40 headers not found)")
endif()

# Never copy a partial browser runtime into Flutter's bundle. Distribution
# packages provide WebKit, its subprocesses, sandbox helper and security updates.
set(crisp_ebook_reader_bundled_libraries "" PARENT_SCOPE)
