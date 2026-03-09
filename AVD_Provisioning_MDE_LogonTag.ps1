# 2026-03-04 v2 (Merged) - Script
# 목적:
#  - AVD Custom Script Extension에서 이 Bootstrap.ps1만 실행하면,
#    (1) MDE 온보딩(Streamlined ZIP 패키지 다운로드→압축해제→VDI PS1 실행→CMD 자동 실행)
#    (2) 최초 사용자 로그온 1회 태깅 스크립트(FirstLogon-Tag.ps1) 실행(= Scheduled Task 생성)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# [필수 설정] Blob URL (SAS 포함)
# ---------------------------------------------------------------------

# 1) FirstLogon-Tag.ps1 다운로드 URL
$TagScriptUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/FirstLogon-Tag.ps1?sp=r&st=2026-03-04T06:11:19Z&se=2027-01-01T14:26:19Z&spr=https&sv=2024-11-04&sr=b&sig=eb71hp0ASJOQihiA8CQatcxQVIFwnMlOCjKPa14Z%2Fog%3D"

# 2) MDE Streamlined 패키지 ZIP 다운로드 URL (SAS 포함)
$MdeZipUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/GatewayWindowsDefenderATPOnboardingPackage.zip?sp=r&st=2026-03-04T06:10:56Z&se=2027-01-01T14:25:56Z&spr=https&sv=2024-11-04&sr=b&sig=m3O3Za%2BbC0r9PxAbevExRc1VZk1mQvtcX6dL%2BzTbvRw%3D"

# ---------------------------------------------------------------------
# 작업 디렉터리/로그
# ---------------------------------------------------------------------
$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$TmpDir  = Join-Path $WorkDir "_tmp"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("provisioning-mde-logontag-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $TmpDir  -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

Start-Transcript -Path $LogFile -Append | Out-Null

function Log($msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
}

function Download($uri, $out) {
    Log ("Download: {0}" -f $uri)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 300
    if (-not (Test-Path $out)) {
        throw ("Download failed (file not found): {0}" -f $out)
    }
}

function RunPs1($path, [string]$extraArgs = "") {
    if (-not (Test-Path $path)) {
        throw ("Script not found: {0}" -f $path)
    }

    Log ("Run: {0} {1}" -f $path, $extraArgs)

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$path`""
    if ($extraArgs) { $arg = "$arg $extraArgs" }

    $p = Start-Process $psExe -ArgumentList $arg -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

function Cleanup-TempFile($tempPath) {
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
}

# ---------------------------------------------------------------------
# (1) MDE 온보딩(Streamlined ZIP) 실행
#   - ZIP 안에는 반드시 아래 2개가 "같은 폴더"에 있어야 함
#     - Onboard-NonPersistentMachine.ps1
#     - WindowsDefenderATPOnboardingScript.cmd
#   - PS1 실행 시 onboardingPackageLocation을 그 폴더로 전달하면
#     PS1이 CMD를 자동 실행한다.
# ---------------------------------------------------------------------
function Invoke-MDE-VDI-FromZip {
    $ErrorActionPreference = "Stop"

    $MdeRoot = "C:\ProgramData\MDE"
    $MdePkgDir = Join-Path $MdeRoot "Streamlined" 

    function Write-Log([string]$msg) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$ts] $msg"
    }

    try {
        Write-Log "=== MDE(Streamlined ZIP) prepare ==="
        Write-Log "MdeZipUrl = $MdeZipUrl"
        Write-Log "MdePkgDir = $MdePkgDir"

        if ([string]::IsNullOrWhiteSpace($MdeZipUrl) -or $MdeZipUrl -like "https://<storageaccount>*") {
            Write-Log "ERROR: MdeZipUrl is not set"
            return 41
        }

        # 1) ZIP 다운로드
        $zipPath = Join-Path $TmpDir ("mde-streamlined-{0}.zip" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
        Write-Log "Downloading MDE zip to: $zipPath"
        Download $MdeZipUrl $zipPath

        # 2) 대상 폴더 준비
        New-Item -ItemType Directory -Path $MdePkgDir -Force | Out-Null
        try {
            Remove-Item -Path (Join-Path $MdePkgDir "*") -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}

        Write-Log "Expanding zip to: $MdePkgDir"
        Expand-Archive -Path $zipPath -DestinationPath $MdePkgDir -Force

        # ZIP 정리
        Cleanup-TempFile $zipPath

        # 3) ZIP 구조가 루트/하위폴더 PS1 위치 탐색
        $ps1Item = Get-ChildItem -Path $MdePkgDir -Recurse -File -Filter "Onboard-NonPersistentMachine.ps1" | Select-Object -First 1
        if (-not $ps1Item) {
            Write-Log "ERROR: Onboard-NonPersistentMachine.ps1 not found after unzip"
            return 42
        }

        $pkgDir = $ps1Item.Directory.FullName
        $cmdPath = Join-Path $pkgDir "WindowsDefenderATPOnboardingScript.cmd"

        Write-Log "Detected PS1  : $($ps1Item.FullName)"
        Write-Log "Detected PkgDir: $pkgDir"
        Write-Log "Expected CMD  : $cmdPath"

        if (-not (Test-Path $cmdPath -PathType Leaf)) {
            Write-Log "ERROR: WindowsDefenderATPOnboardingScript.cmd not found next to PS1"
            return 43
        }

        # 4) PS1 실행
        Write-Log "Executing VDI onboarding PS1 (it will call CMD automatically)..."
        $args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $ps1Item.FullName,
            "-onboardingPackageLocation", $pkgDir
        )

        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -Wait -PassThru
        Write-Log "MDE VDI PS1 exit code: $($p.ExitCode)"
        return $p.ExitCode
    }
    catch {
        Write-Log "FATAL: $($_.Exception.Message)"
        return 99
    }
}

try {
    Log "=== Bootstrap start ==="
    Log ("WorkDir: {0}" -f $WorkDir)
    Log ("TmpDir : {0}" -f $TmpDir)
    Log ("LogFile: {0}" -f $LogFile)
    Log ("WhoAmI : {0}" -f (whoami))
    Log ("TagScriptUrl: {0}" -f $TagScriptUrl)
    Log ("MdeZipUrl    : {0}" -f $MdeZipUrl)

    # -------------------------
    # STEP 1) MDE 온보딩 실행
    # -------------------------
    $mdeExit = 0
    try {
        Log "=== MDE onboarding start (Streamlined ZIP) ==="
        $mdeExit = Invoke-MDE-VDI-FromZip
        Log ("MDE onboarding exit code: {0}" -f $mdeExit)
    } catch {
        $mdeExit = 99
        Log ("MDE onboarding exception (continue): {0}" -f $_.Exception.Message)
    }

    # -------------------------
    # STEP 2) 태그 스크립트(= Scheduled Task 생성) 실행
    # -------------------------
    Log "=== FirstLogon-Tag script (Create Task) start ==="

    $tempName = "FirstLogon-Tag-{0}.ps1" -f (Get-Date).ToString("yyyyMMdd-HHmmss")
    $tempPath = Join-Path $TmpDir $tempName

    Download $TagScriptUrl $tempPath

    $tagExit = RunPs1 $tempPath
    Log ("Tag script exit code: {0}" -f $tagExit)

    Cleanup-TempFile $tempPath

    # tmp 폴더 정리
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

    # 종료 정책
    if ($tagExit -ne 0) {
        throw ("FirstLogon-Tag script failed (ExitCode={0})" -f $tagExit)
    }

    if ($mdeExit -ne 0) {
        throw ("MDE onboarding failed (ExitCode={0})" -f $mdeExit)
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
