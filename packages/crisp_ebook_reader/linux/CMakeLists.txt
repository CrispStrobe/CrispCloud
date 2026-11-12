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
  pkg_check_modules(WEBKITGTK QUIET webkit2gtk-4.1>=2.48.4)
endif()

add_library(${PLUGIN_NAME} SHARED crisp_ebook_reader_plugin.cc)
apply_standard_settings(${PLUGIN_NAME})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK PkgConfig::GMODULE ${CMAKE_DL_LIBS})

if(CRISP_EBOOK_WEBKITGTK AND WEBKITGTK_FOUND AND CMAKE_VERSION VERSION_GREATER_EQUAL 3.19)
  pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE CRISP_EBOOK_HAS_WEBKITGTK=1)
  target_include_directories(${PLUGIN_NAME} SYSTEM PRIVATE ${WEBKITGTK_INCLUDE_DIRS})
  target_compile_options(${PLUGIN_NAME} PRIVATE ${WEBKITGTK_CFLAGS_OTHER}
    -Wno-deprecated-declarations)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::EPOXY)
  add_executable(crisp_ebook_reader_probe reader_canary.cc)
  apply_standard_settings(crisp_ebook_reader_probe)
  target_compile_features(crisp_ebook_reader_probe PRIVATE cxx_std_17)
  target_include_directories(crisp_ebook_reader_probe SYSTEM PRIVATE ${WEBKITGTK_INCLUDE_DIRS})
  target_compile_options(crisp_ebook_reader_probe PRIVATE ${WEBKITGTK_CFLAGS_OTHER}
    -Wno-deprecated-declarations)
  target_link_libraries(crisp_ebook_reader_probe PRIVATE PkgConfig::GTK PkgConfig::GMODULE)
  add_dependencies(${PLUGIN_NAME} crisp_ebook_reader_probe)
  # Flutter deletes its bundle during the top-level install. Install the helper
  # afterward, as an executable target rather than a bundled-library FILES entry
  # (which would lose execute permissions). Literal args survive deferred scope.
  cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL
    install TARGETS crisp_ebook_reader_probe RUNTIME DESTINATION lib
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE COMPONENT Runtime)
  message(STATUS "crisp_ebook_reader: WebKitGTK4.1 host and isolated startup helper enabled")
else()
  message(STATUS "crisp_ebook_reader: portable-only build (WebKitGTK4.1 >=2.48.4 headers and CMake >=3.19 are required)")
endif()

# Never copy a partial browser runtime into Flutter's bundle. Distribution
# packages provide WebKit, its subprocesses, sandbox helper and security updates.
set(crisp_ebook_reader_bundled_libraries "" PARENT_SCOPE)
