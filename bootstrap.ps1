# bootstrap.ps1
# AVD Session Host 배포 시 CustomScriptExtension으로 1회 실행

$ErrorActionPreference = "Stop"

# ========= 기본 경로 =========
$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("bootstrap-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

# 작업 폴더/로그 폴더 보장
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

Start-Transcript -Path $LogFile -Append | Out-Null

function Log($msg) {
    Write-Host "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
}

function Download($uri, $out) {
    Log "Download: $uri"
    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 120

    if (-not (Test-Path $out)) {
        throw "Download failed (file not found): $out"
    }
}

function RunPs1($path, $args = "") {
    if (-not (Test-Path $path)) {
        throw "Script not found: $path"
    }

    Log "Run: $path $args"
    $p = Start-Process powershell `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$path`" $args" `
        -Wait -PassThru -NoNewWindow

    if ($p.ExitCode -ne 0) {
        throw "Script failed: $path (ExitCode=$($p.ExitCode))"
    }
}

try {
    Log "=== Bootstrap start ==="
    Log "WorkDir: $WorkDir"
    Log "LogFile: $LogFile"

    # ===== GitHub raw base =====
    $RepoBase = "https://raw.githubusercontent.com/ung8850/Gwag/main"

    # ===== 스크립트 다운로드 =====
    # ✅ 언어 관련 스크립트 제거
    $scripts = @(
        "TimezoneRedirection.ps1",
        "ConfigureSessionTimeoutsV2.ps1",
        "Sysprep-OneTime.ps1"
    )

    foreach ($s in $scripts) {
        Download "$RepoBase/$s" (Join-Path $WorkDir $s)
    }

    # ===== 실행 =====
    RunPs1 (Join-Path $WorkDir "TimezoneRedirection.ps1")
    RunPs1 (Join-Path $WorkDir "ConfigureSessionTimeoutsV2.ps1") `
        '-MaxDisconnectionTime "5" -RemoteAppLogoffTimeLimit "5" -MaxConnectionTime "5" -MaxIdleTime "5"'

    # ✅ 첫 로그인 시 Rebuild 태그 찍는 스케줄러/스크립트 설치
    RunPs1 (Join-Path $WorkDir "Sysprep-OneTime.ps1")

    Log "=== Bootstrap success ==="
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Log "!!! Bootstrap FAILED !!!"
    Log $_.Exception.Message
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
