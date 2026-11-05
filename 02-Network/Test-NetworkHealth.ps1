#Requires -Version 5.1
<#
.SYNOPSIS
    Performs read-only Windows network diagnostics.
.DESCRIPTION
    Reports active IP configuration and resolves a selected DNS name.
    Optionally tests a TCP connection to an explicitly supplied host and port.
    Produces objects suitable for filtering, CSV exports, and troubleshooting.
    The default DNS name is localhost: no public destination is contacted by default.
.PARAMETER DnsName
    DNS name to resolve. Defaults to localhost.
.PARAMETER TcpHost
    Hostname or IP address for an optional TCP connection test.
.PARAMETER TcpPort
    Port (1-65535) for the optional TCP test; requires TcpHost.
.PARAMETER TimeoutMilliseconds
    Maximum wait for the optional TCP test, 100-30000 milliseconds.
.EXAMPLE
    .\Test-NetworkHealth.ps1
.EXAMPLE
    .\Test-NetworkHealth.ps1 -DnsName example.com
.EXAMPLE
    .\Test-NetworkHealth.ps1 -DnsName example.com -TcpHost example.com -TcpPort 443
.NOTES
    Windows PowerShell 5.1 and PowerShell 7 on Windows.
    Does not change network settings. Use only approved endpoints.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DnsName = 'localhost',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TcpHost,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$TcpPort,

    [Parameter()]
    [ValidateRange(100, 30000)]
    [int]$TimeoutMilliseconds = 2000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSBoundParameters.ContainsKey('TcpHost') -ne $PSBoundParameters.ContainsKey('TcpPort')) {
    throw 'Specify both -TcpHost and -TcpPort to test TCP connectivity.'
}

function New-DiagnosticResult {
    param(
        [string]$Check,
        [string]$Target,
        [string]$Status,
        [string]$Detail
    )

    [pscustomobject]@{
        Check = $Check
        Target = $Target
        Status = $Status
        Detail = $Detail
        CollectedAt = Get-Date
    }
}

try {
    $configurations = @(Get-NetIPConfiguration -ErrorAction Stop |
        Where-Object { $_.NetAdapter -and $_.NetAdapter.Status -eq 'Up' })
    if ($configurations.Count -eq 0) {
        New-DiagnosticResult -Check 'Adapter' -Target $env:COMPUTERNAME -Status 'Warning' -Detail 'No active adapters were returned.'
    }
    else {
        foreach ($config in $configurations) {
            $addresses = @($config.IPv4Address | ForEach-Object { $_.IPAddress })
            $gateways = @($config.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
            $servers = @($config.DNSServer.ServerAddresses | Where-Object { $_ })
            $detail = 'IPv4: {0}; Gateway: {1}; DNS: {2}' -f (
                ($addresses -join ', '), ($gateways -join ', '), ($servers -join ', ')
            )
            New-DiagnosticResult -Check 'Adapter' -Target $config.InterfaceAlias -Status 'Info' -Detail $detail
        }
    }
}
catch {
    New-DiagnosticResult -Check 'Adapter' -Target $env:COMPUTERNAME -Status 'Error' -Detail $_.Exception.Message
}

try {
    $resolved = @([System.Net.Dns]::GetHostAddresses($DnsName) |
        ForEach-Object { $_.IPAddressToString })
    if ($resolved.Count -eq 0) {
        New-DiagnosticResult -Check 'DNS' -Target $DnsName -Status 'Fail' -Detail 'No address records returned.'
    }
    else {
        New-DiagnosticResult -Check 'DNS' -Target $DnsName -Status 'Pass' -Detail ($resolved -join ', ')
    }
}
catch {
    New-DiagnosticResult -Check 'DNS' -Target $DnsName -Status 'Fail' -Detail $_.Exception.Message
}

if ($PSBoundParameters.ContainsKey('TcpHost')) {
    $client = $null
    $asyncResult = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $client.BeginConnect($TcpHost, $TcpPort, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            throw "Connection timed out after $TimeoutMilliseconds ms."
        }
        $client.EndConnect($asyncResult)
        New-DiagnosticResult -Check 'TCP' -Target "${TcpHost}:${TcpPort}" -Status 'Pass' -Detail 'TCP connection succeeded.'
    }
    catch {
        New-DiagnosticResult -Check 'TCP' -Target "${TcpHost}:${TcpPort}" -Status 'Fail' -Detail $_.Exception.Message
    }
    finally {
        if ($null -ne $asyncResult) { $asyncResult.AsyncWaitHandle.Close() }
        if ($null -ne $client) { $client.Close() }
    }
}
