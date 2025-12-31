#2025-12-31수정

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$TmpDir  = Join-Path $WorkDir "_tmp"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("bootstrap-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $TmpDir  -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

Start-Transcript -Path $LogFile -Append | Out-Null

function Log($msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
}

function Download($uri, $out) {
    Log ("Download: {0}" -f $uri)
    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 120
    if (-not (Test-Path $out)) {
        throw ("Download failed (file not found): {0}" -f $out)
    }
}

function RunPs1($path) {
    if (-not (Test-Path $path)) {
        throw ("Script not found: {0}" -f $path)
    }

    Log ("Run: {0}" -f $path)

    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$path`""
    $p = Start-Process powershell -ArgumentList $arg -Wait -PassThru -NoNewWindow

    if ($p.ExitCode -ne 0) {
        throw ("Script failed: {0} (ExitCode={1})" -f $path, $p.ExitCode)
    }
}

try {
    Log "=== Bootstrap start ==="
    Log ("WorkDir: {0}" -f $WorkDir)
    Log ("TmpDir : {0}" -f $TmpDir)
    Log ("LogFile: {0}" -f $LogFile)
    Log ("WhoAmI : {0}" -f (whoami))


    $RepoBase   = "https://raw.githubusercontent.com/ung8850/Gwag/main"
    $scriptName = "Sysprep-OneTime.ps1"


    $tempName = "Sysprep-OneTime-{0}.ps1" -f (Get-Date).ToString("yyyyMMdd-HHmmss")
    $tempPath = Join-Path $TmpDir $tempName

    Download ("{0}/{1}" -f $RepoBase, $scriptName) $tempPath
    RunPs1 $tempPath

   
    try {
        Remove-Item -Path $tempPath -Force -ErrorAction Stop
        Log ("[CLEAN] Deleted temp script: {0}" -f $tempPath)
    } catch {
        Log ("[CLEAN] Temp delete failed, schedule delayed delete: {0}" -f $_.Exception.Message)
        try {
            $cmd = "ping 127.0.0.1 -n 6 > nul & del /f /q `"$tempPath`""
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -WindowStyle Hidden
            Log ("[CLEAN] Scheduled temp delete: {0}" -f $tempPath)
        } catch {
            Log ("[CLEAN] Schedule temp delete failed (ignored): {0}" -f $_.Exception.Message)
        }
    }

    try {
        if (Test-Path $TmpDir) {
            $left = Get-ChildItem -Path $TmpDir -Force -ErrorAction SilentlyContinue
            if (-not $left) {
                Remove-Item -Path $TmpDir -Force -ErrorAction Stop
                Log ("[CLEAN] Deleted tmp dir: {0}" -f $TmpDir)
            }
        }
    } catch {
        Log ("[CLEAN] Tmp dir delete failed (ignored): {0}" -f $_.Exception.Message)
    }

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
