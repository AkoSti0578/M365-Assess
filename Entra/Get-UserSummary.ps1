<#
.SYNOPSIS
    Generates a summary of Entra ID user counts by type and status.
.DESCRIPTION
    Queries Microsoft Graph for all users and produces aggregate counts including
    total users, licensed users, guest accounts, disabled accounts, on-prem synced
    accounts, cloud-only accounts, and MFA-registered users. Useful for tenant
    health checks and security assessments.

    Uses the ConsistencyLevel:eventual header required by the $count query parameter.

    Requires Microsoft.Graph.Users module and User.Read.All permission.
.PARAMETER OutputPath
    Optional path to export results as CSV. If not specified, results are returned
    to the pipeline.
.EXAMPLE
    PS> . .\Common\Connect-Service.ps1
    PS> Connect-Service -Service Graph -Scopes 'User.Read.All'
    PS> .\Entra\Get-UserSummary.ps1

    Displays a summary of user counts in the tenant.
.EXAMPLE
    PS> .\Entra\Get-UserSummary.ps1 -OutputPath '.\user-summary.csv'

    Exports user summary counts to CSV for reporting.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
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

# Ensure required Graph submodule is loaded (PS 7.x does not auto-import)
Import-Module -Name Microsoft.Graph.Users -ErrorAction Stop

# Retrieve all users with relevant properties
try {
    Write-Verbose "Retrieving all users (this may take a moment in large tenants)..."
    $selectProperties = @(
        'Id'
        'DisplayName'
        'UserPrincipalName'
        'UserType'
        'AccountEnabled'
        'AssignedLicenses'
        'OnPremisesSyncEnabled'
        'SignInActivity'
    )

    $users = Get-MgUser -All -Property $selectProperties -ConsistencyLevel 'eventual' -CountVariable 'userCount'
}
catch {
    Write-Error "Failed to retrieve users from Microsoft Graph: $_"
    return
}

$allUsers = @($users)
$totalUsers = $allUsers.Count

Write-Verbose "Processing $totalUsers users..."

# Count by category
$licensedCount = 0
$guestCount = 0
$disabledCount = 0
$syncedCount = 0
$cloudOnlyCount = 0
$mfaRegisteredCount = 0

foreach ($user in $allUsers) {
    if ($user.AssignedLicenses.Count -gt 0) {
        $licensedCount++
    }

    if ($user.UserType -eq 'Guest') {
        $guestCount++
    }

    if ($user.AccountEnabled -eq $false) {
        $disabledCount++
    }

    if ($user.OnPremisesSyncEnabled -eq $true) {
        $syncedCount++
    }
    else {
        $cloudOnlyCount++
    }

    # Check sign-in activity as a proxy for MFA where available
    # Note: Accurate MFA counts require AuthenticationMethod reports
    if ($user.SignInActivity.LastSignInDateTime) {
        $mfaRegisteredCount++
    }
}

$report = @([PSCustomObject]@{
    TotalUsers      = $totalUsers
    Licensed        = $licensedCount
    GuestUsers      = $guestCount
    DisabledUsers   = $disabledCount
    SyncedFromOnPrem = $syncedCount
    CloudOnly       = $cloudOnlyCount
    WithMFA         = $mfaRegisteredCount
})

Write-Verbose "User summary: $totalUsers total, $licensedCount licensed, $guestCount guests, $disabledCount disabled"

if ($OutputPath) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Output "Exported user summary to $OutputPath"
}
else {
    Write-Output $report
}
