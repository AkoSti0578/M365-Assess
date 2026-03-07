BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-MfaReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgReportAuthenticationMethodUserRegistrationDetail { }
}

Describe 'Get-MfaReport' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — returns per-user MFA data' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            $mockDetails = @(
                [PSCustomObject]@{
                    UserPrincipalName     = 'alice@contoso.com'
                    UserDisplayName       = 'Alice Admin'
                    IsMfaRegistered       = $true
                    IsMfaCapable          = $true
                    IsPasswordlessCapable = $false
                    IsSsprRegistered      = $true
                    IsSsprCapable         = $true
                    MethodsRegistered     = @('microsoftAuthenticatorPush', 'phoneAuthentication')
                    DefaultMfaMethod      = 'microsoftAuthenticatorPush'
                    IsAdmin               = $true
                }
                [PSCustomObject]@{
                    UserPrincipalName     = 'bob@contoso.com'
                    UserDisplayName       = 'Bob User'
                    IsMfaRegistered       = $false
                    IsMfaCapable          = $false
                    IsPasswordlessCapable = $false
                    IsSsprRegistered      = $false
                    IsSsprCapable         = $false
                    MethodsRegistered     = @()
                    DefaultMfaMethod      = 'none'
                    IsAdmin               = $false
                }
                [PSCustomObject]@{
                    UserPrincipalName     = 'charlie@contoso.com'
                    UserDisplayName       = 'Charlie User'
                    IsMfaRegistered       = $true
                    IsMfaCapable          = $true
                    IsPasswordlessCapable = $true
                    IsSsprRegistered      = $true
                    IsSsprCapable         = $true
                    MethodsRegistered     = @('fido2', 'microsoftAuthenticatorPush')
                    DefaultMfaMethod      = 'fido2'
                    IsAdmin               = $false
                }
            )

            Mock Get-MgReportAuthenticationMethodUserRegistrationDetail { return $mockDetails }
        }

        It 'should return one row per user' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 3
        }

        It 'should include UserPrincipalName property' {
            $result = & $script:ScriptPath
            $upns = @($result | Select-Object -ExpandProperty UserPrincipalName)
            $upns | Should -Contain 'alice@contoso.com'
            $upns | Should -Contain 'bob@contoso.com'
        }

        It 'should include IsMfaRegistered property' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.UserPrincipalName -eq 'alice@contoso.com' })[0]
            $alice.IsMfaRegistered | Should -Be $true
        }

        It 'should include IsMfaCapable property' {
            $result = & $script:ScriptPath
            $bob = @($result | Where-Object { $_.UserPrincipalName -eq 'bob@contoso.com' })[0]
            $bob.IsMfaCapable | Should -Be $false
        }

        It 'should include IsPasswordlessCapable property' {
            $result = & $script:ScriptPath
            $charlie = @($result | Where-Object { $_.UserPrincipalName -eq 'charlie@contoso.com' })[0]
            $charlie.IsPasswordlessCapable | Should -Be $true
        }

        It 'should include IsSsprRegistered property' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.UserPrincipalName -eq 'alice@contoso.com' })[0]
            $alice.IsSsprRegistered | Should -Be $true
            $bob = @($result | Where-Object { $_.UserPrincipalName -eq 'bob@contoso.com' })[0]
            $bob.IsSsprRegistered | Should -Be $false
        }

        It 'should include IsSsprCapable property' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.UserPrincipalName -eq 'alice@contoso.com' })[0]
            $alice.IsSsprCapable | Should -Be $true
            $bob = @($result | Where-Object { $_.UserPrincipalName -eq 'bob@contoso.com' })[0]
            $bob.IsSsprCapable | Should -Be $false
        }

        It 'should flatten MethodsRegistered to a semicolon-delimited string' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.UserPrincipalName -eq 'alice@contoso.com' })[0]
            $alice.MethodsRegistered | Should -Match 'microsoftAuthenticatorPush'
            $alice.MethodsRegistered | Should -Match 'phoneAuthentication'
            $alice.MethodsRegistered | Should -Match ';'
        }

        It 'should include DefaultMfaMethod property' {
            $result = & $script:ScriptPath
            $charlie = @($result | Where-Object { $_.UserPrincipalName -eq 'charlie@contoso.com' })[0]
            $charlie.DefaultMfaMethod | Should -Be 'fido2'
        }

        It 'should include IsAdmin property' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.UserPrincipalName -eq 'alice@contoso.com' })[0]
            $alice.IsAdmin | Should -Be $true
        }

        It 'should sort results by UserPrincipalName' {
            $result = & $script:ScriptPath
            $upns = @($result | Select-Object -ExpandProperty UserPrincipalName)
            $upns[0] | Should -Be 'alice@contoso.com'
            $upns[1] | Should -Be 'bob@contoso.com'
            $upns[2] | Should -Be 'charlie@contoso.com'
        }

        It 'should have all expected properties on each row' {
            $result = & $script:ScriptPath
            $properties = $result[0].PSObject.Properties.Name
            $properties | Should -Contain 'UserPrincipalName'
            $properties | Should -Contain 'UserDisplayName'
            $properties | Should -Contain 'IsMfaRegistered'
            $properties | Should -Contain 'IsMfaCapable'
            $properties | Should -Contain 'IsPasswordlessCapable'
            $properties | Should -Contain 'IsSsprRegistered'
            $properties | Should -Contain 'IsSsprCapable'
            $properties | Should -Contain 'MethodsRegistered'
            $properties | Should -Contain 'DefaultMfaMethod'
            $properties | Should -Contain 'IsAdmin'
        }
    }

    Context 'when no users have MFA data (empty results)' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgReportAuthenticationMethodUserRegistrationDetail { return @() }
        }

        It 'should return an empty collection' {
            $result = & $script:ScriptPath
            @($result | Where-Object { $null -ne $_ }).Count | Should -Be 0
        }
    }

    Context 'when user has no methods registered' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgReportAuthenticationMethodUserRegistrationDetail {
                @([PSCustomObject]@{
                    UserPrincipalName     = 'nomethod@contoso.com'
                    UserDisplayName       = 'No Method'
                    IsMfaRegistered       = $false
                    IsMfaCapable          = $false
                    IsPasswordlessCapable = $false
                    IsSsprRegistered      = $false
                    IsSsprCapable         = $false
                    MethodsRegistered     = $null
                    DefaultMfaMethod      = 'none'
                    IsAdmin               = $false
                })
            }
        }

        It 'should return empty string for MethodsRegistered' {
            $result = & $script:ScriptPath
            $result.MethodsRegistered | Should -Be ''
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

    Context 'when Get-MgReportAuthenticationMethodUserRegistrationDetail fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgReportAuthenticationMethodUserRegistrationDetail { throw 'Insufficient privileges' }
        }

        It 'should write an error about MFA retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve MFA registration details*'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgReportAuthenticationMethodUserRegistrationDetail {
                @([PSCustomObject]@{
                    UserPrincipalName     = 'test@contoso.com'
                    UserDisplayName       = 'Test User'
                    IsMfaRegistered       = $true
                    IsMfaCapable          = $true
                    IsPasswordlessCapable = $false
                    IsSsprRegistered      = $true
                    IsSsprCapable         = $true
                    MethodsRegistered     = @('phoneAuthentication')
                    DefaultMfaMethod      = 'phoneAuthentication'
                    IsAdmin               = $false
                })
            }
            $script:csvOutputPath = Join-Path $TestDrive 'mfa-report.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported MFA report'
        }
    }
}
