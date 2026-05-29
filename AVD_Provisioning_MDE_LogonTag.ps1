# 2026-03-30 v8
# 목적:
#  - AVD 프로비저닝 단계에서 1회 실행되며, 최초 사용자 로그온 이후 필요한 후속 작업을 준비하기 위한 메인 스크립트입니다.
#  - 본 스크립트는 아래 작업을 수행합니다.
#    (1) MDE Streamlined 패키지 다운로드 및 VDI 온보딩 준비/실행
#    (2) 최초 로그온 시 VM 태그 반영을 위한 후속 작업 준비
#    (3) 최초 로그온 사용자의 계정 정보를 수집하기 위한 Capture 스크립트 준비
#    (4) 수집된 계정 정보를 기반으로 DBeaver 설정을 반영하기 위한 Apply 스크립트 준비
#
# 동작 개요:
#  - 본 스크립트는 프로비저닝 단계에서 1회 실행되며,
#    최초 사용자 로그온 이후 필요한 후속 작업을 준비하고 등록합니다.
#
#  - MDE 온보딩 작업:
#    MDE Streamlined 패키지(ZIP)를 다운로드 및 압축 해제한 후,
#    VDI 온보딩 스크립트를 실행하여 보안 에이전트 구성을 적용합니다.
#
#  - 태그 작업 준비:
#    FirstLogon-Tag.ps1를 다운로드 및 실행하여,
#    최초 사용자 로그온 시 VM 운영 태그를 기록하는 1회성 후속 작업을 준비합니다.
#
#  - 사용자 계정 수집 작업 준비:
#    Capture-DBeaverUpnUser.ps1를 다운로드하고,
#    사용자 로그온 시 화면 표시 없이 실행될 수 있도록 VBS 런처를 생성한 뒤,
#    최초 로그온 시 사용자 계정명을 수집하는 작업(Task)을 등록합니다.
#
#  - DBeaver 설정 반영 작업 준비:
#    Apply-DBeaverIni.ps1를 다운로드한 뒤,
#    최초 로그온 시 SYSTEM 권한으로 실행되어 수집된 사용자 계정 정보를
#    DBeaver 설정 파일(dbeaver.ini)에 반영하는 작업(Task)을 등록합니다.
#
#  - 최초 로그온 이후 처리:
#    최초 사용자 로그온 시 태그 작업, 사용자 계정 수집 작업, 설정 반영 작업이 각각 동작하며,
#    설정 반영이 완료되면 관련 임시 파일, 작업(Task), 스크립트 등 1회성 구성 요소가 자동으로 정리됩니다.
#
# 비고:
#  - DBeaver 관련 스크립트는 C:\ProgramData\AVD\Scripts 경로에 저장됩니다.
#  - 태그 작업과 DBeaver 후속 작업은 서로 다른 경로를 사용하여 상호 영향 없이 동작하도록 구성되어 있습니다.
#  - 사용자 계정 수집 및 설정 반영에 필요한 임시 데이터는 작업 완료 후 자동 정리됩니다.
#  - 본 구성은 최초 로그온 시 1회만 동작하도록 설계되어 있으며, 실행 후 시스템에 잔여 구성이 남지 않도록 정리됩니다.

# ---------------------------------------------------------------------
# [종료 코드 정의]
# ---------------------------------------------------------------------
#  0  : 성공
#
# 11  : 초기 작업 환경 준비 실패
#       (디렉터리 생성 또는 로그 시작 실패)
#
# 21  : 태그 작업 스크립트 다운로드 실패
# 22  : 사용자 계정 수집 스크립트 다운로드 실패
# 23  : DBeaver 설정 반영 스크립트 다운로드 실패
#
# 31  : MDE 패키지 URL 설정 오류
# 32  : MDE 패키지 다운로드 실패
# 33  : MDE 패키지 압축 해제 실패
# 34  : MDE 온보딩 PowerShell 스크립트 미존재
# 35  : MDE 온보딩 CMD 스크립트 미존재
# 36  : MDE VDI 온보딩 스크립트 실행 실패
# 39  : MDE 처리 중 예외 발생
#
# 41  : 태그 작업 준비 스크립트 실행 실패
#
# 51  : 사용자 계정 수집 작업(Task) 등록 실패
# 61  : DBeaver 설정 반영 작업(Task) 등록 실패
#
# 99  : 처리되지 않은 예외 발생
# ---------------------------------------------------------------------

$ErrorActionPreference = "Stop"
$FinalExitCode = 0

# ---------------------------------------------------------------------
# [필수 설정] Blob URL (SAS 포함)
# ---------------------------------------------------------------------

# 1) FirstLogon-Tag.ps1 다운로드 URL
$TagScriptUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/FirstLogon-Tag.ps1?sp=r&st=2026-03-04T06:11:19Z&se=2027-01-01T14:26:19Z&spr=https&sv=2024-11-04&sr=b&sig=eb71hp0ASJOQihiA8CQatcxQVIFwnMlOCjKPa14Z%2Fog%3D"

# 2) MDE Streamlined 패키지 ZIP 다운로드 URL
$MdeZipUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/GatewayWindowsDefenderATPOnboardingPackage.zip?sp=r&st=2026-03-04T06:10:56Z&se=2027-01-01T14:25:56Z&spr=https&sv=2024-11-04&sr=b&sig=m3O3Za%2BbC0r9PxAbevExRc1VZk1mQvtcX6dL%2BzTbvRw%3D"

# 3) Capture-DBeaverUpnUser.ps1 다운로드 URL
$CaptureUserScriptUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/Capture-DBeaverUpnUser.ps1?sp=r&st=2026-03-26T07:59:48Z&se=2029-12-31T16:14:48Z&spr=https&sv=2025-11-05&sr=b&sig=KjEcfcmqgItyld3mOVFPEEn%2Fv2DCuft7cCV1XXBtwwU%3D"

# 4) Apply-DBeaverIni.ps1 다운로드 URL
$ApplyIniScriptUrl = "https://hanmiavdstorage.blob.core.windows.net/hanmi-avd/AVD-Template/ProvisioningCustomURL/Apply-DBeaverIni.ps1?sp=r&st=2026-03-26T07:59:04Z&se=2028-12-31T16:14:04Z&spr=https&sv=2025-11-05&sr=b&sig=L1UKKU4anIaBElR%2FLdcN23z%2FKgvXKmM%2Bc8W%2F%2F8cM4ng%3D"

# ---------------------------------------------------------------------
# 작업 디렉터리/로그
# ---------------------------------------------------------------------
$BaseDir        = "C:\ProgramData\AVD"
$WorkDir        = Join-Path $BaseDir "Bootstrap"
$TmpDir         = Join-Path $WorkDir "_tmp"
$LogDir         = Join-Path $WorkDir "Logs"
$ScriptStoreDir = Join-Path $BaseDir "Scripts"

$LogFile = Join-Path $LogDir ("provisioning-mde-logontag-dbeaver-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

$CaptureUserScriptPath = Join-Path $ScriptStoreDir "Capture-DBeaverUpnUser.ps1"
$ApplyIniScriptPath    = Join-Path $ScriptStoreDir "Apply-DBeaverIni.ps1"

$CaptureUserTaskName   = "Capture-DBeaver-UPN-User-On-First-Logon"
$ApplyIniTaskName      = "Apply-DBeaver-Ini-On-First-Logon"
$CaptureUserVbsPath = Join-Path $ScriptStoreDir "Run-Capture-DBeaverUpnUser.vbs"

try {
    New-Item -ItemType Directory -Path $WorkDir        -Force | Out-Null
    New-Item -ItemType Directory -Path $TmpDir         -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir         -Force | Out-Null
    New-Item -ItemType Directory -Path $ScriptStoreDir -Force | Out-Null
    Start-Transcript -Path $LogFile -Append | Out-Null
}
catch {
    try { Write-Host "Bootstrap init failed: $($_.Exception.Message)" } catch {}
    exit 11
}

function Log($msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
}

function Download($uri, $out) {
    Log ("Download: {0}" -f $uri)
    Log ("OutFile  : {0}" -f $out)

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -TimeoutSec 300

    if (-not (Test-Path $out -PathType Leaf)) {
        throw ("Download failed (file not found): {0}" -f $out)
    }

    $size = (Get-Item $out).Length
    Log ("Download success. Size={0} bytes" -f $size)
}

function RunPs1 {
    param(
        [string]$Path,
        [string]$ExtraArgs = ""
    )

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw ("Script not found: {0}" -f $Path)
    }

    Log ("Run: {0} {1}" -f $Path, $ExtraArgs)

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$Path`""
    if (-not [string]::IsNullOrWhiteSpace($ExtraArgs)) {
        $arg = "$arg $ExtraArgs"
    }

    $p = Start-Process -FilePath $psExe -ArgumentList $arg -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

function Cleanup-TempFile {
    param(
        [string]$TempPath
    )

    try {
        if (Test-Path $TempPath) {
            Remove-Item -Path $TempPath -Force -ErrorAction Stop
            Log ("[CLEAN] Deleted temp file: {0}" -f $TempPath)
        }
    }
    catch {
        Log ("[CLEAN] Temp delete failed, schedule delayed delete: {0}" -f $_.Exception.Message)
        try {
            $cmd = "ping 127.0.0.1 -n 6 > nul & del /f /q `"$TempPath`""
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -WindowStyle Hidden
            Log ("[CLEAN] Scheduled temp delete: {0}" -f $TempPath)
        }
        catch {
            Log ("[CLEAN] Schedule temp delete failed (ignored): {0}" -f $_.Exception.Message)
        }
    }
}

function Register-CaptureUserLogonTask {
    param(
        [string]$TaskName,
        [string]$VbsPath
    )

    Log ("Register USER logon task (ScheduledTasks): {0}" -f $TaskName)
    Log ("USER task VBS path: {0}" -f $VbsPath)

    if (-not (Test-Path $VbsPath -PathType Leaf)) {
    	throw ("VBS not found: {0}" -f $VbsPath)
	}

    try {
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Log ("Existing USER task found. Removing: {0}" -f $TaskName)
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        }

        $action = New-ScheduledTaskAction `
    		-Execute "$env:SystemRoot\System32\wscript.exe" `
    		-Argument "`"$VbsPath`""

        $trigger = New-ScheduledTaskTrigger -AtLogOn

        $principal = New-ScheduledTaskPrincipal `
            -GroupId "BUILTIN\Users" `
            -RunLevel Limited

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description "One-time capture of logged-on UPN user for DBeaver" `
            -Force `
            -ErrorAction Stop | Out-Null

        $checkTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $checkTask) {
            throw ("USER task verification failed: {0}" -f $TaskName)
        }

        Log ("USER logon task registered successfully: {0}" -f $TaskName)
    }
    catch {
        throw ("Register USER logon task failed: {0}" -f $_.Exception.Message)
    }
}

function Register-ApplyIniLogonTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )

    Log ("Register SYSTEM logon task: {0}" -f $TaskName)
    Log ("SYSTEM task script path: {0}" -f $ScriptPath)

    if (-not (Test-Path $ScriptPath -PathType Leaf)) {
        throw ("Apply ini script not found: {0}" -f $ScriptPath)
    }

    try {
        $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            Log ("Existing SYSTEM task found. Removing: {0}" -f $TaskName)
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        }

        $action = New-ScheduledTaskAction `
    		-Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    		-Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`" -TaskName `"$TaskName`""

        $trigger = New-ScheduledTaskTrigger -AtLogOn

        $principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description "One-time apply of DBeaver ini using captured logged-on username" `
            -Force `
            -ErrorAction Stop | Out-Null

        $checkTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $checkTask) {
            throw ("SYSTEM task verification failed: {0}" -f $TaskName)
        }

        Log ("SYSTEM logon task registered successfully: {0}" -f $TaskName)
    }
    catch {
        throw ("Register SYSTEM logon task failed: {0}" -f $_.Exception.Message)
    }
}

function Invoke-MDE-VDI-FromZip {
    $ErrorActionPreference = "Stop"

    $MdeRoot   = "C:\ProgramData\MDE"
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
            return 31
        }

        $zipPath = Join-Path $TmpDir ("mde-streamlined-{0}.zip" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
        Write-Log "Downloading MDE zip to: $zipPath"

        try {
            Download $MdeZipUrl $zipPath
        }
        catch {
            Write-Log "ERROR: MDE zip download failed: $($_.Exception.Message)"
            return 32
        }

        New-Item -ItemType Directory -Path $MdePkgDir -Force | Out-Null
        try {
            Remove-Item -Path (Join-Path $MdePkgDir "*") -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}

        Write-Log "Expanding zip to: $MdePkgDir"
        try {
            Expand-Archive -Path $zipPath -DestinationPath $MdePkgDir -Force
        }
        catch {
            Write-Log "ERROR: Expand-Archive failed: $($_.Exception.Message)"
            return 33
        }
        finally {
            Cleanup-TempFile $zipPath
        }

        $ps1Item = Get-ChildItem -Path $MdePkgDir -Recurse -File -Filter "Onboard-NonPersistentMachine.ps1" | Select-Object -First 1
        if (-not $ps1Item) {
            Write-Log "ERROR: Onboard-NonPersistentMachine.ps1 not found after unzip"
            return 34
        }

        $pkgDir  = $ps1Item.Directory.FullName
        $cmdPath = Join-Path $pkgDir "WindowsDefenderATPOnboardingScript.cmd"

        Write-Log "Detected PS1   : $($ps1Item.FullName)"
        Write-Log "Detected PkgDir: $pkgDir"
        Write-Log "Expected CMD   : $cmdPath"

        if (-not (Test-Path $cmdPath -PathType Leaf)) {
            Write-Log "ERROR: WindowsDefenderATPOnboardingScript.cmd not found next to PS1"
            return 35
        }

        Write-Log "Executing VDI onboarding PS1..."
        $args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $ps1Item.FullName,
            "-onboardingPackageLocation", $pkgDir
        )

        $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -Wait -PassThru
        Write-Log "MDE VDI PS1 exit code: $($p.ExitCode)"

        if ($p.ExitCode -ne 0) {
            return 36
        }

        return 0
    }
    catch {
        Write-Log "FATAL: $($_.Exception.Message)"
        return 39
    }
}

function New-HiddenLauncherVbs {
    param(
        [string]$VbsPath,
        [string]$PsScriptPath,
        [string]$Arguments = ""
    )

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $escapedPsExe        = $psExe.Replace('"', '""')
    $escapedPsScriptPath = $PsScriptPath.Replace('"', '""')
    $escapedArguments    = $Arguments.Replace('"', '""')

    $vbsContent = @"
Set shell = CreateObject("WScript.Shell")
cmd = """" & "$escapedPsExe" & """" & " -NoProfile -ExecutionPolicy Bypass -File " & """" & "$escapedPsScriptPath" & """" & " $escapedArguments"
shell.Run cmd, 0, False
"@

    Set-Content -Path $VbsPath -Value $vbsContent -Encoding Ascii -Force
    Log ("Hidden launcher VBS created: {0}" -f $VbsPath)
    Log ("Hidden launcher VBS content:`n{0}" -f $vbsContent)
}



try {
    Log "=== Bootstrap start ==="
    Log ("WorkDir               : {0}" -f $WorkDir)
    Log ("TmpDir                : {0}" -f $TmpDir)
    Log ("LogFile               : {0}" -f $LogFile)
    Log ("ScriptStoreDir        : {0}" -f $ScriptStoreDir)
    Log ("WhoAmI                : {0}" -f (whoami))
    Log ("CaptureUserTaskName   : {0}" -f $CaptureUserTaskName)
    Log ("ApplyIniTaskName      : {0}" -f $ApplyIniTaskName)

    # STEP 1) MDE 온보딩
    Log "=== STEP 1 : MDE onboarding start ==="
    $mdeExit = Invoke-MDE-VDI-FromZip
    Log ("MDE onboarding exit code: {0}" -f $mdeExit)

    if ($mdeExit -ne 0) {
        $FinalExitCode = $mdeExit
        throw ("MDE onboarding failed (ExitCode={0})" -f $mdeExit)
    }

    # STEP 2) FirstLogon-Tag 스크립트 다운로드/실행
    Log "=== STEP 2 : FirstLogon-Tag script start ==="

    $tempName = "FirstLogon-Tag-{0}.ps1" -f (Get-Date).ToString("yyyyMMdd-HHmmss")
    $tempPath = Join-Path $TmpDir $tempName

    try {
        Download $TagScriptUrl $tempPath
    }
    catch {
        $FinalExitCode = 21
        throw ("Tag script download failed: {0}" -f $_.Exception.Message)
    }

    try {
        $tagExit = RunPs1 -Path $tempPath
        Log ("Tag script exit code: {0}" -f $tagExit)

        if ($tagExit -ne 0) {
            $FinalExitCode = 41
            throw ("FirstLogon-Tag script failed (ExitCode={0})" -f $tagExit)
        }
    }
    finally {
        Cleanup-TempFile -TempPath $tempPath
    }

    # STEP 3) Capture 스크립트 다운로드
    Log "=== STEP 3 : Capture-DBeaverUpnUser.ps1 download start ==="
    try {
    Download $CaptureUserScriptUrl $CaptureUserScriptPath
    Log ("Capture user script downloaded: {0}" -f $CaptureUserScriptPath)

    New-HiddenLauncherVbs `
        -VbsPath $CaptureUserVbsPath `
        -PsScriptPath $CaptureUserScriptPath `
        -Arguments "-TaskName `"$CaptureUserTaskName`""

    Log ("Capture hidden launcher VBS created: {0}" -f $CaptureUserVbsPath)
	}
	catch {
    $FinalExitCode = 22
    throw ("Capture script/VBS prepare failed: {0}" -f $_.Exception.Message)
	}

    # STEP 4) ApplyIni 스크립트 다운로드
    Log "=== STEP 4 : Apply-DBeaverIni.ps1 download start ==="
    try {
        Download $ApplyIniScriptUrl $ApplyIniScriptPath
        Log ("Apply ini script downloaded: {0}" -f $ApplyIniScriptPath)
    }
    catch {
        $FinalExitCode = 23
        throw ("Apply ini script download failed: {0}" -f $_.Exception.Message)
    }

    # STEP 5) Capture 사용자 로그온 Task 등록
    Log "=== STEP 5 : Register capture user logon task start ==="
    try {
        Register-CaptureUserLogonTask -TaskName $CaptureUserTaskName -VbsPath $CaptureUserVbsPath
    }
    catch {
        $FinalExitCode = 51
        throw ("Register capture task failed: {0}" -f $_.Exception.Message)
    }

    # STEP 6) ApplyIni SYSTEM 로그온 Task 등록
    Log "=== STEP 6 : Register apply ini SYSTEM logon task start ==="
    try {
        Register-ApplyIniLogonTask -TaskName $ApplyIniTaskName -ScriptPath $ApplyIniScriptPath
    }
    catch {
        $FinalExitCode = 61
        throw ("Register apply ini task failed: {0}" -f $_.Exception.Message)
    }

    # tmp 정리
    try {
        if (Test-Path $TmpDir) {
            $left = Get-ChildItem -Path $TmpDir -Force -ErrorAction SilentlyContinue
            if (-not $left) {
                Remove-Item -Path $TmpDir -Force -ErrorAction Stop
                Log ("[CLEAN] Deleted tmp dir: {0}" -f $TmpDir)
            }
        }
    }
    catch {
        Log ("[CLEAN] Tmp dir delete failed (ignored): {0}" -f $_.Exception.Message)
    }

    Log "=== Bootstrap success ==="
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Log "!!! Bootstrap FAILED !!!"
    Log ("FinalExitCode: {0}" -f $FinalExitCode)
    Log $_.Exception.Message
    try { Stop-Transcript | Out-Null } catch {}

    if ($FinalExitCode -eq 0) {
        exit 99
    }
    else {
        exit $FinalExitCode
    }
}