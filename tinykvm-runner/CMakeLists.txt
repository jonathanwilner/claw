cmake_minimum_required(VERSION 3.20)
project(openclaw_tinykvm_runner CXX)

set(TINYKVM_SOURCE "" CACHE PATH "Path to the TinyKVM source tree")

if (NOT TINYKVM_SOURCE)
  message(FATAL_ERROR "Set -DTINYKVM_SOURCE=/path/to/tinykvm when configuring this project.")
endif()

if (NOT EXISTS "${TINYKVM_SOURCE}/lib/CMakeLists.txt")
  message(FATAL_ERROR "TinyKVM lib/CMakeLists.txt was not found under ${TINYKVM_SOURCE}.")
endif()

add_subdirectory("${TINYKVM_SOURCE}/lib" tinykvm-lib)

add_executable(openclaw-tinykvm-runner
  openclaw_tinykvm_runner.cpp
)

target_compile_features(openclaw-tinykvm-runner PRIVATE cxx_std_20)
target_include_directories(openclaw-tinykvm-runner PRIVATE "${TINYKVM_SOURCE}/lib")
target_link_libraries(openclaw-tinykvm-runner PRIVATE tinykvm)
