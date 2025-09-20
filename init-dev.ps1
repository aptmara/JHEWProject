# init-dev.ps1
# 目的:
# - 作業前 Pull（rebase, autostash）をワンクリック起動：Start Work - Pull.lnk
# - 追加→整形(pre-commit)→commit→pull(rebase)→push→PR（gh/compare）をワンクリック起動：Quick Sync + PR.lnk
# - いずれも .ps1 本体は .devtools/ 配下に隠す
# 実行:
#   PowerShell をリポジトリ直下で開き:
#   powershell -ExecutionPolicy Bypass -File .\init-dev.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location $repoRoot

function Ask-YesNo($message, $default=$true) {
  $suffix = $default ? "[Y/n]" : "[y/N]"
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
    } else { Write-Host "ExecutionPolicy 変更をスキップしました。" }
  } else { Write-Host "ExecutionPolicy は既に RemoteSigned（CurrentUser）。" }
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

function Install-Python-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
  } else { Write-Host "winget なし: Python は手動導入 https://www.python.org/downloads/windows/" }
}
function Install-gh-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install -e --id GitHub.cli --accept-package-agreements --accept-source-agreements
  } else { Write-Host "winget なし: gh は https://cli.github.com/ から手動導入" }
}

function Ensure-PythonAndPip {
  $okPy = Require-Tool "python" ${function:Install-Python-Winget}
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

# --- 1) Execution policy ---
Ensure-ExecPolicy

# --- 2) 基本設定ファイル（整形/改行/commit時整形） ---
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

$preCommit = @"
repos:
  - repo: https://github.com/pre-commit/mirrors-clang-format
    rev: v17.0.6
    hooks:
      - id: clang-format
        files: \.(c|cc|cpp|cxx|h|hpp)$
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

# --- 3) .devtools（隠し）と 2つの .ps1 を配置 ---
$hiddenDir = Join-Path $repoRoot ".devtools"
if (-not (Test-Path $hiddenDir)) { New-Item -ItemType Directory -Path $hiddenDir | Out-Null }
attrib +h "$hiddenDir" 2>$null | Out-Null

# 3-1) 作業前 Pull 専用
$startWorkPath = Join-Path $hiddenDir "start-work-pull.ps1"
$startWork = @"
# start-work-pull.ps1
# 目的: 作業開始前に、現在ブランチを origin と同期（pull --rebase --autostash）
`$ErrorActionPreference = 'Stop'
Set-Location -Path `$PSScriptRoot
Set-Location ..  # repo root

function Fail(`$stage, `$msg) {
  Write-Host ""
  Write-Host "[ERROR] Stage: `$stage" -ForegroundColor Red
  if (`$msg) { Write-Host `$msg -ForegroundColor Red }
  Write-Host ""
  Read-Host "Enter を押すと閉じます"
  exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git" "Git が見つかりません。" }
& git rev-parse --is-inside-work-tree *> `$null
if (`$LASTEXITCODE -ne 0) { Fail "repo" "ここは Git リポジトリではありません。" }

`$curbr = (& git rev-parse --abbrev-ref HEAD).Trim()
if (-not `$curbr) { Fail "branch" "ブランチ名を取得できませんでした。" }

# 変更がある場合でも安全に進める
Write-Host "Fetching..." -ForegroundColor Cyan
& git fetch origin | Out-Null

Write-Host "`n=== pull --rebase (autostash) ===" -ForegroundColor Cyan
& git pull --rebase --autostash origin `$curbr
if (`$LASTEXITCODE -ne 0) {
  Write-Host "[Warn] autostash なしで再試行"
  & git pull --rebase origin `$curbr
  if (`$LASTEXITCODE -ne 0) { Fail "pull-rebase" "リベースに失敗。競合を解消してください。" }
}

Write-Host "`n[OK] Up to date. これで作業を開始できます。" -ForegroundColor Green
Read-Host "Enter を押すと閉じます"
exit 0
"@
Write-File $startWorkPath $startWork
attrib +h "$startWorkPath" 2>$null | Out-Null

# 3-2) Push + PR（既存の quick-sync を再掲）
$quickSyncPath = Join-Path $hiddenDir "quick-sync-pr.ps1"
$quickSync = @"
# quick-sync-pr.ps1
# 目的: add -> pre-commit -> commit -> pull --rebase -> push -> PR（gh or compare）
`$ErrorActionPreference = 'Stop'
Set-Location -Path `$PSScriptRoot
Set-Location ..  # repo root

function Fail(`$stage, `$msg) {
  Write-Host ""
  Write-Host "[ERROR] Stage: `$stage" -ForegroundColor Red
  if (`$msg) { Write-Host `$msg -ForegroundColor Red }
  Write-Host ""
  Read-Host "Enter を押すと閉じます"
  exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git" "Git が見つかりません。" }
& git rev-parse --is-inside-work-tree *> `$null
if (`$LASTEXITCODE -ne 0) { Fail "repo" "ここは Git リポジトリではありません。" }

`$curbr = (& git rev-parse --abbrev-ref HEAD).Trim()
if (-not `$curbr) { Fail "branch" "ブランチ名を取得できませんでした。" }

`$origin = (& git remote get-url origin 2>`$null)
if (-not `$origin) { Fail "remote" "origin が設定されていません。" }

`$basebr = "main"
& git show-ref --verify --quiet refs/remotes/origin/main
if (`$LASTEXITCODE -ne 0) {
  & git show-ref --verify --quiet refs/remotes/origin/master
  if (`$LASTEXITCODE -eq 0) { `$basebr = "master" }
}

`$msg = Read-Host "コミットメッセージ（必須）"
if ([string]::IsNullOrWhiteSpace(`$msg)) { Fail "commit" "コミットメッセージが空です。" }

Write-Host "`n=== add ==="
& git add -A; if (`$LASTEXITCODE -ne 0) { Fail "add" "git add に失敗" }

if (Get-Command pre-commit -ErrorAction SilentlyContinue) {
  Write-Host "`n=== pre-commit ==="
  & pre-commit run --hook-stage commit -a
  if (`$LASTEXITCODE -ne 0) { Fail "pre-commit" "pre-commit フックで失敗（整形/検査エラー）" }
  & git add -A; if (`$LASTEXITCODE -ne 0) { Fail "add" "pre-commit 後の git add に失敗" }
}

Write-Host "`n=== commit ==="
& git commit -m "`$msg"
if (`$LASTEXITCODE -ne 0) { Write-Host "[Info] 変更なし。commit はスキップして続行。" }

Write-Host "`n=== pull --rebase ==="
& git pull --rebase --autostash origin `$curbr
if (`$LASTEXITCODE -ne 0) {
  Write-Host "[Warn] autostash なしで再試行"
  & git pull --rebase origin `$curbr
  if (`$LASTEXITCODE -ne 0) { Fail "pull-rebase" "リベースに失敗。競合を解消してください。" }
}

Write-Host "`n=== push ==="
& git rev-parse --symbolic-full-name --abbrev-ref '@{u}' *> `$null
if (`$LASTEXITCODE -ne 0) {
  & git push -u origin `$curbr; if (`$LASTEXITCODE -ne 0) { Fail "push" "git push -u に失敗" }
} else {
  & git push; if (`$LASTEXITCODE -ne 0) { Fail "push" "git push に失敗" }
}

`$ownerRepo = `$null
if (`$origin -match 'github\.com[:/](?<own>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') { `$ownerRepo = "`$($Matches.own)/`$($Matches.repo)" }

if (Get-Command gh -ErrorAction SilentlyContinue) {
  & gh auth status *> `$null
  if (`$LASTEXITCODE -eq 0) {
    Write-Host "`n=== create PR via gh ==="
    & gh pr create --base `$basebr --head `$curbr` --title "`$msg" --body "Auto PR by quick-sync-pr.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
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
$hasGh = Require-Tool "gh" ${function:Install-gh-Winget}
if ($hasGh) {
  Write-Host "gh 利用可。未ログインなら 'gh auth login' を一度実行。"
} else {
  Write-Host "gh 未導入。PR 自動作成は compare URL の自動オープンで代替されます。" -ForegroundColor Yellow
}


# --- 5) リポジトリ直下に 2つのショートカット作成 ---
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$lnk1 = Join-Path $repoRoot "Start Work - Pull.lnk"
$args1 = "-ExecutionPolicy Bypass -File `"$startWorkPath`""
Create-Shortcut -lnkPath $lnk1 -target $psExe -args $args1 -workdir $repoRoot -icon "$psExe,0"

$lnk2 = Join-Path $repoRoot "Quick Sync + PR.lnk"
$args2 = "-ExecutionPolicy Bypass -File `"$quickSyncPath`""
Create-Shortcut -lnkPath $lnk2 -target $psExe -args $args2 -workdir $repoRoot -icon "$psExe,0"

Write-Host "`n[OK] 初期設定完了。" -ForegroundColor Green
Write-Host "・作業開始前は:  'Start Work - Pull.lnk' をダブルクリック（pull --rebase --autostash）"
Write-Host "・作業を上げる時は: 'Quick Sync + PR.lnk' をダブルクリック（add→整形→commit→pull→push→PR）"
