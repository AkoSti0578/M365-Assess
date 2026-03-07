BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-ConditionalAccessReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgIdentityConditionalAccessPolicy { }
}

Describe 'Get-ConditionalAccessReport' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — flattens policies correctly' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            $mockPolicies = @(
                [PSCustomObject]@{
                    DisplayName      = 'Require MFA for Admins'
                    State            = 'enabled'
                    CreatedDateTime  = '2024-01-10T12:00:00Z'
                    ModifiedDateTime = '2024-06-15T08:00:00Z'
                    Conditions       = [PSCustomObject]@{
                        Users = [PSCustomObject]@{
                            IncludeUsers = @('All')
                            ExcludeUsers = @('guest-id-1', 'breakglass-id-1')
                        }
                        Applications = [PSCustomObject]@{
                            IncludeApplications = @('All')
                        }
                    }
                    GrantControls = [PSCustomObject]@{
                        BuiltInControls = @('mfa')
                        Operator        = 'OR'
                    }
                    SessionControls = [PSCustomObject]@{
                        SignInFrequency = [PSCustomObject]@{
                            IsEnabled = $true
                            Value     = 1
                            Type      = 'hours'
                        }
                        PersistentBrowser = [PSCustomObject]@{
                            IsEnabled = $false
                            Mode      = $null
                        }
                        CloudAppSecurity = [PSCustomObject]@{
                            IsEnabled            = $false
                            CloudAppSecurityType = $null
                        }
                        ApplicationEnforcedRestrictions = [PSCustomObject]@{
                            IsEnabled = $false
                        }
                    }
                }
                [PSCustomObject]@{
                    DisplayName      = 'Block Legacy Auth'
                    State            = 'enabledForReportingButNotEnforced'
                    CreatedDateTime  = '2024-03-01T09:00:00Z'
                    ModifiedDateTime = $null
                    Conditions       = [PSCustomObject]@{
                        Users = [PSCustomObject]@{
                            IncludeUsers = @('All')
                            ExcludeUsers = @()
                        }
                        Applications = [PSCustomObject]@{
                            IncludeApplications = @('Office365')
                        }
                    }
                    GrantControls = [PSCustomObject]@{
                        BuiltInControls = @('block')
                        Operator        = $null
                    }
                    SessionControls = [PSCustomObject]@{
                        SignInFrequency = [PSCustomObject]@{ IsEnabled = $false }
                        PersistentBrowser = [PSCustomObject]@{
                            IsEnabled = $true
                            Mode      = 'never'
                        }
                        CloudAppSecurity = [PSCustomObject]@{
                            IsEnabled            = $true
                            CloudAppSecurityType = 'monitorOnly'
                        }
                        ApplicationEnforcedRestrictions = [PSCustomObject]@{
                            IsEnabled = $true
                        }
                    }
                }
            )

            Mock Get-MgIdentityConditionalAccessPolicy { return $mockPolicies }
        }

        It 'should return one row per policy' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 2
        }

        It 'should include DisplayName property' {
            $result = & $script:ScriptPath
            $names = @($result | Select-Object -ExpandProperty DisplayName)
            $names | Should -Contain 'Require MFA for Admins'
            $names | Should -Contain 'Block Legacy Auth'
        }

        It 'should include State property' {
            $result = & $script:ScriptPath
            $blockPolicy = @($result | Where-Object { $_.DisplayName -eq 'Block Legacy Auth' })[0]
            $blockPolicy.State | Should -Be 'enabledForReportingButNotEnforced'
        }

        It 'should flatten IncludeUsers to a semicolon-delimited string' {
            $result = & $script:ScriptPath
            $mfaPolicy = @($result | Where-Object { $_.DisplayName -match 'MFA' })[0]
            $mfaPolicy.IncludeUsers | Should -Be 'All'
        }

        It 'should flatten ExcludeUsers to a semicolon-delimited string' {
            $result = & $script:ScriptPath
            $mfaPolicy = @($result | Where-Object { $_.DisplayName -match 'MFA' })[0]
            $mfaPolicy.ExcludeUsers | Should -Match ';'
        }

        It 'should flatten IncludeApplications correctly' {
            $result = & $script:ScriptPath
            $blockPolicy = @($result | Where-Object { $_.DisplayName -eq 'Block Legacy Auth' })[0]
            $blockPolicy.IncludeApplications | Should -Be 'Office365'
        }

        It 'should flatten GrantControls with operator when multiple' {
            $result = & $script:ScriptPath
            $mfaPolicy = @($result | Where-Object { $_.DisplayName -match 'MFA' })[0]
            $mfaPolicy.GrantControls | Should -Be 'mfa'
        }

        It 'should flatten SessionControls for SignInFrequency' {
            $result = & $script:ScriptPath
            $mfaPolicy = @($result | Where-Object { $_.DisplayName -match 'MFA' })[0]
            $mfaPolicy.SessionControls | Should -Match 'SignInFrequency: 1 hours'
        }

        It 'should include PersistentBrowser in SessionControls when enabled' {
            $result = & $script:ScriptPath
            $blockPolicy = @($result | Where-Object { $_.DisplayName -eq 'Block Legacy Auth' })[0]
            $blockPolicy.SessionControls | Should -Match 'PersistentBrowser: never'
        }

        It 'should include CloudAppSecurity in SessionControls when enabled' {
            $result = & $script:ScriptPath
            $blockPolicy = @($result | Where-Object { $_.DisplayName -eq 'Block Legacy Auth' })[0]
            $blockPolicy.SessionControls | Should -Match 'CloudAppSecurity: monitorOnly'
        }

        It 'should include AppEnforcedRestrictions in SessionControls when enabled' {
            $result = & $script:ScriptPath
            $blockPolicy = @($result | Where-Object { $_.DisplayName -eq 'Block Legacy Auth' })[0]
            $blockPolicy.SessionControls | Should -Match 'AppEnforcedRestrictions'
        }

        It 'should have all expected properties on each row' {
            $result = & $script:ScriptPath
            $properties = $result[0].PSObject.Properties.Name
            $properties | Should -Contain 'DisplayName'
            $properties | Should -Contain 'State'
            $properties | Should -Contain 'CreatedDateTime'
            $properties | Should -Contain 'ModifiedDateTime'
            $properties | Should -Contain 'IncludeUsers'
            $properties | Should -Contain 'ExcludeUsers'
            $properties | Should -Contain 'IncludeApplications'
            $properties | Should -Contain 'GrantControls'
            $properties | Should -Contain 'SessionControls'
        }

        It 'should sort results by DisplayName' {
            $result = & $script:ScriptPath
            $result[0].DisplayName | Should -Be 'Block Legacy Auth'
            $result[1].DisplayName | Should -Be 'Require MFA for Admins'
        }
    }

    Context 'when no Conditional Access policies exist' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgIdentityConditionalAccessPolicy { return @() }
        }

        It 'should return an empty collection' {
            $result = & $script:ScriptPath
            @($result | Where-Object { $null -ne $_ }).Count | Should -Be 0
        }
    }

    Context 'when policy has no grant controls or session controls' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgIdentityConditionalAccessPolicy {
                @([PSCustomObject]@{
                    DisplayName      = 'Minimal Policy'
                    State            = 'disabled'
                    CreatedDateTime  = '2024-01-01T00:00:00Z'
                    ModifiedDateTime = $null
                    Conditions       = [PSCustomObject]@{
                        Users = [PSCustomObject]@{
                            IncludeUsers = $null
                            ExcludeUsers = $null
                        }
                        Applications = [PSCustomObject]@{
                            IncludeApplications = $null
                        }
                    }
                    GrantControls = [PSCustomObject]@{
                        BuiltInControls = $null
                        Operator        = $null
                    }
                    SessionControls = [PSCustomObject]@{
                        SignInFrequency = [PSCustomObject]@{ IsEnabled = $false }
                        PersistentBrowser = [PSCustomObject]@{ IsEnabled = $false }
                        CloudAppSecurity = [PSCustomObject]@{ IsEnabled = $false }
                        ApplicationEnforcedRestrictions = [PSCustomObject]@{ IsEnabled = $false }
                    }
                })
            }
        }

        It 'should return empty strings for flattened fields' {
            $result = & $script:ScriptPath
            $result.IncludeUsers | Should -Be ''
            $result.ExcludeUsers | Should -Be ''
            $result.IncludeApplications | Should -Be ''
            $result.GrantControls | Should -Be ''
            $result.SessionControls | Should -Be ''
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

    Context 'when Get-MgIdentityConditionalAccessPolicy fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgIdentityConditionalAccessPolicy { throw '403 Forbidden' }
        }

        It 'should write an error about policy retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve Conditional Access policies*'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgIdentityConditionalAccessPolicy {
                @([PSCustomObject]@{
                    DisplayName      = 'Test Policy'
                    State            = 'enabled'
                    CreatedDateTime  = '2024-01-01T00:00:00Z'
                    ModifiedDateTime = $null
                    Conditions       = [PSCustomObject]@{
                        Users = [PSCustomObject]@{ IncludeUsers = @('All'); ExcludeUsers = @() }
                        Applications = [PSCustomObject]@{ IncludeApplications = @('All') }
                    }
                    GrantControls = [PSCustomObject]@{ BuiltInControls = @('mfa'); Operator = 'OR' }
                    SessionControls = [PSCustomObject]@{
                        SignInFrequency = [PSCustomObject]@{ IsEnabled = $false }
                        PersistentBrowser = [PSCustomObject]@{ IsEnabled = $false }
                        CloudAppSecurity = [PSCustomObject]@{ IsEnabled = $false }
                        ApplicationEnforcedRestrictions = [PSCustomObject]@{ IsEnabled = $false }
                    }
                })
            }
            $script:csvOutputPath = Join-Path $TestDrive 'ca-report.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported Conditional Access report'
        }
    }
}
