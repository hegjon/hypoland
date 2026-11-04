cmake_minimum_required(VERSION 3.19)

project(start-hypoland DESCRIPTION "Hypoland watchdog binary")

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 26)
set(CMAKE_EXPORT_COMPILE_COMMANDS TRUE)

find_package(PkgConfig REQUIRED)

pkg_check_modules(starthyprland_deps REQUIRED IMPORTED_TARGET hyprutils>=0.10.3)

file(GLOB_RECURSE SRCFILES CONFIGURE_DEPENDS "src/*.cpp")

add_executable(start-hyprland ${SRCFILES})

target_link_libraries(start-hyprland PUBLIC PkgConfig::starthyprland_deps)

set_target_properties(start-hyprland PROPERTIES OUTPUT_NAME start-hypoland)

install(TARGETS start-hyprland)

# start-hyprland is kept as a symlink, so existing session files keep working
install(
  CODE "execute_process( \
        COMMAND ${CMAKE_COMMAND} -E create_symlink \
        start-hypoland \
        \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_BINDIR}/start-hyprland\" \
        )")

if(CMAKE_BUILD_TYPE MATCHES Debug OR CMAKE_BUILD_TYPE MATCHES DEBUG)
  set(CMAKE_EXECUTABLE_ENABLE_EXPORTS TRUE)
endif()

if(BUILD_TESTING OR WITH_TESTS)
  enable_testing()
  if(NOT Python3_Interpreter_FOUND)
    find_package(Python3 COMPONENTS Interpreter REQUIRED)
  endif()

  foreach(termination IN ITEMS exit-0 exit-23 sigterm sigkill)
    add_test(
      NAME start-hyprland-${termination}
      COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/termination.py"
              "$<TARGET_FILE:start-hyprland>" "${termination}")
    set_tests_properties(start-hyprland-${termination} PROPERTIES TIMEOUT 20)
  endforeach()
endif()
