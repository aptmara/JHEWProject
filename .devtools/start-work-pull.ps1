# start-work-pull.ps1
# 目的: 作業開始前に、現在ブランチを origin と同期（pull --rebase --autostash）
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot
Set-Location ..  # repo root

function Fail($stage, $msg) {
  Write-Host ""
  Write-Host "[ERROR] Stage: $stage" -ForegroundColor Red
  if ($msg) { Write-Host $msg -ForegroundColor Red }
  Write-Host ""
  Read-Host "Enter を押すと閉じます"
  exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git" "Git が見つかりません。" }
& git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Fail "repo" "ここは Git リポジトリではありません。" }

$curbr = (& git rev-parse --abbrev-ref HEAD).Trim()
if (-not $curbr) { Fail "branch" "ブランチ名を取得できませんでした。" }

# 変更がある場合でも安全に進める
Write-Host "Fetching..." -ForegroundColor Cyan
& git fetch origin | Out-Null

Write-Host "
=== pull --rebase (autostash) ===" -ForegroundColor Cyan
& git pull --rebase --autostash origin $curbr
if ($LASTEXITCODE -ne 0) {
  Write-Host "[Warn] autostash なしで再試行"
  & git pull --rebase origin $curbr
  if ($LASTEXITCODE -ne 0) { Fail "pull-rebase" "リベースに失敗。競合を解消してください。" }
}

Write-Host "
[OK] Up to date. これで作業を開始できます。" -ForegroundColor Green
Read-Host "Enter を押すと閉じます"
exit 0
