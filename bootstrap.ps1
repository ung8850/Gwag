<<<<<<< HEAD
$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("bootstrap-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
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
    Log ("LogFile: {0}" -f $LogFile)
    Log ("WhoAmI: {0}" -f (whoami))

    $RepoBase = "https://raw.githubusercontent.com/ung8850/Gwag/main"
    $scriptName = "Sysprep-OneTime.ps1"
    $localPath  = Join-Path $WorkDir $scriptName

    Download ("{0}/{1}" -f $RepoBase, $scriptName) $localPath
    RunPs1 $localPath

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
=======
$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("bootstrap-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
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
    Log ("LogFile: {0}" -f $LogFile)
    Log ("WhoAmI: {0}" -f (whoami))

    $RepoBase = "https://raw.githubusercontent.com/ung8850/Gwag/main"
    $scriptName = "Sysprep-OneTime.ps1"
    $localPath  = Join-Path $WorkDir $scriptName

    Download ("{0}/{1}" -f $RepoBase, $scriptName) $localPath
    RunPs1 $localPath

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
>>>>>>> 0476f89ff03fb7c5ed34a8197b1b7aa95cafb895
