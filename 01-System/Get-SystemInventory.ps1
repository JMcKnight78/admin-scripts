#Requires -Version 5.1
<#
.SYNOPSIS
    Returns read-only inventory for the local Windows computer.
.DESCRIPTION
    Uses CIM to collect operating system, manufacturer, model, processor,
    memory, domain/workgroup, and uptime as one structured PowerShell object.
    No administrator privileges are normally required for local queries.
.EXAMPLE
    .\Get-SystemInventory.ps1
.EXAMPLE
    .\Get-SystemInventory.ps1 | Format-List
.EXAMPLE
    .\Get-SystemInventory.ps1 | Export-Csv .\inventory.csv -NoTypeInformation
.NOTES
    Intended for Windows PowerShell 5.1 and PowerShell 7 on Windows.
    Test in an authorized lab before workplace use.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $system = Get-CimInstance -ClassName Win32_ComputerSystem
    $processor = Get-CimInstance -ClassName Win32_Processor |
        Select-Object -First 1

    if ($null -eq $os -or $null -eq $system -or $null -eq $processor) {
        throw 'One or more required CIM queries returned no information.'
    }

    $lastBoot = [datetime]$os.LastBootUpTime
    $uptime = (Get-Date) - $lastBoot

    [pscustomobject]@{
        ComputerName = $system.Name
        OperatingSystem = $os.Caption
        OSVersion = $os.Version
        Manufacturer = $system.Manufacturer
        Model = $system.Model
        DomainOrWorkgroup = $system.Domain
        PartOfDomain = [bool]$system.PartOfDomain
        Processor = $processor.Name
        TotalMemoryGB = [math]::Round(
            [double]$system.TotalPhysicalMemory / 1GB, 2
        )
        LastBootTime = $lastBoot
        UptimeDays = [math]::Round($uptime.TotalDays, 2)
        CollectedAt = Get-Date
    }
}
catch {
    Write-Error -Message (
        'Unable to collect system inventory: {0}' -f $_.Exception.Message
    ) -ErrorAction Stop
}
