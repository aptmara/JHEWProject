/**
 * @file Shader.hlsl
 * @brief 三角形描画に用いる頂点・ピクセルシェーダー。
 * @author 山内陽
 */

cbuffer Globals : register(b0)
{
    float4 Tint;        // xyz にティント色を格納 (w は未使用)
    float2 Screen;      // 画面サイズ
    float2 Pad0;        // アライメント調整
    float4x4 Mvp;       // 2D モデルビュー射影行列
};

struct VSInput
{
    float3 pos : POSITION;
    float3 col : COLOR;
};

struct VSOutput
{
    float4 pos : SV_POSITION;
    float3 col : COLOR;
};

/**
 * @brief 頂点を MVP 行列で変換しティントを適用する頂点シェーダー。
 * @param input 頂点属性。
 * @return シェーダーステージへ送る出力。
 */
VSOutput VSMain(VSInput input)
{
    VSOutput o;
    float4 p = float4(input.pos, 1.0f);
    o.pos = mul(p, Mvp);
    o.col = input.col * Tint.rgb;
    return o;
}

/**
 * @brief 頂点シェーダー出力の色をそのまま描画するピクセルシェーダー。
 * @param input 補間済み属性。
 * @return 出力カラー。
 */
float4 PSMain(VSOutput input) : SV_TARGET
{
    return float4(input.col, 1.0f);
}
