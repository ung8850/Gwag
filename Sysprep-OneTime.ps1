<<<<<<< HEAD
# Sysprep-OneTime.ps1
# 목적:
#  - 사용자 로그온(AtLogOn) 시 1회 실행되는 Scheduled Task 생성
#  - Task는 SYSTEM으로 실행되며 VM의 SystemAssigned MI 토큰(IMDS)로 ARM PATCH 호출하여
#    "자기 자신 VM"에 태그를 찍는다.
#  - 실행 후 Task는 자기 자신을 삭제(OneTime)

$ErrorActionPreference = "Stop"

# ===================== Paths =====================
$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("sysprep-onetime-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

Start-Transcript -Path $LogFile -Append | Out-Null

function Log($msg) {
    Write-Host "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
}

# ===================== MODE: TagOnly =====================
# Scheduled Task에서 이 스크립트를 -TagOnly 로 다시 호출하도록 만들 예정
param(
    [switch]$TagOnly
)

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
    $uri  = "https://management.azure.com$vmId?api-version=2023-03-01"

    $token = Get-ImdsToken -Resource "https://management.azure.com/"
    $body  = @{ tags = $Tags } | ConvertTo-Json -Depth 10

    Log ("[TAG] Self VM : {0}" -f $vmId)
    Log ("[TAG] Values  : {0}" -f (($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "))

    Invoke-RestMethod -Method PATCH -Uri $uri `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" -Body $body -TimeoutSec 60

    Log "[TAG] Patch success"
}

function Remove-ThisTask {
    param([string]$TaskName)
    try {
        schtasks /Delete /TN $TaskName /F | Out-Null
        Log "[TASK] Deleted: $TaskName"
    } catch {
        Log "[TASK] Delete failed (ignored): $($_.Exception.Message)"
    }
}

# ===================== MAIN =====================
$taskName = "AVD-TagSelf-AtLogon-Once"

try {
    if ($TagOnly) {
        # ---------- This part runs at user logon (SYSTEM) ----------
        Log "=== TagOnly start ==="

        # 태그 키/값 (원하면 여기서 키를 바꿔도 됨)
        $tags = @{
            "Rebuild"            = "Yes"
            "RebuildDetectedKst" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
       
        }

        Set-SelfVmTags -Tags $tags

        # 1회 실행 후 작업 삭제
        Remove-ThisTask -TaskName $taskName

        Log "=== TagOnly success ==="
        Stop-Transcript | Out-Null
        exit 0
    }

    # ---------- This part runs once during provisioning ----------
    Log "=== Sysprep-OneTime (Create Scheduled Task) start ==="
    Log "WorkDir: $WorkDir"
    Log "Task  : $taskName"

    # 기존 작업 있으면 삭제
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    # 이 스크립트가 있는 절대 경로를 Task에 넣는다
    $selfPath = $MyInvocation.MyCommand.Path
    if (-not (Test-Path $selfPath)) { throw "Cannot resolve self script path." }

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args  = "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`" -TagOnly"

    # SYSTEM + Highest, AtLogOn 트리거
    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $args
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    Log "Scheduled Task created successfully: $taskName"
    Log "=== Sysprep-OneTime (Create Scheduled Task) success ==="

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Log "!!! Sysprep-OneTime FAILED !!!"
    Log $_.Exception.Message
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
=======
# Sysprep-OneTime.ps1
# 목적:
#  - 사용자 로그온(AtLogOn) 시 1회 실행되는 Scheduled Task 생성
#  - Task는 SYSTEM으로 실행되며 VM의 SystemAssigned MI 토큰(IMDS)로 ARM PATCH 호출하여
#    "자기 자신 VM"에 태그를 찍는다.
#  - 실행 후 Task는 자기 자신을 삭제(OneTime)

$ErrorActionPreference = "Stop"

# ===================== Paths =====================
$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("sysprep-onetime-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

Start-Transcript -Path $LogFile -Append | Out-Null

function Log($msg) {
    Write-Host "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
}

# ===================== MODE: TagOnly =====================
# Scheduled Task에서 이 스크립트를 -TagOnly 로 다시 호출하도록 만들 예정
param(
    [switch]$TagOnly
)

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
    $uri  = "https://management.azure.com$vmId?api-version=2023-03-01"

    $token = Get-ImdsToken -Resource "https://management.azure.com/"
    $body  = @{ tags = $Tags } | ConvertTo-Json -Depth 10

    Log ("[TAG] Self VM : {0}" -f $vmId)
    Log ("[TAG] Values  : {0}" -f (($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "))

    Invoke-RestMethod -Method PATCH -Uri $uri `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" -Body $body -TimeoutSec 60

    Log "[TAG] Patch success"
}

function Remove-ThisTask {
    param([string]$TaskName)
    try {
        schtasks /Delete /TN $TaskName /F | Out-Null
        Log "[TASK] Deleted: $TaskName"
    } catch {
        Log "[TASK] Delete failed (ignored): $($_.Exception.Message)"
    }
}

# ===================== MAIN =====================
$taskName = "AVD-TagSelf-AtLogon-Once"

try {
    if ($TagOnly) {
        # ---------- This part runs at user logon (SYSTEM) ----------
        Log "=== TagOnly start ==="

        # 태그 키/값 (원하면 여기서 키를 바꿔도 됨)
        $tags = @{
            "Rebuild"            = "Yes"
            "RebuildDetectedKst" = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
       
        }

        Set-SelfVmTags -Tags $tags

        # 1회 실행 후 작업 삭제
        Remove-ThisTask -TaskName $taskName

        Log "=== TagOnly success ==="
        Stop-Transcript | Out-Null
        exit 0
    }

    # ---------- This part runs once during provisioning ----------
    Log "=== Sysprep-OneTime (Create Scheduled Task) start ==="
    Log "WorkDir: $WorkDir"
    Log "Task  : $taskName"

    # 기존 작업 있으면 삭제
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    # 이 스크립트가 있는 절대 경로를 Task에 넣는다
    $selfPath = $MyInvocation.MyCommand.Path
    if (-not (Test-Path $selfPath)) { throw "Cannot resolve self script path." }

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args  = "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`" -TagOnly"

    # SYSTEM + Highest, AtLogOn 트리거
    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $args
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    Log "Scheduled Task created successfully: $taskName"
    Log "=== Sysprep-OneTime (Create Scheduled Task) success ==="

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Log "!!! Sysprep-OneTime FAILED !!!"
    Log $_.Exception.Message
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
>>>>>>> ba1f7258751ec78acd0f0bc4421a2dfa77c00d3f
