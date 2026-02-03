# 2025-12-31 v2 (Merged) - Bootstrap Script
# 목적:
#  - AVD Custom Script Extension(사용자 지정 URL)에서 이 Bootstrap.ps1만 실행하면,
#    (1) MDE 온보딩(로컬 패키지) 실행
#    (2) 최초 사용자 로그온 1회 태깅을 위한 스크립트(FirstLogon-Tag.ps1) 실행(= Scheduled Task 생성)
#  - MDE가 실패하더라도 태깅 스크립트는 "반드시" 실행합니다.
#  - 단, 최종 종료 코드는 MDE/태깅 결과에 따라 실패(Exit 1)로 반환할 수 있습니다.

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# [필수 설정] Azure Blob(HTTPS) 최종 다운로드 URL (파일 + SAS 포함)
#  - 운영 편의를 위해 "최종 URL 1개"만 입력합니다.
#  - 예) https://<storageaccount>.blob.core.windows.net/<container>/path/FirstLogon-Tag.ps1?<SAS>
# ---------------------------------------------------------------------
$TagScriptUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/FirstLogon-Tag.ps1?sp=r&st=2026-02-03T04:47:32Z&se=2026-12-31T13:02:32Z&spr=https&sv=2024-11-04&sr=b&sig=%2Bm1SIV9g0u%2FQFWGnjRJyXno2KVv4fCuK6yTATBj0lh4%3D"


# ---------------------------------------------------------------------
# 작업 디렉터리/로그
# ---------------------------------------------------------------------
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

    # TLS 보강(환경에 따라 필요)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 180
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
# (1) MDE 온보딩 - 업로드된 Run-MDE-VDI-Local (1).ps1 내용을 "그대로" 통합
#     - 기존 스크립트는 exit로 종료하므로, 여기서는 함수로 감싸고 결과 코드를 return 합니다.
# ---------------------------------------------------------------------
function Invoke-MDE-VDI-Local {
    $ErrorActionPreference = "Stop"

    # 1) Onboard-NonPersistentMachine.ps1(VDI 스크립트) 실제 위치
    $LocalVdiPs1 = "C:\ProgramData\MDE\Onboard-NonPersistentMachine.ps1"
    # 2) WindowsDefenderATPOnboardingScript.cmd 가 들어있는 폴더(온보딩 패키지 폴더)
    $LocalPkgDir = "C:\ProgramData\MDE"

    function Write-Log([string]$msg) {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$ts] $msg"
    }

    try {
        Write-Log "Wrapper start"
        Write-Log "LocalVdiPs1 = $LocalVdiPs1"
        Write-Log "LocalPkgDir = $LocalPkgDir"

        # ---- 파일/폴더 존재 확인 ----
        if (-not (Test-Path $LocalVdiPs1 -PathType Leaf)) {
            Write-Log "ERROR: VDI PS1 not found: $LocalVdiPs1"
            return 21
        }

        if (-not (Test-Path $LocalPkgDir -PathType Container)) {
            Write-Log "ERROR: Package directory not found: $LocalPkgDir"
            return 22
        }

        $cmd1 = Join-Path $LocalPkgDir "WindowsDefenderATPOnboardingScript.cmd"
        $cmd2 = Join-Path $LocalPkgDir "DeviceComplianceOnboardingScript.cmd"

        if (-not (Test-Path $cmd1 -PathType Leaf) -and -not (Test-Path $cmd2 -PathType Leaf)) {
            Write-Log "ERROR: No onboarding CMD found in $LocalPkgDir"
            Write-Log "Expected: WindowsDefenderATPOnboardingScript.cmd or DeviceComplianceOnboardingScript.cmd"
            return 23
        }

        # ---- 실제 실행  ----
        Write-Log "Executing pre-staged VDI script..."
        $args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $LocalVdiPs1,
            "-onboardingPackageLocation", $LocalPkgDir
        )

        $p = Start-Process -FilePath "powershell.exe" -ArgumentList $args -Wait -PassThru
        Write-Log "Inner script exit code: $($p.ExitCode)"

        if ($p.ExitCode -ne 0) {
            Write-Log "ERROR: Inner script failed with exit code: $($p.ExitCode)"
            return $p.ExitCode
        }

        Write-Log "Wrapper success"
        return 0
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

    # -------------------------
    # STEP 1) MDE 온보딩 실행
    #  - 실패해도 다음 단계(태그 스크립트 실행)는 반드시 수행
    # -------------------------
    $mdeExit = 0
    try {
        Log "=== MDE onboarding start ==="
        $mdeExit = Invoke-MDE-VDI-Local
        Log ("MDE onboarding exit code: {0}" -f $mdeExit)
    } catch {
        $mdeExit = 99
        Log ("MDE onboarding exception (continue): {0}" -f $_.Exception.Message)
    }

	# -------------------------
	# STEP 2) 태그 스크립트(= Scheduled Task 생성) 실행
	#  - Blob 최종 URL에서 내려받아 임시 경로에서 실행
	# -------------------------
	Log "=== FirstLogon-Tag script (Create Task) start ==="

	$tempName = "FirstLogon-Tag-{0}.ps1" -f (Get-Date).ToString("yyyyMMdd-HHmmss")
	$tempPath = Join-Path $TmpDir $tempName

	Download $TagScriptUrl $tempPath

	$tagExit = RunPs1 $tempPath
	Log ("Tag script exit code: {0}" -f $tagExit)

	Cleanup-TempFile $tempPath


    # tmp 폴더 정리(기존 그대로)
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

    # -------------------------
    # 종료 정책
    #  - Tag 스크립트 실패: 즉시 실패(Exit 1)  (태그 작업 생성 자체가 핵심이므로)
    #  - Tag 성공 + MDE 실패: 태그 Task는 만들어졌지만 프로비저닝은 실패 처리(Exit 1)
    #  - 둘 다 성공: Exit 0
    # -------------------------
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
