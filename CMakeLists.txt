cmake_minimum_required(VERSION 4.0)
project(SCU_DataStructure_TextEditor VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# 控制台编辑器；离线可视化页面无需构建。
add_executable(editor
        src/main.cpp
        src/platform.cpp
        src/line_buffer.cpp
        src/memory_counters.cpp
        src/line_list.cpp
        src/fileio.cpp
        src/editor.cpp
        src/commands.cpp
        src/trace.cpp)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(editor PRIVATE -Wall -Wextra)
endif()
