# Sysprep-OneTime.ps1
# - VM 프로비저닝 시 1회 실행: Scheduled Task 생성(AtLogOn, SYSTEM, Highest)
# - 사용자 로그온 시(=Task 실행): SystemAssigned MI(IMDS)로 자기 자신 VM에 태그 PATCH
# - 1회 실행 후 Task 자기 삭제(OneTime)

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\AVD"
$WorkDir = Join-Path $BaseDir "Bootstrap"
$LogDir  = Join-Path $WorkDir "Logs"
$LogFile = Join-Path $LogDir ("sysprep-onetime-{0}.log" -f (Get-Date).ToString("yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir  -Force | Out-Null

Start-Transcript -Path $LogFile -Append | Out-Null

function Log([string]$msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
}

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
        Stop-Transcript | Out-Null
        exit 0
    }

    Log "=== Sysprep-OneTime (Create Scheduled Task) start ==="
    Log ("WorkDir: {0}" -f $WorkDir)
    Log ("Task  : {0}" -f $taskName)

    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    $selfPath = $MyInvocation.MyCommand.Path
    if (-not (Test-Path $selfPath)) { throw "Cannot resolve self script path." }

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args  = "-NoProfile -ExecutionPolicy Bypass -File `"$selfPath`" -TagOnly"

    $action    = New-ScheduledTaskAction -Execute $psExe -Argument $args
    $trigger   = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null

    Log ("Scheduled Task created successfully: {0}" -f $taskName)
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
