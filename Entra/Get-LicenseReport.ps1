<#
.SYNOPSIS
    Generates a report of Microsoft 365 license assignments and availability.
.DESCRIPTION
    Queries Microsoft Graph for all subscribed SKUs in the tenant and reports
    on total, assigned, and available license counts. Optionally exports per-user
    license assignments. Essential for client license audits and cost optimization.

    Requires Microsoft.Graph.Users module and Organization.Read.All permission.
.PARAMETER IncludeUserDetail
    Include per-user license assignment detail in the output. Without this flag,
    only the SKU summary is returned.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service Graph -Scopes 'Organization.Read.All'
    PS> .\Entra\Get-LicenseReport.ps1

    Displays a summary of all license SKUs with total, assigned, and available counts.
.EXAMPLE
    PS> .\Entra\Get-LicenseReport.ps1 -IncludeUserDetail -OutputPath '.\license-report.csv'

    Exports per-user license assignments to CSV.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$IncludeUserDetail,

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Verify Graph connection
try {
    $context = Get-MgContext
    if (-not $context) {
        Write-Error "Not connected to Microsoft Graph. Run Connect-Service -Service Graph first."
        return
    }
}
catch {
    Write-Error "Not connected to Microsoft Graph. Run Connect-Service -Service Graph first."
    return
}

# Ensure required Graph submodules are loaded (PS 7.x does not auto-import)
Import-Module -Name Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
Import-Module -Name Microsoft.Graph.Users -ErrorAction Stop

# Friendly names for common SKU part numbers
$skuFriendlyNames = @{
    'O365_BUSINESS_ESSENTIALS'     = 'Microsoft 365 Business Basic'
    'O365_BUSINESS_PREMIUM'        = 'Microsoft 365 Business Standard'
    'SPB'                          = 'Microsoft 365 Business Premium'
    'ENTERPRISEPACK'               = 'Office 365 E3'
    'ENTERPRISEPREMIUM'            = 'Office 365 E5'
    'SPE_E3'                       = 'Microsoft 365 E3'
    'SPE_E5'                       = 'Microsoft 365 E5'
    'SPE_F1'                       = 'Microsoft 365 F3'
    'EXCHANGESTANDARD'             = 'Exchange Online (Plan 1)'
    'EXCHANGEENTERPRISE'           = 'Exchange Online (Plan 2)'
    'EMS'                          = 'Enterprise Mobility + Security E3'
    'EMSPREMIUM'                   = 'Enterprise Mobility + Security E5'
    'POWER_BI_STANDARD'            = 'Power BI (Free)'
    'POWER_BI_PRO'                 = 'Power BI Pro'
    'PROJECTPREMIUM'               = 'Project Plan 5'
    'VISIOCLIENT'                  = 'Visio Plan 2'
    'AAD_PREMIUM'                  = 'Entra ID P1'
    'AAD_PREMIUM_P2'               = 'Entra ID P2'
    'WIN_DEF_ATP'                  = 'Microsoft Defender for Endpoint P2'
    'IDENTITY_THREAT_PROTECTION'   = 'Microsoft 365 E5 Security'
    'ATP_ENTERPRISE'               = 'Microsoft Defender for Office 365 P1'
    'THREAT_INTELLIGENCE'          = 'Microsoft Defender for Office 365 P2'
}

try {
    Write-Verbose "Retrieving subscribed SKUs..."
    $skus = Get-MgSubscribedSku -All
}
catch {
    Write-Error "Failed to retrieve license information: $_"
    return
}

if (-not $IncludeUserDetail) {
    # SKU summary only
    $report = foreach ($sku in $skus) {
        $friendlyName = $skuFriendlyNames[$sku.SkuPartNumber]
        if (-not $friendlyName) { $friendlyName = $sku.SkuPartNumber }

        [PSCustomObject]@{
            License        = $friendlyName
            SkuPartNumber  = $sku.SkuPartNumber
            Total          = $sku.PrepaidUnits.Enabled
            Assigned       = $sku.ConsumedUnits
            Available      = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
            Suspended      = $sku.PrepaidUnits.Suspended
            Warning        = $sku.PrepaidUnits.Warning
        }
    }

    $report = @($report) | Sort-Object -Property License

    if ($OutputPath) {
        $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported license summary ($($report.Count) SKUs) to $OutputPath"
    }
    else {
        Write-Output $report
    }
}
else {
    # Per-user license detail
    Write-Verbose "Retrieving per-user license assignments..."
    try {
        $users = Get-MgUser -Property 'Id','DisplayName','UserPrincipalName','AssignedLicenses' -All
    }
    catch {
        Write-Error "Failed to retrieve user license data: $_"
        return
    }

    # Build a SkuId-to-name lookup
    $skuLookup = @{}
    foreach ($sku in $skus) {
        $friendlyName = $skuFriendlyNames[$sku.SkuPartNumber]
        if (-not $friendlyName) { $friendlyName = $sku.SkuPartNumber }
        $skuLookup[$sku.SkuId] = $friendlyName
    }

    $report = foreach ($user in $users) {
        if ($user.AssignedLicenses.Count -eq 0) { continue }

        $licenseNames = foreach ($license in $user.AssignedLicenses) {
            $name = $skuLookup[$license.SkuId]
            if (-not $name) { $name = $license.SkuId }
            $name
        }

        [PSCustomObject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            LicenseCount      = $user.AssignedLicenses.Count
            Licenses          = $licenseNames -join '; '
        }
    }

    $report = @($report) | Sort-Object -Property DisplayName

    if ($OutputPath) {
        $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Output "Exported per-user license detail ($($report.Count) users) to $OutputPath"
    }
    else {
        Write-Output $report
    }
}
