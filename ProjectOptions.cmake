include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(myrepo_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(myrepo_setup_options)
  option(myrepo_ENABLE_HARDENING "Enable hardening" ON)
  option(myrepo_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    myrepo_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    myrepo_ENABLE_HARDENING
    OFF)

  myrepo_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR myrepo_PACKAGING_MAINTAINER_MODE)
    option(myrepo_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(myrepo_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(myrepo_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(myrepo_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(myrepo_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(myrepo_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(myrepo_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(myrepo_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(myrepo_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(myrepo_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(myrepo_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(myrepo_ENABLE_PCH "Enable precompiled headers" OFF)
    option(myrepo_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(myrepo_ENABLE_IPO "Enable IPO/LTO" ON)
    option(myrepo_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(myrepo_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(myrepo_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(myrepo_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(myrepo_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(myrepo_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(myrepo_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(myrepo_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(myrepo_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(myrepo_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(myrepo_ENABLE_PCH "Enable precompiled headers" OFF)
    option(myrepo_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      myrepo_ENABLE_IPO
      myrepo_WARNINGS_AS_ERRORS
      myrepo_ENABLE_USER_LINKER
      myrepo_ENABLE_SANITIZER_ADDRESS
      myrepo_ENABLE_SANITIZER_LEAK
      myrepo_ENABLE_SANITIZER_UNDEFINED
      myrepo_ENABLE_SANITIZER_THREAD
      myrepo_ENABLE_SANITIZER_MEMORY
      myrepo_ENABLE_UNITY_BUILD
      myrepo_ENABLE_CLANG_TIDY
      myrepo_ENABLE_CPPCHECK
      myrepo_ENABLE_COVERAGE
      myrepo_ENABLE_PCH
      myrepo_ENABLE_CACHE)
  endif()

  myrepo_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (myrepo_ENABLE_SANITIZER_ADDRESS OR myrepo_ENABLE_SANITIZER_THREAD OR myrepo_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(myrepo_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(myrepo_global_options)
  if(myrepo_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    myrepo_enable_ipo()
  endif()

  myrepo_supports_sanitizers()

  if(myrepo_ENABLE_HARDENING AND myrepo_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR myrepo_ENABLE_SANITIZER_UNDEFINED
       OR myrepo_ENABLE_SANITIZER_ADDRESS
       OR myrepo_ENABLE_SANITIZER_THREAD
       OR myrepo_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${myrepo_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${myrepo_ENABLE_SANITIZER_UNDEFINED}")
    myrepo_enable_hardening(myrepo_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(myrepo_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(myrepo_warnings INTERFACE)
  add_library(myrepo_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  myrepo_set_project_warnings(
    myrepo_warnings
    ${myrepo_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(myrepo_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    myrepo_configure_linker(myrepo_options)
  endif()

  include(cmake/Sanitizers.cmake)
  myrepo_enable_sanitizers(
    myrepo_options
    ${myrepo_ENABLE_SANITIZER_ADDRESS}
    ${myrepo_ENABLE_SANITIZER_LEAK}
    ${myrepo_ENABLE_SANITIZER_UNDEFINED}
    ${myrepo_ENABLE_SANITIZER_THREAD}
    ${myrepo_ENABLE_SANITIZER_MEMORY})

  set_target_properties(myrepo_options PROPERTIES UNITY_BUILD ${myrepo_ENABLE_UNITY_BUILD})

  if(myrepo_ENABLE_PCH)
    target_precompile_headers(
      myrepo_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(myrepo_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    myrepo_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(myrepo_ENABLE_CLANG_TIDY)
    myrepo_enable_clang_tidy(myrepo_options ${myrepo_WARNINGS_AS_ERRORS})
  endif()

  if(myrepo_ENABLE_CPPCHECK)
    myrepo_enable_cppcheck(${myrepo_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(myrepo_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    myrepo_enable_coverage(myrepo_options)
  endif()

  if(myrepo_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(myrepo_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(myrepo_ENABLE_HARDENING AND NOT myrepo_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR myrepo_ENABLE_SANITIZER_UNDEFINED
       OR myrepo_ENABLE_SANITIZER_ADDRESS
       OR myrepo_ENABLE_SANITIZER_THREAD
       OR myrepo_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    myrepo_enable_hardening(myrepo_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
