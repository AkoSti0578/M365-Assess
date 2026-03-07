<#
.SYNOPSIS
    Connects to Microsoft cloud services with standardized error handling.
.DESCRIPTION
    Wraps Connect-MgGraph, Connect-ExchangeOnline, and Connect-IPPSSession
    with consistent error handling, required module checks, and scope management.
    Supports interactive, certificate, and client secret authentication.
.PARAMETER Service
    The service to connect to: Graph, ExchangeOnline, or Purview.
.PARAMETER Scopes
    Microsoft Graph permission scopes. Only used with the Graph service.
    Defaults to 'User.Read.All' if not specified.
.PARAMETER TenantId
    The tenant ID or domain (e.g., 'contoso.onmicrosoft.com'). Optional for
    interactive auth but required for app-only auth.
.PARAMETER ClientId
    Application (client) ID for app-only authentication. Requires TenantId
    and either CertificateThumbprint or ClientSecret.
.PARAMETER CertificateThumbprint
    Certificate thumbprint for app-only authentication.
.PARAMETER ClientSecret
    Client secret for app-only authentication. Less secure than certificate auth.
.PARAMETER UserPrincipalName
    User principal name (e.g., 'admin@contoso.onmicrosoft.com') for interactive
    authentication to Exchange Online or Purview. Bypasses the Windows Authentication
    Manager (WAM) broker which can cause RuntimeBroker errors on some systems.
.EXAMPLE
    PS> .\Common\Connect-Service.ps1 -Service Graph -Scopes 'User.Read.All','Group.Read.All'

    Connects to Microsoft Graph interactively with the specified scopes.
.EXAMPLE
    PS> .\Common\Connect-Service.ps1 -Service ExchangeOnline -TenantId 'contoso.onmicrosoft.com'

    Connects to Exchange Online for the specified tenant.
.EXAMPLE
    PS> .\Common\Connect-Service.ps1 -Service Graph -TenantId 'contoso.onmicrosoft.com' -ClientId '00000000-0000-0000-0000-000000000000' -CertificateThumbprint 'ABC123'

    Connects to Microsoft Graph using certificate-based app-only auth.
.EXAMPLE
    PS> .\Common\Connect-Service.ps1 -Service Purview -UserPrincipalName 'admin@contoso.onmicrosoft.com'

    Connects to Purview using the specified UPN (avoids WAM broker issues).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Graph', 'ExchangeOnline', 'Purview')]
    [string]$Service,

    [Parameter()]
    [string[]]$Scopes = @('User.Read.All'),

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [string]$ClientSecret,

    [Parameter()]
    [string]$UserPrincipalName
)

$ErrorActionPreference = 'Stop'

$moduleMap = @{
    'Graph'           = 'Microsoft.Graph.Authentication'
    'ExchangeOnline'  = 'ExchangeOnlineManagement'
    'Purview'         = 'ExchangeOnlineManagement'
}

$requiredModule = $moduleMap[$Service]

# Check that the required module is available
if (-not (Get-Module -Name $requiredModule -ListAvailable)) {
    Write-Error "Required module '$requiredModule' is not installed. Run: Install-Module -Name $requiredModule -Scope CurrentUser"
    return
}

try {
    switch ($Service) {
        'Graph' {
            $connectParams = @{}
            if ($TenantId) { $connectParams['TenantId'] = $TenantId }

            if ($ClientId -and $CertificateThumbprint) {
                $connectParams['ClientId'] = $ClientId
                $connectParams['CertificateThumbprint'] = $CertificateThumbprint
            }
            elseif ($ClientId -and $ClientSecret) {
                $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
                $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ClientId, $secureSecret
                $connectParams['ClientSecretCredential'] = $credential
            }
            else {
                $connectParams['Scopes'] = $Scopes
            }

            # Suppress Graph SDK welcome banner (available in v2.x+)
            if ((Get-Command Connect-MgGraph -ErrorAction SilentlyContinue) -and
                (Get-Command Connect-MgGraph).Parameters.ContainsKey('NoWelcome')) {
                $connectParams['NoWelcome'] = $true
            }

            Connect-MgGraph @connectParams
            Write-Verbose "Connected to Microsoft Graph"
        }

        'ExchangeOnline' {
            $connectParams = @{
                ShowBanner = $false
            }
            if ($TenantId) { $connectParams['Organization'] = $TenantId }

            if ($ClientId -and $CertificateThumbprint) {
                $connectParams['AppId'] = $ClientId
                $connectParams['CertificateThumbprint'] = $CertificateThumbprint
            }
            elseif ($UserPrincipalName) {
                $connectParams['UserPrincipalName'] = $UserPrincipalName
            }

            Connect-ExchangeOnline @connectParams
            Write-Verbose "Connected to Exchange Online"
        }

        'Purview' {
            $connectParams = @{}
            if ($TenantId) { $connectParams['Organization'] = $TenantId }

            if ($ClientId -and $CertificateThumbprint) {
                $connectParams['AppId'] = $ClientId
                $connectParams['CertificateThumbprint'] = $CertificateThumbprint
            }
            elseif ($UserPrincipalName) {
                $connectParams['UserPrincipalName'] = $UserPrincipalName
            }

            Connect-IPPSSession @connectParams
            Write-Verbose "Connected to Purview (Security & Compliance)"
        }
    }
}
catch {
    Write-Error "Failed to connect to $Service`: $_"
}
