[CmdletBinding()]
param (
    [string]$RemoteIP = "type remote device IP here",
    [string]$LocalIP = "type local device IP here",
    [string]$Username = "type username here",
    [string]$Password = "type password here",
    [int]$RebootConfirmTimeoutSec = 60,
    [int]$PingIntervalSec = 1
)

$LogDir = Join-Path $PSScriptRoot "logs"
$LogFile = Join-Path $LogDir "reboot_log.txt"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Output $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage -ErrorAction SilentlyContinue
}

$AskPassPath = Join-Path $LogDir "askpass.bat"
$StdoutPath  = Join-Path $LogDir "ssh_stdout.txt"
$StderrPath  = Join-Path $LogDir "ssh_stderr.txt"
$StdinPath   = Join-Path $LogDir "ssh_stdin.txt"

$env:SIKLU_SSH_PASS      = $Password
$env:SSH_ASKPASS         = $AskPassPath
$env:SSH_ASKPASS_REQUIRE = "force"
$env:DISPLAY             = "dummydisplay:0"

function Invoke-NativeSSHReboot {
    param([string]$IPAddress)

    if (Test-Path $StdoutPath) { Remove-Item -Force $StdoutPath }
    if (Test-Path $StderrPath) { Remove-Item -Force $StderrPath }

    $AskPassContent = '@powershell -NoProfile -ExecutionPolicy Bypass -Command "[Console]::Out.Write([System.Environment]::GetEnvironmentVariable(''SIKLU_SSH_PASS''))"'
    $AskPassContent | Out-File -FilePath $AskPassPath -Encoding ascii -Force

    "reboot system" | Out-File -FilePath $StdinPath -Encoding ascii -Force

    $ArgList = @(
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=NUL",
        "-l", $Username,
        $IPAddress
    )

    Write-Log "Sending reboot command to $IPAddress."

    $StartInfo = @{
        FilePath               = "ssh.exe"
        ArgumentList           = $ArgList
        NoNewWindow            = $true
        RedirectStandardInput  = $StdinPath
        RedirectStandardOutput = $StdoutPath
        RedirectStandardError  = $StderrPath
        PassThru               = $true
    }

    try {
        $Process = Start-Process @StartInfo

        $Process | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

        if (-not $Process.HasExited) {
            Write-Log "SSH session to $IPAddress dropped (device rebooting)."
            $Process | Stop-Process -Force
        }

        $StdoutContent = if (Test-Path $StdoutPath) { Get-Content -Raw $StdoutPath } else { "" }
        if ($StdoutContent.Trim()) { Write-Log "STDOUT: $($StdoutContent.Trim())" }

        Write-Log "Reboot command sent to $IPAddress."
        return $true
    }
    catch {
        Write-Log "ERROR running ssh on ${IPAddress}."
        return $false
    }
}

function Wait-ForDeviceOffline {
    param([string]$IPAddress)

    Write-Log "Waiting for $IPAddress to go offline."

    $Deadline = (Get-Date).AddSeconds($RebootConfirmTimeoutSec)

    while ((Get-Date) -lt $Deadline) {
        $IsUp = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $IsUp) {
            Write-Log "CONFIRMED: $IPAddress is offline - reboot successful."
            return $true
        }
        Write-Log "  $IPAddress still responding to ping - waiting ${PingIntervalSec}s."
        Start-Sleep -Seconds $PingIntervalSec
    }

    Write-Log "WARNING: $IPAddress is still reachable after ${RebootConfirmTimeoutSec}s. Reboot failed!"
    return $false
}

try {
    Write-Log "--- Rebooting remote device at $RemoteIP ---"
    $RemoteSuccess = Invoke-NativeSSHReboot -IPAddress $RemoteIP

    if ($RemoteSuccess) {
        Wait-ForDeviceOffline -IPAddress $RemoteIP
    }

    Write-Log "--- Rebooting local device at $LocalIP ---"
    $LocalSuccess = Invoke-NativeSSHReboot -IPAddress $LocalIP

    if ($LocalSuccess) {
        Wait-ForDeviceOffline -IPAddress $LocalIP
    }
}
finally {
    $env:SIKLU_SSH_PASS = ""
    if (Test-Path $AskPassPath) { Remove-Item -Force $AskPassPath | Out-Null }
    if (Test-Path $StdoutPath)  { Remove-Item -Force $StdoutPath  | Out-Null }
    if (Test-Path $StderrPath)  { Remove-Item -Force $StderrPath  | Out-Null }
    if (Test-Path $StdinPath)   { Remove-Item -Force $StdinPath   | Out-Null }
}

Write-Log "END"