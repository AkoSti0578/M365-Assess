BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-PasswordPolicyReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgDomain { }
    function Get-MgPolicyAuthorizationPolicy { }
}

Describe 'Get-PasswordPolicyReport' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — one row per domain enriched with auth policy data' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgDomain {
                @(
                    [PSCustomObject]@{
                        Id                                = 'contoso.com'
                        IsDefault                         = $true
                        PasswordValidityPeriodInDays      = 90
                        PasswordNotificationWindowInDays  = 14
                    }
                    [PSCustomObject]@{
                        Id                                = 'contoso.onmicrosoft.com'
                        IsDefault                         = $false
                        PasswordValidityPeriodInDays      = 2147483647
                        PasswordNotificationWindowInDays  = 14
                    }
                )
            }

            Mock Get-MgPolicyAuthorizationPolicy {
                [PSCustomObject]@{
                    AllowEmailVerifiedUsersToJoinOrganization = $true
                    AllowedToUseSSPR                         = $true
                }
            }
        }

        It 'should return one row per domain' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 2
        }

        It 'should include Domain property' {
            $result = & $script:ScriptPath
            $domains = @($result | Select-Object -ExpandProperty Domain)
            $domains | Should -Contain 'contoso.com'
            $domains | Should -Contain 'contoso.onmicrosoft.com'
        }

        It 'should include IsDefault property' {
            $result = & $script:ScriptPath
            $defaultDomain = @($result | Where-Object { $_.Domain -eq 'contoso.com' })[0]
            $defaultDomain.IsDefault | Should -Be $true

            $otherDomain = @($result | Where-Object { $_.Domain -eq 'contoso.onmicrosoft.com' })[0]
            $otherDomain.IsDefault | Should -Be $false
        }

        It 'should include PasswordValidityPeriod from domain' {
            $result = & $script:ScriptPath
            $defaultDomain = @($result | Where-Object { $_.Domain -eq 'contoso.com' })[0]
            $defaultDomain.PasswordValidityPeriod | Should -Be 90
        }

        It 'should include PasswordNotificationWindowInDays from domain' {
            $result = & $script:ScriptPath
            $defaultDomain = @($result | Where-Object { $_.Domain -eq 'contoso.com' })[0]
            $defaultDomain.PasswordNotificationWindowInDays | Should -Be 14
        }

        It 'should enrich with AllowCloudPasswordValidation from auth policy' {
            $result = & $script:ScriptPath
            $result[0].AllowCloudPasswordValidation | Should -Be $true
        }

        It 'should enrich with AllowEmailVerifiedUsersToJoinOrganization from auth policy' {
            $result = & $script:ScriptPath
            $result[0].AllowEmailVerifiedUsersToJoinOrganization | Should -Be $true
        }

        It 'should apply auth policy values consistently to all domain rows' {
            $result = & $script:ScriptPath
            $result[0].AllowCloudPasswordValidation | Should -Be $result[1].AllowCloudPasswordValidation
            $result[0].AllowEmailVerifiedUsersToJoinOrganization | Should -Be $result[1].AllowEmailVerifiedUsersToJoinOrganization
        }

        It 'should have all expected properties on each row' {
            $result = & $script:ScriptPath
            $properties = $result[0].PSObject.Properties.Name
            $properties | Should -Contain 'Domain'
            $properties | Should -Contain 'IsDefault'
            $properties | Should -Contain 'PasswordValidityPeriod'
            $properties | Should -Contain 'PasswordNotificationWindowInDays'
            $properties | Should -Contain 'AllowCloudPasswordValidation'
            $properties | Should -Contain 'AllowEmailVerifiedUsersToJoinOrganization'
        }

        It 'should sort results by Domain' {
            $result = & $script:ScriptPath
            $result[0].Domain | Should -Be 'contoso.com'
            $result[1].Domain | Should -Be 'contoso.onmicrosoft.com'
        }
    }

    Context 'when only one domain exists' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDomain {
                @([PSCustomObject]@{
                    Id                                = 'single.onmicrosoft.com'
                    IsDefault                         = $true
                    PasswordValidityPeriodInDays      = 2147483647
                    PasswordNotificationWindowInDays  = 14
                })
            }
            Mock Get-MgPolicyAuthorizationPolicy {
                [PSCustomObject]@{
                    AllowEmailVerifiedUsersToJoinOrganization = $false
                    AllowedToUseSSPR                         = $false
                }
            }
        }

        It 'should return exactly one row' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 1
        }

        It 'should reflect auth policy values correctly' {
            $result = & $script:ScriptPath
            $result.AllowCloudPasswordValidation | Should -Be $false
            $result.AllowEmailVerifiedUsersToJoinOrganization | Should -Be $false
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

    Context 'when Get-MgDomain fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDomain { throw 'Access denied' }
        }

        It 'should write an error about domain retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve domain information*'
        }
    }

    Context 'when Get-MgPolicyAuthorizationPolicy fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDomain {
                @([PSCustomObject]@{
                    Id = 'test.com'; IsDefault = $true
                    PasswordValidityPeriodInDays = 90
                    PasswordNotificationWindowInDays = 14
                })
            }
            Mock Get-MgPolicyAuthorizationPolicy { throw 'Insufficient privileges' }
        }

        It 'should write an error about authorization policy retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve authorization policy*'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDomain {
                @([PSCustomObject]@{
                    Id = 'output.com'; IsDefault = $true
                    PasswordValidityPeriodInDays = 90
                    PasswordNotificationWindowInDays = 14
                })
            }
            Mock Get-MgPolicyAuthorizationPolicy {
                [PSCustomObject]@{
                    AllowEmailVerifiedUsersToJoinOrganization = $false
                    AllowedToUseSSPR = $true
                }
            }
            $script:csvOutputPath = Join-Path $TestDrive 'password-policies.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported password policy report'
        }
    }
}
