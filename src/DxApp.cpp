/**
 * @file DxApp.cpp
 * @brief Direct3D 11 アプリケーションラッパーの実装。
 * @author 山内陽
 */

#include "DxApp.h"
#include <cassert>
#include <string>
#include <cmath>

#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"

using Microsoft::WRL::ComPtr;

extern LRESULT ImGui_ImplWin32_WndProcHandler(HWND, UINT, WPARAM, LPARAM);

/**
 * @brief 位置と色を保持する頂点構造体。
 */
struct Vertex
{
    float pos[3]; // 位置
    float col[3]; // 色
};

/**
 * @brief シェーダーと共有する定数バッファのレイアウト。
 */
struct CBData
{
    float Tint[4];   // 色調係数 (w は未使用)
    float Screen[2]; // 画面サイズ
    float Pad0[2];   // アライメント調整用パディング
    float Mvp[16];   // モデルビュー射影行列
};

/**
 * @brief Z 軸回転と等方スケールを組み合わせた行列を生成する。
 * @param out16 16 要素の出力配列。
 * @param angle 回転角 (ラジアン)。
 * @param scale 一様スケール係数。
 */
static void MakeZRotateScale(float* out16, float angle, float scale)
{
    const float c = std::cos(angle) * scale;
    const float s = std::sin(angle) * scale;
    float m[16] = {
         c,  s, 0, 0,
        -s,  c, 0, 0,
         0,  0, 1, 0,
         0,  0, 0, 1
    };
    std::copy(std::begin(m), std::end(m), out16);
}

/**
 * @brief デバイス・スワップチェーン・シェーダー・UI を初期化する。
 * @param hWnd レンダラーに関連付けるウィンドウハンドル。
 * @param width バックバッファ幅 (ピクセル)。
 * @param height バックバッファ高さ (ピクセル)。
 * @return すべての初期化に成功した場合は true。
 */
bool DxApp::Init(HWND hWnd, UINT width, UINT height)
{
    m_width = width;
    m_height = height;

    m_settings.Load(L"settings.ini");
    UpdateFromSettings(false);
    m_start = std::chrono::steady_clock::now();
    m_lastCheck = m_start;

    if (!CreateDeviceAndSwapChain(hWnd, width, height)) return false;
    if (!CreateRenderTarget()) return false;
    if (!LoadShaders()) return false;
    if (!CreateTriangleResources()) return false;
    if (!CreateConstantBuffer()) return false;

    InitImGui(hWnd);

    D3D11_VIEWPORT vp{};
    vp.TopLeftX = 0.0f;
    vp.TopLeftY = 0.0f;
    vp.Width    = static_cast<float>(m_width);
    vp.Height   = static_cast<float>(m_height);
    vp.MinDepth = 0.0f;
    vp.MaxDepth = 1.0f;
    m_context->RSSetViewports(1, &vp);

    return true;
}

/**
 * @brief Direct3D コンテキスト上で ImGui を動作させるよう構成する。
 * @param hWnd ホストとなるウィンドウハンドル。
 */
void DxApp::InitImGui(HWND hWnd)
{
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::StyleColorsDark();
    ImGui_ImplWin32_Init(hWnd);
    ImGui_ImplDX11_Init(m_device.Get(), m_context.Get());
}

/**
 * @brief Direct3D と関連付いた ImGui リソースをすべて解放する。
 */
void DxApp::ShutdownImGui()
{
    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();
}

/**
 * @brief Direct3D デバイス・コンテキスト・スワップチェーンを生成する。
 * @param hWnd プレゼンテーションに使用するウィンドウハンドル。
 * @param width 希望するバックバッファ幅。
 * @param height 希望するバックバッファ高さ。
 * @return 生成に成功した場合は true。
 */
bool DxApp::CreateDeviceAndSwapChain(HWND hWnd, UINT width, UINT height)
{
    DXGI_SWAP_CHAIN_DESC sd{};
    sd.BufferCount      = 2;
    sd.BufferDesc.Format= DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferUsage      = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow     = hWnd;
    sd.SampleDesc.Count = 1;
    sd.Windowed         = TRUE;
    sd.SwapEffect       = DXGI_SWAP_EFFECT_DISCARD;
    sd.BufferDesc.Width = width;
    sd.BufferDesc.Height= height;

    UINT deviceFlags = 0;
#if defined(_DEBUG)
    deviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

    D3D_FEATURE_LEVEL req[] = {
        D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
    };
    D3D_FEATURE_LEVEL got{};

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, deviceFlags,
        req, _countof(req), D3D11_SDK_VERSION,
        &sd, m_swapChain.GetAddressOf(), m_device.GetAddressOf(), &got, m_context.GetAddressOf());

    if (FAILED(hr)) {
        hr = D3D11CreateDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_WARP, nullptr, deviceFlags,
            req, _countof(req), D3D11_SDK_VERSION,
            &sd, m_swapChain.GetAddressOf(), m_device.GetAddressOf(), &got, m_context.GetAddressOf());
    }
    return SUCCEEDED(hr);
}

/**
 * @brief バックバッファを取得しレンダーターゲットビューを作成する。
 * @return ビューの用意に成功した場合は true。
 */
bool DxApp::CreateRenderTarget()
{
    ComPtr<ID3D11Texture2D> backBuf;
    HRESULT hr = m_swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(backBuf.GetAddressOf()));
    if (FAILED(hr)) return false;
    hr = m_device->CreateRenderTargetView(backBuf.Get(), nullptr, m_rtv.GetAddressOf());
    return SUCCEEDED(hr);
}

/**
 * @brief 現在のレンダーターゲットビューを安全に解放する。
 */
void DxApp::ReleaseRenderTarget()
{
    if (m_rtv) m_rtv.Reset();
}

/**
 * @brief WM_SIZE に応じてスワップチェーンとビューポートを再設定する。
 * @param width 更新後の幅 (ピクセル)。
 * @param height 更新後の高さ (ピクセル)。
 */
void DxApp::OnResize(UINT width, UINT height)
{
    if (!m_swapChain) return;
    m_width = width; m_height = height;

    m_context->OMSetRenderTargets(0, nullptr, nullptr);
    ReleaseRenderTarget();

    if (FAILED(m_swapChain->ResizeBuffers(0, width, height, DXGI_FORMAT_UNKNOWN, 0))) return;
    if (!CreateRenderTarget()) return;

    D3D11_VIEWPORT vp{};
    vp.TopLeftX = 0; vp.TopLeftY = 0;
    vp.Width = (float)m_width; vp.Height = (float)m_height;
    vp.MinDepth = 0; vp.MaxDepth = 1;
    m_context->RSSetViewports(1, &vp);
}

/**
 * @brief 頂点／ピクセルシェーダーをソースからコンパイルして生成する。
 * @return 両方のシェーダーが生成できた場合は true。
 */
bool DxApp::LoadShaders()
{
    const std::wstring shaderFile = L"Shader.hlsl";
    UINT compileFlags = 0;
#if defined(_DEBUG)
    compileFlags |= D3DCOMPILE_DEBUG | D3DCOMPILE_SKIP_OPTIMIZATION;
#endif
    ComPtr<ID3DBlob> vs, ps, err;

    HRESULT hr = D3DCompileFromFile(shaderFile.c_str(), nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE,
        "VSMain", "vs_5_0", compileFlags, 0, vs.GetAddressOf(), err.GetAddressOf());
    if (FAILED(hr)) { if (err) OutputDebugStringA((char*)err->GetBufferPointer()); return false; }

    hr = D3DCompileFromFile(shaderFile.c_str(), nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE,
        "PSMain", "ps_5_0", compileFlags, 0, ps.GetAddressOf(), err.ReleaseAndGetAddressOf());
    if (FAILED(hr)) { if (err) OutputDebugStringA((char*)err->GetBufferPointer()); return false; }

    if (FAILED(m_device->CreateVertexShader(vs->GetBufferPointer(), vs->GetBufferSize(), nullptr, m_vs.GetAddressOf()))) return false;
    if (FAILED(m_device->CreatePixelShader (ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, m_ps.GetAddressOf()))) return false;

    D3D11_INPUT_ELEMENT_DESC layout[] = {
        { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, offsetof(Vertex,pos), D3D11_INPUT_PER_VERTEX_DATA, 0 },
        { "COLOR",    0, DXGI_FORMAT_R32G32B32_FLOAT, 0, offsetof(Vertex,col), D3D11_INPUT_PER_VERTEX_DATA, 0 },
    };
    return SUCCEEDED(m_device->CreateInputLayout(layout, _countof(layout), vs->GetBufferPointer(), vs->GetBufferSize(), m_inputLayout.GetAddressOf()));
}

/**
 * @brief デモ三角形で用いる頂点バッファと入力レイアウトを構築する。
 * @return リソース生成に成功した場合は true。
 */
bool DxApp::CreateTriangleResources()
{
    Vertex v[] = {
        { {  0.0f,  0.5f, 0.0f }, { 1.f, 0.f, 0.f } },
        { {  0.5f, -0.5f, 0.0f }, { 0.f, 1.f, 0.f } },
        { { -0.5f, -0.5f, 0.0f }, { 0.f, 0.f, 1.f } },
    };
    D3D11_BUFFER_DESC bd{};
    bd.Usage = D3D11_USAGE_DEFAULT;
    bd.ByteWidth = sizeof(v);
    bd.BindFlags = D3D11_BIND_VERTEX_BUFFER;
    D3D11_SUBRESOURCE_DATA init{ v };
    return SUCCEEDED(m_device->CreateBuffer(&bd, &init, m_vb.GetAddressOf()));
}

/**
 * @brief シェーダー間で共有する動的定数バッファを確保する。
 * @return バッファ生成に成功した場合は true。
 */
bool DxApp::CreateConstantBuffer()
{
    D3D11_BUFFER_DESC bd{};
    bd.Usage = D3D11_USAGE_DYNAMIC;
    bd.ByteWidth = sizeof(CBData);
    bd.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    bd.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
    return SUCCEEDED(m_device->CreateBuffer(&bd, nullptr, m_cb.GetAddressOf()));
}

/**
 * @brief 初期化以降の経過時間を算出する。
 * @return 起動からの経過秒数。
 */
float DxApp::ElapsedSeconds()
{
    auto now = std::chrono::steady_clock::now();
    std::chrono::duration<float> d = now - m_start;
    return d.count();
}

/**
 * @brief 永続化された設定値をランタイムパラメータへ反映する。
 * @param onDemandReload 手動リロード操作による呼び出しなら true。
 */
void DxApp::UpdateFromSettings(bool onDemandReload)
{
    if (onDemandReload) m_settings.ReloadIfChanged();

    m_vsync = m_settings.GetBool("Render", "VSync", true) ? 1 : 0;
    m_hotReloadIntervalMs = m_settings.GetInt("Render", "HotReloadIntervalMs", 500);

    m_clear[0] = (float)m_settings.GetDouble("Clear", "R", 0.05);
    m_clear[1] = (float)m_settings.GetDouble("Clear", "G", 0.10);
    m_clear[2] = (float)m_settings.GetDouble("Clear", "B", 0.20);
    m_clear[3] = (float)m_settings.GetDouble("Clear", "A", 1.0);

    m_scale = (float)m_settings.GetDouble("Triangle", "Scale", 1.0);
    m_speed = (float)m_settings.GetDouble("Triangle", "RotationSpeed", 1.0);
    m_tint[0] = (float)m_settings.GetDouble("Triangle", "TintR", 1.0);
    m_tint[1] = (float)m_settings.GetDouble("Triangle", "TintG", 1.0);
    m_tint[2] = (float)m_settings.GetDouble("Triangle", "TintB", 1.0);
}

/**
 * @brief 設定 UI を描画し変更があれば保存する。
 */
void DxApp::DrawImGui()
{
    ImGui_ImplDX11_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    bool changed = false;

    if (ImGui::Begin("Settings (INI <-> GUI)")) {
        if (ImGui::CollapsingHeader("Render", ImGuiTreeNodeFlags_DefaultOpen)) {
            bool vsync = m_vsync != 0;
            if (ImGui::Checkbox("VSync", &vsync)) {
                m_vsync = vsync ? 1 : 0;
                m_settings.SetBool("Render", "VSync", vsync);
                changed = true;
            }
            int interval = m_hotReloadIntervalMs;
            if (ImGui::SliderInt("HotReloadIntervalMs", &interval, 100, 2000)) {
                m_hotReloadIntervalMs = interval;
                m_settings.SetInt("Render", "HotReloadIntervalMs", interval);
                changed = true;
            }
        }

        if (ImGui::CollapsingHeader("Clear", ImGuiTreeNodeFlags_DefaultOpen)) {
            if (ImGui::ColorEdit4("ClearColor", m_clear)) {
                m_settings.SetDouble("Clear", "R", m_clear[0]);
                m_settings.SetDouble("Clear", "G", m_clear[1]);
                m_settings.SetDouble("Clear", "B", m_clear[2]);
                m_settings.SetDouble("Clear", "A", m_clear[3]);
                changed = true;
            }
        }

        if (ImGui::CollapsingHeader("Triangle", ImGuiTreeNodeFlags_DefaultOpen)) {
            if (ImGui::SliderFloat("Scale", &m_scale, 0.1f, 5.0f)) {
                m_settings.SetDouble("Triangle", "Scale", m_scale);
                changed = true;
            }
            if (ImGui::SliderFloat("RotationSpeed", &m_speed, -10.0f, 10.0f)) {
                m_settings.SetDouble("Triangle", "RotationSpeed", m_speed);
                changed = true;
            }
            if (ImGui::ColorEdit3("Tint", m_tint)) {
                m_settings.SetDouble("Triangle", "TintR", m_tint[0]);
                m_settings.SetDouble("Triangle", "TintG", m_tint[1]);
                m_settings.SetDouble("Triangle", "TintB", m_tint[2]);
                changed = true;
            }
        }

        ImGui::Separator();
        if (ImGui::Button("Save to settings.ini")) {
            changed = true;
        }
        ImGui::SameLine();
        if (ImGui::Button("Reload from settings.ini")) {
            m_settings.Load(L"settings.ini");
            UpdateFromSettings(false);
        }
        ImGui::TextUnformatted("Hint: R key or external edit triggers reload too.");
    }
    ImGui::End();

    if (changed) {
        m_settings.Save();
    }

    ImGui::Render();
    ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());
}

/**
 * @brief 毎フレームの更新と描画、表示処理をまとめて実行する。
 */
void DxApp::Render()
{
    auto now = std::chrono::steady_clock::now();
    if (std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastCheck).count() >= m_hotReloadIntervalMs
        || (GetAsyncKeyState('R') & 1))
    {
        if (m_settings.ReloadIfChanged()) {
            UpdateFromSettings(false);
            OutputDebugStringW(L"[Settings] Reloaded settings.ini\n");
        }
        m_lastCheck = now;
    }

    m_context->OMSetRenderTargets(1, m_rtv.GetAddressOf(), nullptr);
    m_context->ClearRenderTargetView(m_rtv.Get(), m_clear);

    D3D11_MAPPED_SUBRESOURCE mapped{};
    if (SUCCEEDED(m_context->Map(m_cb.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        auto* cb = reinterpret_cast<CBData*>(mapped.pData);
        cb->Tint[0]=m_tint[0]; cb->Tint[1]=m_tint[1]; cb->Tint[2]=m_tint[2]; cb->Tint[3]=0;
        cb->Screen[0]=(float)m_width; cb->Screen[1]=(float)m_height;
        cb->Pad0[0]=cb->Pad0[1]=0;
        float angle = ElapsedSeconds() * m_speed;
        MakeZRotateScale(cb->Mvp, angle, m_scale);
        m_context->Unmap(m_cb.Get(), 0);
    }

    UINT stride = sizeof(Vertex), offset = 0;
    ID3D11Buffer* bufs[] = { m_vb.Get() };
    m_context->IASetVertexBuffers(0, 1, bufs, &stride, &offset);
    m_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    m_context->IASetInputLayout(m_inputLayout.Get());

    m_context->VSSetShader(m_vs.Get(), nullptr, 0);
    m_context->PSSetShader(m_ps.Get(), nullptr, 0);
    ID3D11Buffer* cbs[] = { m_cb.Get() };
    m_context->VSSetConstantBuffers(0, 1, cbs);
    m_context->PSSetConstantBuffers(0, 1, cbs);

    m_context->Draw(3, 0);

    DrawImGui();

    m_swapChain->Present(m_vsync ? 1 : 0, 0);
}
