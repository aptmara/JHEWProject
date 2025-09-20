# quick-sync-pr.ps1 (auto re-add on pre-commit fixes)
$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot
Set-Location ..  # repo root

function Fail($stage, $msg) {
  Write-Host ''
  Write-Host "[ERROR] Stage: $stage" -ForegroundColor Red
  if ($msg) { Write-Host $msg -ForegroundColor Red }
  Write-Host ''
  Read-Host 'Enter を押すと閉じます'
  exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git' 'Git が見つかりません。' }
& git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Fail 'repo' 'ここは Git リポジトリではありません。' }

$curbr = (& git rev-parse --abbrev-ref HEAD).Trim()
if (-not $curbr) { Fail 'branch' 'ブランチ名を取得できませんでした。' }

$origin = (& git remote get-url origin 2>$null)
if (-not $origin) { Fail 'remote' 'origin が設定されていません。' }

$basebr = 'main'
& git show-ref --verify --quiet refs/remotes/origin/main
if ($LASTEXITCODE -ne 0) {
  & git show-ref --verify --quiet refs/remotes/origin/master
  if ($LASTEXITCODE -eq 0) { $basebr = 'master' }
}

$msg = Read-Host 'コミットメッセージ（必須）'
if ([string]::IsNullOrWhiteSpace($msg)) { Fail 'commit' 'コミットメッセージが空です。' }

Write-Host "
=== add ==="
& git add -A; if ($LASTEXITCODE -ne 0) { Fail 'add' 'git add に失敗' }

if (Get-Command pre-commit -ErrorAction SilentlyContinue) {
  Write-Host "
=== pre-commit (pass 1) ==="
  & pre-commit run --hook-stage commit -a
  $first = $LASTEXITCODE

  if ($first -ne 0) {
    Write-Warning 'pre-commit で修正あり or エラー。自動で再 add します。'
    & git add -A; if ($LASTEXITCODE -ne 0) { Fail 'add' 'pre-commit 後の git add に失敗' }

    Write-Host "
=== pre-commit (pass 2) ==="
    & pre-commit run --hook-stage commit -a
    $second = $LASTEXITCODE
    if ($second -ne 0) {
      $details = (& git status --porcelain) -join "
"
      Fail 'pre-commit' "フック失敗（自動修正不可）。差分を直して再実行してください。
$details"
    }
  }
}

Write-Host "
=== commit ==="
& git commit -m "$msg"
if ($LASTEXITCODE -ne 0) { Write-Host '[Info] 変更なし。commit はスキップして続行。' }

Write-Host "
=== pull --rebase ==="
& git pull --rebase --autostash origin $curbr
if ($LASTEXITCODE -ne 0) {
  Write-Host '[Warn] autostash なしで再試行'
  & git pull --rebase origin $curbr
  if ($LASTEXITCODE -ne 0) { Fail 'pull-rebase' 'リベースに失敗。競合を解消してください。' }
}

Write-Host "
=== push ==="
& git rev-parse --symbolic-full-name --abbrev-ref '@{u}' *> $null
if ($LASTEXITCODE -ne 0) {
  & git push -u origin $curbr; if ($LASTEXITCODE -ne 0) { Fail 'push' 'git push -u に失敗' }
} else {
  & git push; if ($LASTEXITCODE -ne 0) { Fail 'push' 'git push に失敗' }
}

$ownerRepo = $null
if ($origin -match 'github\.com[:/](?<own>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') { $ownerRepo = "$(.own)/$(.repo)" }

if (Get-Command gh -ErrorAction SilentlyContinue) {
  & gh auth status *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "
=== create PR via gh ==="
    & gh pr create --base $basebr --head $curbr --title "$msg" --body "Auto PR by quick-sync-pr.ps1 on 2025-09-21 00:10:54"
    if ($LASTEXITCODE -eq 0) {
      & gh pr view --web
      exit 0
    }
  }
}

$compareUrl = $ownerRepo ? "https://github.com/$ownerRepo/compare/$basebr...$curbr?expand=1" : "https://github.com"
Start-Process $compareUrl
exit 0
