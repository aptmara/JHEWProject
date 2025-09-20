# init-dev.ps1
# 目的:
# - 初期設定(ExecutionPolicy, .clang-format, .gitattributes, pre-commit)
# - .devtools 配下に ps1 を隠し配置し、リポジトリ直下に 2 つの .lnk（Start Work - Pull / Quick Sync + PR）を作成
# - vendor 依存(fetch script) 実行（任意）
# - CMakePresets.json 自動生成（未存在時）
# - CMake 構成＆ビルド（デフォルト実行／-NoBuild でスキップ、-ForceNinja で Ninja 強制）
#
# 実行:
#   .\init-dev.ps1
#   .\init-dev.ps1 -NoBuild
#   .\init-dev.ps1 -ForceNinja

param(
  [switch]$NoBuild = $false,
  [switch]$ForceNinja = $false
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location $repoRoot

function Ask-YesNo($message, $default=$true) {
  $suffix = if ($default) {"[Y/n]"} else {"[y/N]"}
  $ans = Read-Host "$message $suffix"
  if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
  return $ans.Trim().ToLower() -in @('y','yes')
}

function Ensure-ExecPolicy {
  try { $cur = Get-ExecutionPolicy -Scope CurrentUser } catch { $cur = $null }
  if ($cur -ne 'RemoteSigned') {
    if (Ask-YesNo "Set-ExecutionPolicy RemoteSigned (CurrentUser) にしますか？") {
      Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
      Write-Host "ExecutionPolicy: RemoteSigned (CurrentUser)"
    } else {
      Write-Host "ExecutionPolicy 変更をスキップ。"
    }
  } else {
    Write-Host "ExecutionPolicy は既に RemoteSigned（CurrentUser）。"
  }
}

function Require-Tool($name, [scriptblock]$installer) {
  if (Get-Command $name -ErrorAction SilentlyContinue) {
    Write-Host "${name}: OK"
    return $true
  }
  Write-Host "${name}: NOT FOUND"
  if ($installer -and (Ask-YesNo "Install ${name} now?")) {
    & $installer
    if (Get-Command $name -ErrorAction SilentlyContinue) {
      Write-Host "${name}: installed"
      return $true
    } else {
      Write-Host "${name}: install failed"
      return $false
    }
  }
  return $false
}

function Install-Winget($id, $manualUrl) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install -e --id $id --accept-package-agreements --accept-source-agreements
  } else {
    Write-Host "winget がありません。手動インストール: $manualUrl" -ForegroundColor Yellow
  }
}

function Install-Python { Install-Winget "Python.Python.3.12" "https://www.python.org/downloads/windows/" }
function Install-gh     { Install-Winget "GitHub.cli"         "https://cli.github.com/" }
function Install-CMake  { Install-Winget "Kitware.CMake"      "https://cmake.org/download/" }
function Install-Ninja  { Install-Winget "Ninja-build.Ninja"  "https://github.com/ninja-build/ninja/releases" }

function Ensure-PythonAndPip {
  $okPy = Require-Tool "python" ${function:Install-Python}
  if (-not $okPy) { return $false }
  try { python -m pip --version | Out-Null; return $true } catch { return $false }
}
function Ensure-PreCommit {
  if (Get-Command pre-commit -ErrorAction SilentlyContinue) { return $true }
  if (Ensure-PythonAndPip) {
    Write-Host "pip で pre-commit を導入..."
    python -m pip install --upgrade pip pre-commit
    return [bool](Get-Command pre-commit -ErrorAction SilentlyContinue)
  }
  return $false
}

function Write-File($path, $content, $encoding='UTF8') {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Set-Content -Path $path -Value $content -Encoding $encoding
  Write-Host "Wrote: $path"
}

function Create-Shortcut($lnkPath, $target, $arguments, $workdir, $icon=$null) {
  $wsh = New-Object -ComObject WScript.Shell
  $s = $wsh.CreateShortcut($lnkPath)
  $s.TargetPath = $target
  $s.Arguments  = [string]$arguments
  $s.WorkingDirectory = $workdir
  if ($icon) { $s.IconLocation = $icon }
  $s.Save()
  Write-Host "Shortcut: $lnkPath"
}

# --- 0) Git repo check ---
& git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "ここは Git リポジトリではありません。'git init' 後に実行。" -ForegroundColor Yellow; exit 1 }

# --- 1) ExecPolicy ---
Ensure-ExecPolicy

# --- 2) 基本設定ファイル ---
$clangFormat = @"
BasedOnStyle: LLVM
IndentWidth: 4
TabWidth: 4
UseTab: Never
ColumnLimit: 120
BreakBeforeBraces: Allman
NamespaceIndentation: All
AccessModifierOffset: -4
AllowShortFunctionsOnASingleLine: Empty
SortIncludes: true
IncludeBlocks: Regroup
PointerAlignment: Left
SpaceBeforeParens: ControlStatements
FixNamespaceComments: true
"@
Write-File (Join-Path $repoRoot ".clang-format") $clangFormat

$gitattributes = @"
* text=auto eol=lf

*.bat text eol=crlf
*.cmd text eol=crlf
*.ps1 text eol=crlf

*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.exe binary
*.dll binary
"@
Write-File (Join-Path $repoRoot ".gitattributes") $gitattributes

# pre-commit: src/ & include/ のみ対象、vendor/build/out/.devtools を除外
$preCommit = @"
repos:
  - repo: https://github.com/pre-commit/mirrors-clang-format
    rev: v17.0.6
    hooks:
      - id: clang-format
        files: ^(src/|include/).*\.(c|cc|cpp|cxx|h|hpp)$
        exclude: ^(vendor/|build/|out/|\.devtools/)
        args: [--style=file]
"@
Write-File (Join-Path $repoRoot ".pre-commit-config.yaml") $preCommit

if (Ensure-PreCommit) {
  Write-Host "pre-commit install 実行..."
  & pre-commit install
  if ($LASTEXITCODE -ne 0) { Write-Host "pre-commit install に失敗（後で手動実行可）。" -ForegroundColor Yellow }
} else {
  Write-Host "pre-commit 未導入。python/pip 準備後に: python -m pip install pre-commit" -ForegroundColor Yellow
}

# --- 3) .devtools（隠し）と 2つの ps1 を配置 ---
$hiddenDir = Join-Path $repoRoot ".devtools"
if (-not (Test-Path $hiddenDir)) { New-Item -ItemType Directory -Path $hiddenDir | Out-Null }
attrib +h "$hiddenDir" 2>$null | Out-Null

# Start Work - Pull
$startWorkPath = Join-Path $hiddenDir "start-work-pull.ps1"
$startWork = @"
# start-work-pull.ps1
`$ErrorActionPreference = 'Stop'
Set-Location -Path `$PSScriptRoot
Set-Location ..  # repo root

function Fail(`$stage, `$msg) {
  Write-Host ''
  Write-Host "[ERROR] Stage: `$stage" -ForegroundColor Red
  if (`$msg) { Write-Host `$msg -ForegroundColor Red }
  Write-Host ''
  Read-Host 'Enter を押すと閉じます'
  exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git' 'Git が見つかりません。' }
& git rev-parse --is-inside-work-tree *> `$null
if (`$LASTEXITCODE -ne 0) { Fail 'repo' 'ここは Git リポジトリではありません。' }

`$curbr = (& git rev-parse --abbrev-ref HEAD).Trim()
if (-not `$curbr) { Fail 'branch' 'ブランチ名を取得できませんでした。' }

Write-Host 'Fetching...' -ForegroundColor Cyan
& git fetch origin | Out-Null

Write-Host "`n=== pull --rebase (autostash) ===" -ForegroundColor Cyan
& git pull --rebase --autostash origin `$curbr
if (`$LASTEXITCODE -ne 0) {
  Write-Host '[Warn] autostash なしで再試行'
  & git pull --rebase origin `$curbr
  if (`$LASTEXITCODE -ne 0) { Fail 'pull-rebase' 'リベースに失敗。競合を解消してください。' }
}

Write-Host "`n[OK] Up to date. これで作業を開始できます。" -ForegroundColor Green
Read-Host 'Enter を押すと閉じます'
exit 0
"@
Write-File $startWorkPath $startWork
attrib +h "$startWorkPath" 2>$null | Out-Null

# Quick Sync + PR（便利版：pre-commit 修正→自動再 add＆再チェック + settings.ini 同期）
$quickSyncPath = Join-Path $hiddenDir "quick-sync-pr.ps1"
$quickSync = @"
# quick-sync-pr.ps1 (auto re-add on pre-commit fixes + settings.ini sync)
`$ErrorActionPreference = 'Stop'
Set-Location -Path `$PSScriptRoot
Set-Location ..  # repo root

function Fail(`$stage, `$msg) {
  Write-Host ''
  Write-Host "[ERROR] Stage: `$stage" -ForegroundColor Red
  if (`$msg) { Write-Host `$msg -ForegroundColor Red }
  Write-Host ''
  Read-Host 'Enter を押すと閉じます'
  exit 1
}

# --- 基本チェック ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git' 'Git が見つかりません。' }
& git rev-parse --is-inside-work-tree *> `$null
if (`$LASTEXITCODE -ne 0) { Fail 'repo' 'ここは Git リポジトリではありません。' }

`$curbr = (& git rev-parse --abbrev-ref HEAD).Trim()
if (-not `$curbr) { Fail 'branch' 'ブランチ名を取得できませんでした。' }

`$origin = (& git remote get-url origin 2>`$null)
if (-not `$origin) { Fail 'remote' 'origin が設定されていません。' }

`$basebr = 'main'
& git show-ref --verify --quiet refs/remotes/origin/main
if (`$LASTEXITCODE -ne 0) {
  & git show-ref --verify --quiet refs/remotes/origin/master
  if (`$LASTEXITCODE -eq 0) { `$basebr = 'master' }
}

# --- 設定同期: build/**/settings.ini (最新) -> repo root settings.ini ---
function Sync-SettingsIni {
  `$buildRoot = Join-Path (Get-Location) "build"
  if (-not (Test-Path `$buildRoot)) {
    Write-Host "[settings.ini] build ディレクトリ無し。同期スキップ。" -ForegroundColor Yellow
    return
  }
  `$candidates = Get-ChildItem -Path `$buildRoot -Filter "settings.ini" -Recurse -File -ErrorAction SilentlyContinue
  if (-not `$candidates -or `$candidates.Count -eq 0) {
    Write-Host "[settings.ini] 見つからず。同期スキップ。" -ForegroundColor Yellow
    return
  }
  `$latest = `$candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  `$dst = Join-Path (Get-Location) "settings.ini"

  `$needCopy = `$true
  if (Test-Path `$dst) {
    try {
      `$srcHash = (Get-FileHash -Algorithm SHA256 -Path `$latest.FullName).Hash
      `$dstHash = (Get-FileHash -Algorithm SHA256 -Path `$dst).Hash
      `$needCopy = (`$srcHash -ne `$dstHash)
    } catch { `$needCopy = `$true }
  }

  if (`$needCopy) {
    Copy-Item -Path `$latest.FullName -Destination `$dst -Force
    Write-Host "[settings.ini] Synced: `$(`$latest.FullName) -> `$dst" -ForegroundColor Cyan
  } else {
    Write-Host "[settings.ini] 同一のため同期不要。" -ForegroundColor DarkGray
  }
}

# ここで同期（add の前）
Sync-SettingsIni

# --- メッセージ必須 ---
`$msg = Read-Host 'コミットメッセージ（必須）'
if ([string]::IsNullOrWhiteSpace(`$msg)) { Fail 'commit' 'コミットメッセージが空です。' }

Write-Host "`n=== add ==="
& git add -A; if (`$LASTEXITCODE -ne 0) { Fail 'add' 'git add に失敗' }

# --- pre-commit（自動再 add & 再チェック付き）---
if (Get-Command pre-commit -ErrorAction SilentlyContinue) {
  Write-Host "`n=== pre-commit (pass 1) ==="
  & pre-commit run --hook-stage commit -a
  `$first = `$LASTEXITCODE

  if (`$first -ne 0) {
    Write-Warning "pre-commit で修正あり or エラー。自動で再 add します。"
    & git add -A; if (`$LASTEXITCODE -ne 0) { Fail 'add' 'pre-commit 後の git add に失敗' }

    Write-Host "`n=== pre-commit (pass 2) ==="
    & pre-commit run --hook-stage commit -a
    `$second = `$LASTEXITCODE

    if (`$second -ne 0) {
      `$details = (& git status --porcelain) -join "`n"
      Fail 'pre-commit' "フック失敗（自動修正不可）。差分を直して再実行してください。`n`$details"
    }
  }
}

Write-Host "`n=== commit ==="
& git commit -m "`$msg"
if (`$LASTEXITCODE -ne 0) { Write-Host '[Info] 変更なし。commit はスキップして続行。' }

Write-Host "`n=== pull --rebase ==="
& git pull --rebase --autostash origin `$curbr
if (`$LASTEXITCODE -ne 0) {
  Write-Host '[Warn] autostash なしで再試行'
  & git pull --rebase origin `$curbr
  if (`$LASTEXITCODE -ne 0) { Fail 'pull-rebase' 'リベースに失敗。競合を解消してください。' }
}

Write-Host "`n=== push ==="
& git rev-parse --symbolic-full-name --abbrev-ref '@{u}' *> `$null
if (`$LASTEXITCODE -ne 0) {
  & git push -u origin `$curbr; if (`$LASTEXITCODE -ne 0) { Fail 'push' 'git push -u に失敗' }
} else {
  & git push; if (`$LASTEXITCODE -ne 0) { Fail 'push' 'git push に失敗' }
}

# --- PR ---
`$ownerRepo = `$null
if (`$origin -match 'github\.com[:/](?<own>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') { `$ownerRepo = "`$($Matches.own)/`$($Matches.repo)" }

if (Get-Command gh -ErrorAction SilentlyContinue) {
  & gh auth status *> `$null
  if (`$LASTEXITCODE -eq 0) {
    Write-Host "`n=== create PR via gh ==="
    & gh pr create --base `$basebr --head `$curbr --title "`$msg" --body "Auto PR by quick-sync-pr.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    if (`$LASTEXITCODE -eq 0) {
      & gh pr view --web
      exit 0
    }
  }
}

`$compareUrl = `$ownerRepo ? "https://github.com/`$ownerRepo/compare/`$basebr...`$curbr?expand=1" : "https://github.com"
Start-Process `$compareUrl
exit 0
"@
Write-File $quickSyncPath $quickSync
attrib +h "$quickSyncPath" 2>$null | Out-Null

# --- 4) gh の導入確認（任意） ---
$hasGh = Require-Tool "gh" ${function:Install-gh}
if ($hasGh) {
  Write-Host "gh 利用可。未ログインなら 'gh auth login' を一度実行。"
} else {
  Write-Host "gh 未導入。PR 自動作成は compare URL 自動オープンで代替されます。" -ForegroundColor Yellow
}

# --- 5) リポジトリ直下に 2つのショートカット作成（pwsh + NoProfile/NoLogo） ---
$pwsh   = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
$target = if ($pwsh) { $pwsh } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }

$lnk1 = Join-Path $repoRoot "Start Work - Pull.lnk"
$lnk2 = Join-Path $repoRoot "Quick Sync + PR.lnk"
$args1 = "-NoProfile -NoLogo -ExecutionPolicy Bypass -File `"$startWorkPath`""
$args2 = "-NoProfile -NoLogo -ExecutionPolicy Bypass -File `"$quickSyncPath`""

Create-Shortcut -lnkPath $lnk1 -target $target -arguments $args1 -workdir $repoRoot -icon "$target,0"
Create-Shortcut -lnkPath $lnk2 -target $target -arguments $args2 -workdir $repoRoot -icon "$target,0"

# 生成したスクリプトにブロック属性が付くことがあるため解除
Get-ChildItem ".devtools\*.ps1" | Unblock-File -ErrorAction SilentlyContinue

# --- 6) vendor 取得（任意） ---
if (Test-Path ".\scripts\get_imgui.ps1") {
  Write-Host "== Fetching vendor (imgui) =="
  try { powershell -ExecutionPolicy Bypass -File .\scripts\get_imgui.ps1 } catch { Write-Host "imgui fetch failed (ignored)" -ForegroundColor Yellow }
}

# --- 7) CMakePresets.json を用意（未存在なら生成） ---
$presetsPath = Join-Path $repoRoot "CMakePresets.json"
if (-not (Test-Path $presetsPath)) {
  $presets = @"
{
  "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 24 },
  "configurePresets": [
    {
      "name": "vs2022-x64",
      "displayName": "VS2022 x64",
      "generator": "Visual Studio 17 2022",
      "binaryDir": "${sourceDir}/build/vs2022-x64",
      "cacheVariables": { "CMAKE_POLICY_DEFAULT_CMP0141": "NEW" },
      "architecture": { "value": "x64", "strategy": "set" }
    },
    {
      "name": "ninja-msvc",
      "displayName": "Ninja (MSVC)",
      "generator": "Ninja Multi-Config",
      "binaryDir": "${sourceDir}/build/ninja",
      "cacheVariables": {
        "CMAKE_C_COMPILER": "cl",
        "CMAKE_CXX_COMPILER": "cl",
        "CMAKE_POLICY_DEFAULT_CMP0141": "NEW"
      }
    }
  ],
  "buildPresets": [
    { "name": "vs2022-Debug",   "configurePreset": "vs2022-x64", "configuration": "Debug"   },
    { "name": "vs2022-Release", "configurePreset": "vs2022-x64", "configuration": "Release" },
    { "name": "ninja-Debug",    "configurePreset": "ninja-msvc", "configuration": "Debug"   },
    { "name": "ninja-Release",  "configurePreset": "ninja-msvc", "configuration": "Release" }
  ]
}
"@
  Write-File $presetsPath $presets
}

# --- 8) CMake 構成＆ビルド（NoBuild でスキップ） ---
if (-not $NoBuild) {
  $haveCMake = Require-Tool "cmake" ${function:Install-CMake}
  if (-not $haveCMake) { Write-Host "cmake が必須です。中断。" -ForegroundColor Red; exit 1 }

  $haveVS = $false
  if (-not $ForceNinja) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
      $vs = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationVersion 2>$null
      if ($vs) { $haveVS = $true }
    }
  }

  if (-not $haveVS) {
    $haveNinja = Require-Tool "ninja" ${function:Install-Ninja}
    if (-not $haveNinja) { Write-Host "Ninja が必要ですが見つかりません。中断。" -ForegroundColor Red; exit 1 }
  }

  $cfgPreset = if ($haveVS -and -not $ForceNinja) { "vs2022-x64" } else { "ninja-msvc" }
  $release = Ask-YesNo "Build Release? (No=Debug)"
  $buildPreset = if ($cfgPreset -eq "vs2022-x64") {
    if ($release) { "vs2022-Release" } else { "vs2022-Debug" }
  } else {
    if ($release) { "ninja-Release" } else { "ninja-Debug" }
  }

  Write-Host "== CMake Configure ($cfgPreset) =="
  & cmake --preset $cfgPreset
  if ($LASTEXITCODE -ne 0) { Write-Host "CMake configure failed." -ForegroundColor Red; exit 1 }

  Write-Host "== CMake Build ($buildPreset) =="
  & cmake --build --preset $buildPreset --parallel
  if ($LASTEXITCODE -ne 0) { Write-Host "Build failed." -ForegroundColor Red; exit 1 }

  $out = switch ($buildPreset) {
    "vs2022-Release" { "build/vs2022-x64/Release" }
    "vs2022-Debug"   { "build/vs2022-x64/Debug"   }
    "ninja-Release"  { "build/ninja/Release"      }
    default          { "build/ninja/Debug"        }
  }
  Write-Host "`n[OK] Build finished. Artifacts: $out" -ForegroundColor Green
} else {
  Write-Host "[SKIP] Build skipped by -NoBuild"
}

Write-Host "`n[DONE] 初期設定＆ショートカット作成は完了。以後:"
Write-Host " - 作業前更新: 'Start Work - Pull.lnk'"
Write-Host " - 上げるとき: 'Quick Sync + PR.lnk'"
