#===----------------------------------------------------------------------===#
#
# Agora's build for Builder — the interface builder.
#
# **BUILDER IS AN APPLICATION AND NOT A FRAMEWORK.** It consumes the AppKit as a built package and installs no package of
# its own; its one output is `Builder.app`. The AppKit owns the FORMAT (`NSNib`, `NSNibSource`), so this repository owns
# the DESIGN: the document model over that format, the canvas that hosts the real views, the outline of the object graph,
# and the connections a person draws between them.
#
# **THE THREE THINGS IN THIS REPOSITORY ARE THE MODEL, THE DOCUMENT AND THE WINDOW.** `AGDesign` is the property list
# plus the `id` → live object map, and it has no view in it at all, which is what lets its suite run with no compositor.
# `AGBuilderDocument` is the `NSDocument` that reads and writes the text source. `AGBuilderWindowController` is the
# window: an outline of the graph beside a canvas that hosts the graph. See README.md for the division.
#
#===----------------------------------------------------------------------===#

cmake_minimum_required(VERSION 3.24)

project(AgoraBuilder VERSION 0.1.0 LANGUAGES C OBJC)

include(GNUInstallDirs)

set(CMAKE_POSITION_INDEPENDENT_CODE YES)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(AgoraApp CONFIG REQUIRED)

add_executable(Builder
    src/main.m
    src/AGDesign.m
    src/AGBuilderDocument.m
    src/AGBuilderWindowController.m)

target_include_directories(Builder PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(Builder PRIVATE AgoraApp::App)

# ---------------------------------------------------------------------------
# The bundle: Builder.app/Contents/{Info.plist, <platform>/<arch>/Builder}
# ---------------------------------------------------------------------------
# **THE DIRECTORY NAMES ARE libagora-core'S VOCABULARY, NOT CMAKE'S** — the same rule Dock's and Terminal's builds state:
# the resolver spells the platform `Linux`, `FreeBSD`, `NetBSD`, `OpenBSD`, `DragonFly` or `MacOS` and the architecture
# `amd64`, `arm64`, `riscv64`, `i386` or `ppc64`, and a bundle laid out in CMake's spelling is one this tree cannot launch.
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_bundle_platform "MacOS")
elseif(CMAKE_SYSTEM_NAME MATCHES "^(Linux|FreeBSD|NetBSD|OpenBSD|DragonFly)$")
    set(_bundle_platform "${CMAKE_SYSTEM_NAME}")
else()
    message(FATAL_ERROR
        "Builder: no bundle platform directory is named for ${CMAKE_SYSTEM_NAME}. Add the name to "
        "_CFBundleCopyPrimaryPlatformDirectoryName() in libagora-core first, so the resolver and the build "
        "cannot disagree.")
endif()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
    set(_bundle_arch "amd64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    set(_bundle_arch "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(riscv64)$")
    set(_bundle_arch "riscv64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(i[3-6]86|x86)$")
    set(_bundle_arch "i386")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ppc64|ppc64le|powerpc64)$")
    set(_bundle_arch "ppc64")
else()
    message(FATAL_ERROR
        "Builder: no bundle architecture directory is named for ${CMAKE_SYSTEM_PROCESSOR}. Add the name to "
        "_CFBundleCopyArchitectureDirectoryNames() in libagora-core first.")
endif()

set(_bundle "${CMAKE_BINARY_DIR}/Builder.app")
set(BUILDER_BUNDLE_EXECUTABLE "${_bundle}/Contents/${_bundle_platform}/${_bundle_arch}/Builder")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in" "${_bundle}/Contents/Info.plist" @ONLY)
add_custom_command(TARGET Builder POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E remove -f "${_bundle}/Contents/MacOS/Builder"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${_bundle}/Contents/${_bundle_platform}/${_bundle_arch}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:Builder>"
            "${BUILDER_BUNDLE_EXECUTABLE}"
    VERBATIM)

# **THE TESTS ARE A DEVELOPMENT ARTEFACT, AND A RELEASE DOES NOT BUILD THEM.** `include(CTest)` is what defines
# `BUILD_TESTING` — ON when a configure says nothing, which is what a developer's build wants — and the subdirectory is
# added only when it is on, so `-DBUILD_TESTING=OFF`, which is what the release driver passes, compiles no test at all.
include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
