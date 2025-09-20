#pragma once
#include "Settings.h"

#include <chrono>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <vector>
#include <windows.h>
#include <wrl.h>

/**
 * @file DxApp.h
 * @brief Direct3D 11 レンダラーのインターフェースを宣言するヘッダー。
 * @author 山内陽
 */

/**
 * @brief Direct3D デバイスと描画ループを管理するアプリケーションクラス。
 */
class DxApp
{
public:
    /**
     * @brief Direct3D と ImGui の初期化を行う。
     * @param hWnd 連携するウィンドウハンドル。
     * @param width 初期ウィンドウ幅 (ピクセル)。
     * @param height 初期ウィンドウ高さ (ピクセル)。
     * @return すべての初期化に成功した場合は true。
     */
    bool Init(HWND hWnd, UINT width, UINT height);

    /**
     * @brief ウィンドウサイズ変更に合わせてバッファを再作成する。
     * @param width 新しい幅 (ピクセル)。
     * @param height 新しい高さ (ピクセル)。
     */
    void OnResize(UINT width, UINT height);

    /**
     * @brief 1 フレーム分の描画と UI 更新を処理する。
     */
    void Render();

private:
    /**
     * @brief デバイスとスワップチェーンを生成する。
     * @param hWnd 描画先ウィンドウハンドル。
     * @param width バックバッファ幅。
     * @param height バックバッファ高さ。
     * @return 作成に成功した場合は true。
     */
    bool CreateDeviceAndSwapChain(HWND hWnd, UINT width, UINT height);

    /**
     * @brief バックバッファからレンダーターゲットビューを構築する。
     * @return 作成に成功した場合は true。
     */
    bool CreateRenderTarget();

    /**
     * @brief レンダーターゲットビューを解放する。
     */
    void ReleaseRenderTarget();

    /**
     * @brief 三角形描画用の頂点バッファと入力レイアウトを生成する。
     * @return 作成に成功した場合は true。
     */
    bool CreateTriangleResources();

    /**
     * @brief HLSL シェーダーを読み込みコンパイルする。
     * @return コンパイルと作成に成功した場合は true。
     */
    bool LoadShaders();

    /**
     * @brief 定数バッファを作成する。
     * @return 作成に成功した場合は true。
     */
    bool CreateConstantBuffer();

    /**
     * @brief 設定値をランタイム状態へ反映する。
     * @param onDemandReload 手動リロードで呼ばれた場合は true。
     */
    void UpdateFromSettings(bool onDemandReload);

    /**
     * @brief 設定編集用の ImGui ウィジェットを描画する。
     */
    void DrawImGui();

    /**
     * @brief 指定ウィンドウで ImGui を初期化する。
     * @param hWnd ImGui が利用するウィンドウハンドル。
     */
    void InitImGui(HWND hWnd);

    /**
     * @brief ImGui のリソースを破棄する。
     */
    void ShutdownImGui();

    /**
     * @brief 初期化以降の経過秒数を取得する。
     * @return 経過秒数。
     */
    float ElapsedSeconds();

private:
    Microsoft::WRL::ComPtr<ID3D11Device> m_device;         // Direct3D デバイス
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> m_context; // 即時コンテキスト
    Microsoft::WRL::ComPtr<IDXGISwapChain> m_swapChain;    // スワップチェーン
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView> m_rtv;  // レンダーターゲットビュー

    Microsoft::WRL::ComPtr<ID3D11Buffer> m_vb;               // 三角形用頂点バッファ
    Microsoft::WRL::ComPtr<ID3D11InputLayout> m_inputLayout; // 入力レイアウト
    Microsoft::WRL::ComPtr<ID3D11VertexShader> m_vs;         // 頂点シェーダー
    Microsoft::WRL::ComPtr<ID3D11PixelShader> m_ps;          // ピクセルシェーダー

    Microsoft::WRL::ComPtr<ID3D11Buffer> m_cb; // シェーダー用定数バッファ

    UINT m_width = 0;  // バックバッファ幅
    UINT m_height = 0; // バックバッファ高さ

    Settings m_settings;                                 // 設定ファイル管理
    std::chrono::steady_clock::time_point m_start{};     // 起動時刻
    std::chrono::steady_clock::time_point m_lastCheck{}; // 設定ファイル最終確認時刻
    int m_hotReloadIntervalMs = 500;                     // ホットリロード間隔 (ミリ秒)

    int m_vsync = 1;                           // VSync 設定 (0/1)
    float m_clear[4]{0.05f, 0.1f, 0.2f, 1.0f}; // クリアカラー RGBA
    float m_scale = 1.0f;                      // 三角形スケール係数
    float m_speed = 1.0f;                      // 回転速度係数
    float m_tint[3]{1.f, 1.f, 1.f};            // 色調補正係数
};
