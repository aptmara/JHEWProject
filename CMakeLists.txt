cmake_minimum_required(VERSION 3.20)
project(D3D11Sample LANGUAGES CXX)


if (NOT MSVC)
  message(FATAL_ERROR "This sample requires MSVC on Windows.")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- App sources
set(SRC
    src/WinMain.cpp
    src/DxApp.h
    src/DxApp.cpp
    src/Settings.h
    src/Settings.cpp
)

# ---- ImGui sources (vendor)
set(IMGUI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor/imgui)
set(IMGUI_SRC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_dx11.cpp
    ${IMGUI_DIR}/backends/imgui_impl_win32.cpp
)

add_executable(D3D11Sample WIN32 ${SRC} ${IMGUI_SRC})
add_compile_options("$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")

target_include_directories(D3D11Sample PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
)

target_compile_definitions(D3D11Sample PRIVATE UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(D3D11Sample PRIVATE d3d11 dxgi d3dcompiler)

set_target_properties(D3D11Sample PROPERTIES
    VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# Shader & settings.ini を出力先へコピー
add_custom_command(
    TARGET D3D11Sample POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/src/Shader.hlsl"
            "${CMAKE_CURRENT_BINARY_DIR}/Shader.hlsl"
)
add_custom_command(
    TARGET D3D11Sample POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/settings.ini"
            "${CMAKE_CURRENT_BINARY_DIR}/settings.ini"
)

# --- MSVC で UTF-8 を強制（ターゲット毎） ---
if (MSVC)
  target_compile_options(D3D11Sample PRIVATE /utf-8 /permissive-)
  add_definitions(-DUNICODE -D_UNICODE)  # ワイドAPIを確実化（既に定義済みなら無害）
endif()
