#===----------------------------------------------------------------------===#
#
# Agora's build for the System UI.
#
# **THE SYSTEM UI IS A CLIENT, AND THAT IS THE POINT.** The window server owns the menu bar's global portion — the
# strip, the System menu's square and the mark inside it — because that is furniture no application owns. But a MENU is
# text, a highlight chip and a tracking loop, and all three are the AppKit's: so the menu itself belongs to this
# process, which draws it with the same toolkit every application draws with, and is composited as an ordinary window
# at the pop-up level. The server forwards the square's click (`agora_shell.system_menu_invoked`, version 19) and does
# nothing else about it.
#
# It consumes the AppKit as a built package and installs none of its own; its one output is `SystemUI.app`.
#
#===----------------------------------------------------------------------===#

cmake_minimum_required(VERSION 3.24)

project(AgoraSystemUI VERSION 0.1.0 LANGUAGES C OBJC)

include(GNUInstallDirs)

set(CMAKE_POSITION_INDEPENDENT_CODE YES)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

find_package(AgoraApp CONFIG REQUIRED)

add_executable(SystemUI
    src/main.m)

target_include_directories(SystemUI PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(SystemUI PRIVATE AgoraApp::App)

# ---------------------------------------------------------------------------
# WHICH CHECKOUT THIS IS, FOR THE ABOUT PANEL'S OWN LINE. `Agora <version>` is the only version a from-source desktop
# has: the tag (or the commit) the session was built from. A release build passes `AWS_AGORA_VERSION`; a development
# build asks git; a build outside any checkout says "unknown" rather than inventing a number.
# ---------------------------------------------------------------------------
set(AWS_AGORA_VERSION "" CACHE STRING "the Agora version this build reports (empty: ask git, then 'unknown')")
if(NOT AWS_AGORA_VERSION)
  execute_process(COMMAND git -C "${CMAKE_CURRENT_SOURCE_DIR}/.." describe --tags --always --dirty
    OUTPUT_VARIABLE _agora_describe OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE _agora_git)
  if(_agora_git EQUAL 0 AND _agora_describe)
    set(AWS_AGORA_VERSION "${_agora_describe}")
  else()
    set(AWS_AGORA_VERSION "unknown")
  endif()
endif()
target_compile_definitions(SystemUI PRIVATE AWS_AGORA_VERSION="${AWS_AGORA_VERSION}" SYSUI_UI_FONT_AWARE)
message(STATUS "systemui: Agora version reported by About this Computer: ${AWS_AGORA_VERSION}")

# ---------------------------------------------------------------------------
# The bundle: SystemUI.app/Contents/{Info.plist, <platform>/<arch>/SystemUI}
# ---------------------------------------------------------------------------
# **THE DIRECTORY NAMES ARE libagora-core'S VOCABULARY, NOT CMAKE'S** — the same rule the Dock's and Workspace's builds
# state, and the same reason: the resolver spells the platform `Linux`, `FreeBSD`, `NetBSD`, `OpenBSD`, `DragonFly` or
# `MacOS` and the architecture `amd64`, `arm64`, `riscv64`, `i386` or `ppc64`, and a bundle laid out in CMake's
# spelling is one this tree cannot launch.
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_bundle_platform "MacOS")
elseif(CMAKE_SYSTEM_NAME MATCHES "^(Linux|FreeBSD|NetBSD|OpenBSD|DragonFly)$")
    set(_bundle_platform "${CMAKE_SYSTEM_NAME}")
else()
    message(FATAL_ERROR
        "SystemUI: no bundle platform directory is named for ${CMAKE_SYSTEM_NAME}. Add the name to "
        "_CFBundleCopyPrimaryPlatformDirectoryName() in libagora-core first, so the resolver and the build "
        "cannot disagree.")
endif()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
    set(_bundle_arch "amd64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    set(_bundle_arch "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^riscv64$")
    set(_bundle_arch "riscv64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(i[3-6]86|x86)$")
    set(_bundle_arch "i386")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ppc64|ppc64le|powerpc64)$")
    set(_bundle_arch "ppc64")
else()
    message(FATAL_ERROR
        "SystemUI: no bundle architecture directory is named for ${CMAKE_SYSTEM_PROCESSOR}. Add the name to "
        "_CFBundleCopyArchitectureDirectoryNames() in libagora-core first.")
endif()

set(_bundle "${CMAKE_BINARY_DIR}/SystemUI.app")
set(SYSTEMUI_BUNDLE_EXECUTABLE "${_bundle}/Contents/${_bundle_platform}/${_bundle_arch}/SystemUI")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in" "${_bundle}/Contents/Info.plist" @ONLY)
add_custom_command(TARGET SystemUI POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E remove -f "${_bundle}/Contents/MacOS/SystemUI"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${_bundle}/Contents/${_bundle_platform}/${_bundle_arch}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$<TARGET_FILE:SystemUI>"
            "${SYSTEMUI_BUNDLE_EXECUTABLE}"
    VERBATIM)

# **THE TESTS ARE A DEVELOPMENT ARTEFACT, AND A RELEASE DOES NOT BUILD THEM.**
include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
