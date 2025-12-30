# =========================
# Sysprep-OneTime.ps1
# - VM 프로비저닝 시 1회 실행: Scheduled Task 생성(AtLogOn, SYSTEM, Highest)
# - 사용자 로그온 시(=Task 실행): SystemAssigned MI(IMDS)로 자기 자신 VM에 태그 PATCH
# - 1회 실행 후 Task 자기 삭제(OneTime)
# =========================

param(
    [switch]$TagOnly
)

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

$LogFile = Join-Path $LogDir ("sysprep-onetime-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))
Start-Transcript -Path $LogFile -Append | Out-Null

function Log([string]$msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
}

function Remove-ScheduledTaskIfExists {
    param([Parameter(Mandatory)][string]$TaskName)

    try {
        $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($null -ne $t) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Log ("[TASK] Deleted existing task: {0}" -f $TaskName)
        } else {
            Log ("[TASK] No existing task (skip delete): {0}" -f $TaskName)
        }
    } catch {
        Log ("[TASK] Delete attempt ignored: {0}" -f $_.Exception.Message)
    }
}

function Get-ImdsToken {
    param([Parameter(Mandatory)][string]$Resource)

    $api = "2018-02-01"
    $uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=$api&resource=$([uri]::EscapeDataString($Resource))"
    $hdr = @{ Metadata = "true" }

    $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $hdr -TimeoutSec 30 -Proxy $null
    if (-not $resp.access_token) { throw "IMDS token not found (resource=$Resource)" }
    return $resp.access_token
}

function Get-ImdsComputeInfo {
    $uri = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
    $hdr = @{ Metadata = "true" }
    return Invoke-RestMethod -Method GET -Uri $uri -Headers $hdr -TimeoutSec 30 -Proxy $null
}

function Set-SelfVmTags {
    param([hashtable]$Tags)

    $c = Get-ImdsComputeInfo
    $vmId = "/subscriptions/$($c.subscriptionId)/resourceGroups/$($c.resourceGroupName)/providers/Microsoft.Compute/virtualMachines/$($c.name)"

    # ✅ FIX: PowerShell 문자열에서 "$vmId?api-version=..." 는 ? 때문에 파싱이 깨질 수 있음
    #        변수 경계를 ${}로 명확히 지정해서 안전하게 만듦
    $uri  = "https://management.azure.com${vmId}?api-version=2023-03-01"

    $token = Get-ImdsToken -Resource "https://management.azure.com/"
    $body  = @{ tags = $Tags } | ConvertTo-Json -Depth 10

    Log ("[TAG] Self VM : {0}" -f $vmId)
    Log ("[TAG] URI     : {0}" -f $uri)
    Log ("[TAG] Values  : {0}" -f (($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "))

    Invoke-RestMethod -Method PATCH -Uri $uri `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" -Body $body -TimeoutSec 60

    Log "[TAG] Patch success"
}

function Remove-ThisTask {
    param([string]$TaskName)

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Log ("[TASK] Deleted: {0}" -f $TaskName)
    } catch {
        Log ("[TASK] Delete failed (ignored): {0}" -f $_.Exception.Message)
    }
}

$taskName = "AVD-TagSelf-AtLogon-Once"

try {
    if ($TagOnly) {
        Log "=== TagOnly start ==="

        $tags = @{
            "Rebuild"            = "Yes"
            "RebuildDetectedKst" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }

        Set-SelfVmTags -Tags $tags
        Remove-ThisTask -TaskName $taskName

        Log "=== TagOnly success ==="
        exit 0
    }

    Log "=== Sysprep-OneTime (Create Scheduled Task) start ==="
    Log ("WorkDir: {0}" -f $WorkDir)
    Log ("Task  : {0}" -f $taskName)

    Remove-ScheduledTaskIfExists -TaskName $taskName

    $fixedScript = Join-Path $WorkDir "Sysprep-OneTime.ps1"

    # ---- FIX: self path resolve 안정화 ----
    # PS 5.1에서는 $PSCommandPath가 $MyInvocation.MyCommand.Path 보다 안정적
    $selfPath = $PSCommandPath
    if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Path }

    if ($selfPath -and (Test-Path $selfPath)) {
        if ($selfPath -ne $fixedScript) {
            Copy-Item -Path $selfPath -Destination $fixedScript -Force
            Log ("[FILE] Copied self script to fixed path: {0}" -f $fixedScript)
        } else {
            Log ("[FILE] Script already in fixed path: {0}" -f $fixedScript)
        }
    }
    else {
        # selfPath를 못 잡아도, 고정 경로 파일이 이미 있으면 그대로 진행
        Log ("[FILE] Self path not resolvable. Will use fixed script if exists: {0}" -f $fixedScript)
        if (-not (Test-Path $fixedScript)) {
            throw "Cannot resolve self script path AND fixed script not found: $fixedScript"
        }
    }
    # ---- FIX END ----

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args  = "-NoProfile -ExecutionPolicy Bypass -File `"$fixedScript`" -TagOnly"

    Log ("[TASK] PS  : {0}" -f $psExe)
    Log ("[TASK] Arg : {0}" -f $args)

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $args
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    Log ("Scheduled Task created successfully: {0}" -f $taskName)
    Log "=== Sysprep-OneTime (Create Scheduled Task) success ==="

    exit 0
}
catch {
    Log "!!! Sysprep-OneTime FAILED !!!"
    Log $_.Exception.Message
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
