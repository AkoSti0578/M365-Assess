BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-TenantInfo.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgOrganization { }
    function Get-MgDomain { }
    function Invoke-MgGraphRequest { }
}

Describe 'Get-TenantInfo' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — returns tenant information' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgOrganization {
                @([PSCustomObject]@{
                    DisplayName     = 'Contoso Ltd'
                    Id              = '00000000-0000-0000-0000-000000000000'
                    CreatedDateTime = '2020-01-15T10:30:00Z'
                })
            }

            Mock Get-MgDomain {
                @(
                    [PSCustomObject]@{
                        Id         = 'contoso.onmicrosoft.com'
                        IsVerified = $true
                        IsDefault  = $true
                    }
                    [PSCustomObject]@{
                        Id         = 'contoso.com'
                        IsVerified = $true
                        IsDefault  = $false
                    }
                    [PSCustomObject]@{
                        Id         = 'pending.com'
                        IsVerified = $false
                        IsDefault  = $false
                    }
                )
            }

            Mock Invoke-MgGraphRequest {
                @{ isEnabled = $true }
            }
        }

        It 'should return a PSCustomObject' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 1
            $result | Should -BeOfType [PSCustomObject]
        }

        It 'should include OrgDisplayName property' {
            $result = & $script:ScriptPath
            $result.OrgDisplayName | Should -Be 'Contoso Ltd'
        }

        It 'should include TenantId property' {
            $result = & $script:ScriptPath
            $result.TenantId | Should -Be '00000000-0000-0000-0000-000000000000'
        }

        It 'should include only verified domains in VerifiedDomains' {
            $result = & $script:ScriptPath
            $result.VerifiedDomains | Should -Match 'contoso\.com'
            $result.VerifiedDomains | Should -Match 'contoso\.onmicrosoft\.com'
            $result.VerifiedDomains | Should -Not -Match 'pending\.com'
        }

        It 'should identify the default domain' {
            $result = & $script:ScriptPath
            $result.DefaultDomain | Should -Be 'contoso.onmicrosoft.com'
        }

        It 'should include SecurityDefaultsEnabled property' {
            $result = & $script:ScriptPath
            $result.SecurityDefaultsEnabled | Should -Be $true
        }

        It 'should include CreatedDateTime property' {
            $result = & $script:ScriptPath
            $result.CreatedDateTime | Should -Be '2020-01-15T10:30:00Z'
        }

        It 'should have all expected properties' {
            $result = & $script:ScriptPath
            $properties = $result.PSObject.Properties.Name
            $properties | Should -Contain 'OrgDisplayName'
            $properties | Should -Contain 'TenantId'
            $properties | Should -Contain 'VerifiedDomains'
            $properties | Should -Contain 'DefaultDomain'
            $properties | Should -Contain 'SecurityDefaultsEnabled'
            $properties | Should -Contain 'CreatedDateTime'
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

    Context 'when Get-MgOrganization fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgOrganization { throw 'Access denied' }
        }

        It 'should write an error about organization retrieval' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve organization details*'
        }
    }

    Context 'when Get-MgDomain fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgOrganization {
                @([PSCustomObject]@{ DisplayName = 'Contoso'; Id = '123'; CreatedDateTime = '2020-01-01' })
            }
            Mock Get-MgDomain { throw 'Insufficient privileges' }
        }

        It 'should write an error about domain retrieval' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve domain information*'
        }
    }

    Context 'when Invoke-MgGraphRequest for security defaults fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgOrganization {
                @([PSCustomObject]@{ DisplayName = 'Contoso'; Id = '123'; CreatedDateTime = '2020-01-01' })
            }
            Mock Get-MgDomain {
                @([PSCustomObject]@{ Id = 'contoso.com'; IsVerified = $true; IsDefault = $true })
            }
            Mock Invoke-MgGraphRequest { throw '403 Forbidden' }
        }

        It 'should still return results with SecurityDefaultsEnabled as N/A' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 1
            $result.SecurityDefaultsEnabled | Should -Be 'N/A'
        }

        It 'should include other tenant properties despite security defaults failure' {
            $result = & $script:ScriptPath
            $result.OrgDisplayName | Should -Be 'Contoso'
            $result.DefaultDomain | Should -Be 'contoso.com'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgOrganization {
                @([PSCustomObject]@{ DisplayName = 'Contoso'; Id = '123'; CreatedDateTime = '2020-01-01' })
            }
            Mock Get-MgDomain {
                @([PSCustomObject]@{ Id = 'contoso.com'; IsVerified = $true; IsDefault = $true })
            }
            Mock Invoke-MgGraphRequest {
                @{ isEnabled = $false }
            }
            $script:csvOutputPath = Join-Path $TestDrive 'tenant-info.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported tenant info'
        }
    }
}
