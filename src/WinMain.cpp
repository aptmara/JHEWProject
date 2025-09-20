/**
 * @file WinMain.cpp
 * @brief アプリケーションエントリーポイントとウィンドウ手続きの実装。
 * @author 山内陽
 */

#include "DxApp.h"
#include "imgui_impl_dx11.h"
#include "imgui_impl_win32.h" // ハンドラ宣言用

#include <windows.h>

extern LRESULT ImGui_ImplWin32_WndProcHandler(HWND, UINT, WPARAM, LPARAM);

/**
 * @brief メインウィンドウ用のプロシージャ。
 * @param hWnd 対象ウィンドウハンドル。
 * @param msg メッセージ ID。
 * @param wParam パラメータ 1。
 * @param lParam パラメータ 2。
 * @return 処理後の結果コード。
 */
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    // 先に ImGui へ転送
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return true;

    DxApp* app = reinterpret_cast<DxApp*>(GetWindowLongPtr(hWnd, GWLP_USERDATA));

    switch (msg)
    {
    case WM_SIZE:
        if (app && wParam != SIZE_MINIMIZED)
        {
            UINT width = LOWORD(lParam);
            UINT height = HIWORD(lParam);
            app->OnResize(width, height);
        }
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    default:
        break;
    }
    return DefWindowProc(hWnd, msg, wParam, lParam);
}

/**
 * @brief Win32 アプリケーションのエントリーポイント。
 * @param hInst インスタンスハンドル。
 * @param unusedPrevInst 未使用。
 * @param unusedCmdLine 未使用のコマンドライン文字列。
 * @param nCmdShow 表示コマンド。
 * @return プロセスの終了コード。
 */
int APIENTRY wWinMain(HINSTANCE hInst, HINSTANCE unusedPrevInst, LPWSTR unusedCmdLine, int nCmdShow)
{
    const wchar_t* kClassName = L"D3D11SampleWindowClass";
    WNDCLASSEX wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;

    if (!RegisterClassEx(&wc))
        return -1;

    RECT rc{0, 0, 1280, 720};
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);

    HWND hWnd = CreateWindowEx(0, kClassName, L"D3D11 Sample - ImGui + INI Sync", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                               CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top, nullptr, nullptr, hInst, nullptr);

    if (!hWnd)
        return -1;

    DxApp app;
    if (!app.Init(hWnd, 1280, 720))
    {
        MessageBox(hWnd, L"Direct3D の初期化に失敗しました。", L"Error", MB_ICONERROR);
        return -1;
    }
    SetWindowLongPtr(hWnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&app));

    ShowWindow(hWnd, nCmdShow);
    UpdateWindow(hWnd);

    MSG msg{};
    while (msg.message != WM_QUIT)
    {
        if (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        else
        {
            app.Render();
        }
    }

    // 終了処理は DxApp のデストラクタで十分
    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    return static_cast<int>(msg.wParam);
}
