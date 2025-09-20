# D3D11Sample

Direct3D 11 と ImGui を組み合わせ、`settings.ini` とリアルタイムに同期しながら描画パラメーターを編集できるサンプルです。Visual Studio 2022 の CMake プロジェクトとして構成しており、ホットリロードや ImGui ウィジェットの操作を通じて D3D11 の基本を確認できます。

## 対応環境
- Windows 10 / 11 (64bit)
- Visual Studio 2022 （C++ によるデスクトップ開発ワークロード）
- CMake 3.20 以上
- PowerShell 5.1 以降（`scripts\get_imgui.ps1` の実行に使用）

## 初期セットアップ
1. 必要であればリポジトリを取得します。
2. ImGui をダウンロードして `vendor\imgui` に配置します。既存の内容が古い場合は上書きしてください。
   ```powershell
   pwsh scripts\get_imgui.ps1           # 既定では v1.90.9 を取得
   # 任意のバージョンを明示する例
   pwsh scripts\get_imgui.ps1 -Version v1.90.9
   ```
   スクリプトは一時フォルダーに Zip を展開し、必要なコアファイルと DX11/Win32 バックエンドだけを `vendor\imgui` にコピーします（MIT License）。

## ビルド手順
### Visual Studio 2022 からビルドする場合
1. Visual Studio を起動し、[フォルダーを開く] からこのディレクトリを選択します。
2. 初回は CMake の自動構成が走り、`out\build\x64-Debug`（既定のキヤッシュ）にビルドディレクトリが作成されます。
3. 表示された CMake Targets から `D3D11Sample` を既定のスタートアップ項目に設定し、[ローカル Windows デバッガー] を実行します。

### CMake コマンドラインからビルドする場合
```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Debug
```
`cmake --build` の出力は `build/Debug/D3D11Sample.exe` に生成されます。

## 実行
- Visual Studio で [ローカル Windows デバッガー] を開始するか、生成された `D3D11Sample.exe`（Debug または Release）を直接起動してください。
- CMake の自動構成を利用した場合は `out\build\x64-Debug\D3D11Sample.exe` が既定の出力先です。

## 機能と操作
- 初回起動時に 1280x720 のウィンドウを生成し、Direct3D 11 で三角形を描画します。
- ImGui の "Settings" ウィンドウから以下をリアルタイムに調整できます。
  - VSync の有効 / 無効
  - 背景クリアカラー (RGBA)
  - 三角形の回転速度・スケール
  - 三角形の色味 (Tint)
- [Save to settings.ini] ボタンで `settings.ini` に保存。
- [Reload from settings.ini] ボタン、`R` キー、または外部エディタで `settings.ini` を更新するとホットリロードが掛かります（既定 500ms 間隔で変更監視）。
- 描画時にはシェーダー用の定数バッファを更新し、ImGui の描画データを Direct3D 11 パイプラインに送っています。

## 設定ファイル (`settings.ini`)
| セクション | キー | 説明 |
| --- | --- | --- |
| `[Render]` | `VSync` | 1 で垂直同期を有効化、0 で無効化 |
|  | `HotReloadIntervalMs` | ファイル監視の間隔（ミリ秒） |
| `[Clear]` | `R`,`G`,`B`,`A` | クリアカラー (0.0–1.0) |
| `[Triangle]` | `Scale` | 三角形のスケール |
|  | `RotationSpeed` | 回転速度（弧度 / 秒） |
|  | `TintR`,`TintG`,`TintB` | 三角形の色味 |

設定値はアプリ起動時およびホットリロード時に読み込まれ、ImGui からの変更は即座にファイルへ書き戻されます。

## ディレクトリ構成
- `src/` … `DxApp`, `Settings`, `Shader.hlsl` などアプリ本体のソース
- `scripts/` … 依存関係取得用スクリプト
- `vendor/imgui/` … `get_imgui.ps1` で取得する ImGui 本体とバックエンド
- `build/`, `out/` … CMake / Visual Studio が生成するビルド成果物

## 補足
- `Shader.hlsl` と `settings.ini` はビルド時に出力ディレクトリへコピーされます。Visual Studio のデバッガー作業ディレクトリは `CMAKE_BINARY_DIR` に設定済みです。
- 必要に応じて Release 構成へ切り替えてビルドしてください。
