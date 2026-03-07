BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-UserSummary.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgUser { }
}

Describe 'Get-UserSummary' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — counts users correctly' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            $mockUsers = @(
                # Licensed, enabled, cloud-only member with sign-in activity
                [PSCustomObject]@{
                    Id                    = '1'
                    DisplayName           = 'Alice Admin'
                    UserPrincipalName     = 'alice@contoso.com'
                    UserType              = 'Member'
                    AccountEnabled        = $true
                    AssignedLicenses      = @([PSCustomObject]@{ SkuId = 'sku1' })
                    OnPremisesSyncEnabled = $false
                    SignInActivity        = [PSCustomObject]@{ LastSignInDateTime = '2025-01-15T10:00:00Z' }
                }
                # Licensed, enabled, synced member with sign-in activity
                [PSCustomObject]@{
                    Id                    = '2'
                    DisplayName           = 'Bob User'
                    UserPrincipalName     = 'bob@contoso.com'
                    UserType              = 'Member'
                    AccountEnabled        = $true
                    AssignedLicenses      = @([PSCustomObject]@{ SkuId = 'sku1' })
                    OnPremisesSyncEnabled = $true
                    SignInActivity        = [PSCustomObject]@{ LastSignInDateTime = '2025-02-01T08:00:00Z' }
                }
                # Guest user, no license, enabled, cloud-only, no sign-in
                [PSCustomObject]@{
                    Id                    = '3'
                    DisplayName           = 'Charlie Guest'
                    UserPrincipalName     = 'charlie_guest@contoso.com'
                    UserType              = 'Guest'
                    AccountEnabled        = $true
                    AssignedLicenses      = @()
                    OnPremisesSyncEnabled = $false
                    SignInActivity        = [PSCustomObject]@{ LastSignInDateTime = $null }
                }
                # Disabled user, licensed, cloud-only, no sign-in
                [PSCustomObject]@{
                    Id                    = '4'
                    DisplayName           = 'Dana Disabled'
                    UserPrincipalName     = 'dana@contoso.com'
                    UserType              = 'Member'
                    AccountEnabled        = $false
                    AssignedLicenses      = @([PSCustomObject]@{ SkuId = 'sku2' })
                    OnPremisesSyncEnabled = $false
                    SignInActivity        = [PSCustomObject]@{ LastSignInDateTime = $null }
                }
            )

            Mock Get-MgUser { return $mockUsers }
        }

        It 'should return exactly one summary object' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 1
        }

        It 'should count total users correctly' {
            $result = & $script:ScriptPath
            $result.TotalUsers | Should -Be 4
        }

        It 'should count licensed users correctly' {
            $result = & $script:ScriptPath
            $result.Licensed | Should -Be 3
        }

        It 'should count guest users correctly' {
            $result = & $script:ScriptPath
            $result.GuestUsers | Should -Be 1
        }

        It 'should count disabled users correctly' {
            $result = & $script:ScriptPath
            $result.DisabledUsers | Should -Be 1
        }

        It 'should count synced-from-on-prem users correctly' {
            $result = & $script:ScriptPath
            $result.SyncedFromOnPrem | Should -Be 1
        }

        It 'should count cloud-only users correctly' {
            $result = & $script:ScriptPath
            $result.CloudOnly | Should -Be 3
        }

        It 'should count users with MFA (sign-in activity) correctly' {
            $result = & $script:ScriptPath
            $result.WithMFA | Should -Be 2
        }

        It 'should have all expected properties' {
            $result = & $script:ScriptPath
            $properties = $result.PSObject.Properties.Name
            $properties | Should -Contain 'TotalUsers'
            $properties | Should -Contain 'Licensed'
            $properties | Should -Contain 'GuestUsers'
            $properties | Should -Contain 'DisabledUsers'
            $properties | Should -Contain 'SyncedFromOnPrem'
            $properties | Should -Contain 'CloudOnly'
            $properties | Should -Contain 'WithMFA'
        }
    }

    Context 'when no users exist (empty result)' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgUser { return @() }
        }

        It 'should return a summary with all zeros' {
            $result = & $script:ScriptPath
            $result.TotalUsers | Should -Be 0
            $result.Licensed | Should -Be 0
            $result.GuestUsers | Should -Be 0
            $result.DisabledUsers | Should -Be 0
            $result.SyncedFromOnPrem | Should -Be 0
            $result.CloudOnly | Should -Be 0
            $result.WithMFA | Should -Be 0
        }
    }

    Context 'when not connected to Microsoft Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should write an error about missing connection' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when Get-MgContext throws' {
        BeforeAll {
            Mock Get-MgContext { throw 'Module not loaded' }
        }

        It 'should write an error about missing connection' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when Get-MgUser fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgUser { throw 'Insufficient privileges' }
        }

        It 'should write an error about user retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve users from Microsoft Graph*'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgUser { return @() }
            $script:csvOutputPath = Join-Path $TestDrive 'user-summary.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported user summary'
        }
    }
}
