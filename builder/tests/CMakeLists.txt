# Builder's tests.
#
# **THE THING THAT CAN BE WRONG WITHOUT LOOKING WRONG IS THE MODEL.** A canvas that draws nothing, a pane two points too
# narrow and a status line that says the wrong number are all visible in one glance; a design file that loses a property,
# renames an object or writes text the compiler then refuses is invisible until somebody opens the document a week later.
# So `design_model` compiles the model, the document and the window controller as they ship and asserts MEANING with no
# window, no compositor and no pixels. The window is never instantiated: only `-makeWindowControllers` would do that, and
# this suite never opens a document on screen.

add_executable(design_model design_model.m
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/AGDesign.m"
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/AGBuilderDocument.m"
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/AGBuilderWindowController.m")
target_include_directories(design_model PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
target_link_libraries(design_model PRIVATE AgoraApp::App m)

# **THE APPKIT'S OWN PRIVATE DEPENDENCIES ARE NOT PROPAGATED AS A RUNPATH** (a shared library's DT_RUNPATH is not
# inherited), so a test that loads the AppKit has to be told where Launch Services and Icon Services are — the same reason
# Dock's and libagora-app's tests carry an `LD_LIBRARY_PATH`. The directory comes from the imported target, so this follows
# the prefix rather than naming it.
set(_builder_test_env "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:AgoraApp::App>")
add_test(NAME builder-design-model COMMAND design_model)
set_tests_properties(builder-design-model PROPERTIES ENVIRONMENT "${_builder_test_env}")
