[CmdletBinding()]
param(
  [ValidateSet("help", "install", "restore", "start", "stop", "restart", "status", "logs", "follow", "tail", "cleanup", "post-update")]
  [string]$Action = "status",

  [string]$TaskName = "OpenClaw Gateway",

  [int]$GatewayPort = 18789,

  [int]$Limit = 200
)

$ErrorActionPreference = "Stop"

function Write-Info {
  param([string]$Message)
  Write-Host "[openclaw-gateway] $Message"
}

function Get-GatewayDir {
  return Join-Path $env:USERPROFILE ".openclaw"
}

function Get-GatewayCmd {
  return Join-Path (Get-GatewayDir) "gateway.cmd"
}

function Get-HiddenLauncherPath {
  return Join-Path (Get-GatewayDir) "start-gateway-hidden.vbs"
}

function Assert-OpenClawCommand {
  if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    throw "Cannot find 'openclaw' in PATH. Open a new PowerShell or check the OpenClaw install."
  }
}

function Assert-GatewayCmd {
  $cmdPath = Get-GatewayCmd
  if (-not (Test-Path -LiteralPath $cmdPath)) {
    throw "Cannot find $cmdPath. Run 'openclaw gateway install' first, then run this script again."
  }
}

function Assert-GatewayTask {
  param([string]$Name)
  if (-not (Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue)) {
    throw "Cannot find scheduled task '$Name'. Run 'openclaw gateway install' first, then run this script again."
  }
}

function Get-GatewayStatusJson {
  Assert-OpenClawCommand
  $raw = & openclaw gateway status --json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "openclaw gateway status --json failed with exit code $LASTEXITCODE."
  }

  $text = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
  $text = $text -replace "`e\[[0-9;?]*[ -/]*[@-~]", ""
  $start = $text.IndexOf("{")
  $end = $text.LastIndexOf("}")

  if ($start -lt 0 -or $end -lt $start) {
    $sample = if ($text.Trim().Length -gt 0) { $text.Trim() } else { "<empty output>" }
    throw "Could not find JSON in 'openclaw gateway status --json' output. Output was: $sample"
  }

  $json = $text.Substring($start, $end - $start + 1)
  return ($json | ConvertFrom-Json)
}

function Write-HiddenLauncher {
  $vbsPath = Get-HiddenLauncherPath
  $content = @'
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
cmd = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "gateway.cmd")
shell.Run """" & cmd & """", 0, True
'@
  Set-Content -LiteralPath $vbsPath -Value $content -Encoding ASCII
  return $vbsPath
}

function Install-HiddenGatewayTaskAction {
  Assert-OpenClawCommand
  Assert-GatewayCmd
  Assert-GatewayTask -Name $TaskName

  $vbsPath = Write-HiddenLauncher
  $wscriptPath = Join-Path $env:WINDIR "System32\wscript.exe"
  $taskAction = New-ScheduledTaskAction -Execute $wscriptPath -Argument "`"$vbsPath`""

  try {
    Set-ScheduledTask -TaskName $TaskName -Action $taskAction | Out-Null
  } catch {
    throw "Could not update scheduled task '$TaskName'. Run this command from an Administrator terminal if Windows returns Access denied. Original error: $($_.Exception.Message)"
  }

  Write-Info "Updated scheduled task '$TaskName' to launch hidden via wscript.exe."
  Write-Info "Hidden launcher: $vbsPath"
  Write-Info "Gateway command remains: $(Get-GatewayCmd)"
}

function Restore-GatewayTaskAction {
  Assert-GatewayCmd
  Assert-GatewayTask -Name $TaskName

  $taskAction = New-ScheduledTaskAction -Execute (Get-GatewayCmd)
  Set-ScheduledTask -TaskName $TaskName -Action $taskAction | Out-Null

  Write-Info "Restored scheduled task '$TaskName' to launch gateway.cmd directly."
}

function Show-GatewayStatus {
  $status = Get-GatewayStatusJson

  Write-Host ""
  Write-Host "Service runtime : $($status.service.runtime.status)"
  Write-Host "Task state      : $($status.service.runtime.state)"
  Write-Host "Probe URL       : $($status.gateway.probeUrl)"
  Write-Host "Log file        : $($status.logFile)"
  Write-Host ""

  if ($status.port.listeners -and $status.port.listeners.Count -gt 0) {
    Write-Host "Listener process:"
    $status.port.listeners | Select-Object pid, address, command, commandLine | Format-Table -AutoSize
  } else {
    Write-Host "Listener process: none found"
  }
}

function Start-Gateway {
  Assert-OpenClawCommand
  & openclaw gateway start
}

function Stop-Gateway {
  Assert-OpenClawCommand
  & openclaw gateway stop
}

function Restart-Gateway {
  Stop-Gateway
  Start-Sleep -Seconds 2
  Start-Gateway
}

function Test-GatewayListening {
  $listeners = @(Get-NetTCPConnection -LocalPort $GatewayPort -State Listen -ErrorAction SilentlyContinue)
  return $listeners.Count -gt 0
}

function Wait-GatewayListening {
  param([int]$TimeoutSeconds = 20)

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-GatewayListening) {
      return $true
    }
    Start-Sleep -Seconds 1
  }

  return $false
}

function Ensure-GatewayRunning {
  if (Test-GatewayListening) {
    Write-Info "Gateway is already listening on port $GatewayPort."
    return
  }

  Write-Info "Gateway is not listening on port $GatewayPort; starting it now."
  Start-Gateway

  if (Wait-GatewayListening -TimeoutSeconds 20) {
    Write-Info "Gateway is now listening on port $GatewayPort."
  } else {
    Write-Info "Gateway did not start listening on port $GatewayPort within 20 seconds. Check logs with .\openclaw-gateway logs."
  }
}

function Get-CimProcessById {
  param([int]$ProcessId)
  return Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
}

function Get-GatewayRelatedProcessIds {
  $ids = New-Object "System.Collections.Generic.HashSet[int]"

  $listeners = Get-NetTCPConnection -LocalPort $GatewayPort -State Listen -ErrorAction SilentlyContinue
  foreach ($listener in $listeners) {
    [void]$ids.Add([int]$listener.OwningProcess)

    $process = Get-CimProcessById -ProcessId ([int]$listener.OwningProcess)
    for ($i = 0; $i -lt 3 -and $process -and $process.ParentProcessId; $i++) {
      [void]$ids.Add([int]$process.ParentProcessId)
      $process = Get-CimProcessById -ProcessId ([int]$process.ParentProcessId)
    }
  }

  return ,$ids
}

function Hide-ProcessWindow {
  param([int]$ProcessId)

  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $process -or $process.MainWindowHandle -eq 0) {
    return $false
  }

  if (-not ("OpenClawWindowUtil" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class OpenClawWindowUtil {
  [DllImport("user32.dll")]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@
  }

  return [OpenClawWindowUtil]::ShowWindowAsync($process.MainWindowHandle, 0)
}

function Stop-ProcessIdAndVerify {
  param([int]$ProcessId)

  $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
  if (-not $process) {
    return $true
  }

  try {
    Stop-Process -Id $ProcessId -Force -ErrorAction Stop
  } catch {
    $cimProcess = Get-CimProcessById -ProcessId $ProcessId
    if ($cimProcess) {
      try {
        Invoke-CimMethod -InputObject $cimProcess -MethodName Terminate | Out-Null
      } catch {
        return $false
      }
    } else {
      return $true
    }
  }

  Start-Sleep -Milliseconds 300
  return -not [bool](Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Stop-ProcessTreeIfSafe {
  param(
    [Parameter(Mandatory = $true)]
    [System.Diagnostics.Process]$FindstrProcess,

    [Parameter(Mandatory = $true)]
    [object]$FindstrCim,

    [Parameter(Mandatory = $true)]
    [object]$ParentCim,

    [System.Collections.Generic.HashSet[int]]$GatewayRelatedProcessIds
  )

  if ($null -eq $GatewayRelatedProcessIds) {
    $GatewayRelatedProcessIds = New-Object "System.Collections.Generic.HashSet[int]"
  }

  if ($ParentCim.Name -ine "cmd.exe") {
    Write-Info "Skipped PID $($FindstrProcess.Id): parent is $($ParentCim.Name), not cmd.exe."
    return $false
  }

  if ($GatewayRelatedProcessIds.Contains([int]$ParentCim.ProcessId)) {
    Write-Info "Skipped PID $($FindstrProcess.Id): parent cmd.exe is part of the running gateway process tree."
    return $false
  }

  $createdAt = [datetime]$FindstrCim.CreationDate
  $ageSeconds = ((Get-Date) - $createdAt).TotalSeconds
  if ($ageSeconds -lt 30) {
    Write-Info "Skipped PID $($FindstrProcess.Id): matching window is only $([int]$ageSeconds)s old; run cleanup again if it stays visible."
    return $false
  }

  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($ParentCim.ProcessId)" -ErrorAction SilentlyContinue)
  $otherChildren = @($children | Where-Object { [int]$_.ProcessId -ne [int]$FindstrProcess.Id })
  if ($otherChildren.Count -gt 0) {
    Write-Info "Skipped parent cmd.exe PID $($ParentCim.ProcessId): it has other child processes."
    return $false
  }

  Write-Info "Stopping stale OpenClaw update port-check window: findstr.exe PID $($FindstrProcess.Id), parent cmd.exe PID $($ParentCim.ProcessId)."
  $parentStopped = Stop-ProcessIdAndVerify -ProcessId ([int]$ParentCim.ProcessId)
  $findstrStopped = Stop-ProcessIdAndVerify -ProcessId ([int]$FindstrProcess.Id)

  if ($parentStopped -and $findstrStopped) {
    return "stopped"
  }

  if (-not $findstrStopped -and (Hide-ProcessWindow -ProcessId ([int]$FindstrProcess.Id))) {
    Write-Info "Could not terminate the stale window without elevation, so it was hidden instead. Run this command as Administrator if you want to terminate it."
    return "hidden"
  }

  Write-Info "Could not stop or hide PID $($FindstrProcess.Id). Try running this command in an Administrator terminal."
  return "skipped"
}

function Cleanup-OpenClawUpdateWindows {
  $titlePattern = "findstr.*:$GatewayPort .*LISTENING"
  $gatewayRelatedProcessIds = Get-GatewayRelatedProcessIds
  $matches = @(Get-Process -Name findstr -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match $titlePattern })

  if ($matches.Count -eq 0) {
    Write-Info "No stale OpenClaw update port-check window found for port $GatewayPort."
    return
  }

  $stopped = 0
  $hidden = 0
  foreach ($process in $matches) {
    $cim = Get-CimProcessById -ProcessId ([int]$process.Id)
    if (-not $cim) {
      continue
    }

    $parent = Get-CimProcessById -ProcessId ([int]$cim.ParentProcessId)
    if (-not $parent) {
      Write-Info "Skipped PID $($process.Id): parent process $($cim.ParentProcessId) no longer exists."
      continue
    }

    $result = Stop-ProcessTreeIfSafe -FindstrProcess $process -FindstrCim $cim -ParentCim $parent -GatewayRelatedProcessIds $gatewayRelatedProcessIds
    if ($result -eq "stopped") {
      $stopped++
    } elseif ($result -eq "hidden") {
      $hidden++
    }
  }

  if ($stopped -eq 0 -and $hidden -eq 0) {
    Write-Info "No matching window was stopped. The process did not meet the safety checks."
  } else {
    Write-Info "Stopped $stopped and hidden $hidden stale OpenClaw update window(s)."
  }
}

function Repair-AfterUpdate {
  try {
    Install-HiddenGatewayTaskAction
  } catch {
    Write-Info $_.Exception.Message
  }
  Cleanup-OpenClawUpdateWindows
  Ensure-GatewayRunning
  Show-GatewayStatus
}

function Show-Logs {
  Assert-OpenClawCommand
  & openclaw logs --plain --local-time --limit $Limit
}

function Follow-Logs {
  Assert-OpenClawCommand
  & openclaw logs --follow --plain --local-time --limit $Limit
}

function Tail-LogFile {
  $status = Get-GatewayStatusJson
  $logFile = [string]$status.logFile
  if (-not $logFile -or -not (Test-Path -LiteralPath $logFile)) {
    throw "Cannot find gateway log file from status output: $logFile"
  }
  Get-Content -LiteralPath $logFile -Tail $Limit -Wait
}

function Show-HelpText {
  Write-Host @"
OpenClaw Gateway hidden launcher helper

Usage:
  .\openclaw-gateway status
  .\openclaw-gateway install
  .\openclaw-gateway restart
  .\openclaw-gateway follow
  .\openclaw-gateway cleanup
  .\openclaw-gateway post-update

Actions:
  install   Create ~/.openclaw/start-gateway-hidden.vbs and update the '$TaskName' task to use wscript.exe.
  restore   Restore the '$TaskName' task to run ~/.openclaw/gateway.cmd directly.
  start     Start the OpenClaw Gateway service.
  stop      Stop the OpenClaw Gateway service.
  restart   Stop then start the OpenClaw Gateway service.
  status    Show runtime status, log file path, and listener PID.
  logs      Print recent gateway logs through 'openclaw logs'.
  follow    Follow gateway logs through 'openclaw logs --follow'.
  tail      Tail the physical log file reported by 'openclaw gateway status --json'.
  cleanup   Stop a stale OpenClaw update port-check window stuck on findstr for port $GatewayPort.
  post-update
            Re-apply hidden Gateway task, clean stale update windows, start Gateway if needed, then show status.

Notes:
  - This script does not edit ~/.openclaw/gateway.cmd.
  - Do not paste the full gateway.cmd contents into chats; it may contain local secrets.
  - Review logs before sharing them; third-party channel errors may include local tokens or app secrets.
  - If OpenClaw rewrites the scheduled task later, run .\openclaw-gateway post-update.
"@
}

switch ($Action) {
  "help" { Show-HelpText }
  "install" { Install-HiddenGatewayTaskAction }
  "restore" { Restore-GatewayTaskAction }
  "start" { Start-Gateway }
  "stop" { Stop-Gateway }
  "restart" { Restart-Gateway }
  "status" { Show-GatewayStatus }
  "logs" { Show-Logs }
  "follow" { Follow-Logs }
  "tail" { Tail-LogFile }
  "cleanup" { Cleanup-OpenClawUpdateWindows }
  "post-update" { Repair-AfterUpdate }
}
