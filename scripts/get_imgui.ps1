Param(
    [string]$Version = "v1.90.9"  # 必要に応じて更新
)
$ErrorActionPreference = "Stop"

$repo = "https://github.com/ocornut/imgui"
$zipUrl = "$repo/archive/refs/tags/$Version.zip"
$dstDir = Join-Path (Get-Location) "vendor\imgui"
$tmpZip = Join-Path $env:TEMP "imgui_$Version.zip"
$tmpDir = Join-Path $env:TEMP "imgui_$Version"

Write-Host "Downloading ImGui $Version from $zipUrl ..."
Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip

if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
Expand-Archive -Path $tmpZip -DestinationPath $tmpDir

$src = Get-ChildItem -Directory $tmpDir | Select-Object -First 1
$backendDir = Join-Path $src.FullName "backends"

New-Item -ItemType Directory -Force -Path "$dstDir\backends" | Out-Null

# 必須ファイルをコピー
Copy-Item "$($src.FullName)\imgui.h" $dstDir -Force
Copy-Item "$($src.FullName)\imgui.cpp" $dstDir -Force
Copy-Item "$($src.FullName)\imgui_draw.cpp" $dstDir -Force
Copy-Item "$($src.FullName)\imgui_tables.cpp" $dstDir -Force
Copy-Item "$($src.FullName)\imgui_widgets.cpp" $dstDir -Force
Copy-Item "$backendDir\imgui_impl_dx11.*" "$dstDir\backends" -Force
Copy-Item "$backendDir\imgui_impl_win32.*" "$dstDir\backends" -Force

Write-Host "ImGui files copied to $dstDir"
Remove-Item $tmpZip -Force
Remove-Item $tmpDir -Recurse -Force
