BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-LicenseReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgSubscribedSku { }
    function Get-MgUser { }
}

Describe 'Get-LicenseReport' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'when returning SKU summary' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgSubscribedSku {
                return @(
                    [PSCustomObject]@{
                        SkuPartNumber = 'ENTERPRISEPACK'
                        SkuId = '00000000-0000-0000-0000-000000000001'
                        ConsumedUnits = 45
                        PrepaidUnits = [PSCustomObject]@{
                            Enabled = 50
                            Suspended = 0
                            Warning = 0
                        }
                    }
                    [PSCustomObject]@{
                        SkuPartNumber = 'EMSPREMIUM'
                        SkuId = '00000000-0000-0000-0000-000000000002'
                        ConsumedUnits = 20
                        PrepaidUnits = [PSCustomObject]@{
                            Enabled = 25
                            Suspended = 0
                            Warning = 2
                        }
                    }
                )
            }
        }

        It 'should return license summary' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'should include expected properties' {
            $result = & $script:ScriptPath
            $result[0].PSObject.Properties.Name | Should -Contain 'License'
            $result[0].PSObject.Properties.Name | Should -Contain 'Total'
            $result[0].PSObject.Properties.Name | Should -Contain 'Assigned'
            $result[0].PSObject.Properties.Name | Should -Contain 'Available'
        }

        It 'should map SKU part numbers to friendly names' {
            $result = & $script:ScriptPath
            $e3 = $result | Where-Object { $_.SkuPartNumber -eq 'ENTERPRISEPACK' }
            $e3.License | Should -Be 'Office 365 E3'
        }

        It 'should calculate available licenses correctly' {
            $result = & $script:ScriptPath
            $e3 = $result | Where-Object { $_.SkuPartNumber -eq 'ENTERPRISEPACK' }
            $e3.Available | Should -Be 5
        }
    }

    Context 'when returning per-user detail' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgSubscribedSku {
                return @(
                    [PSCustomObject]@{
                        SkuPartNumber = 'ENTERPRISEPACK'
                        SkuId = '00000000-0000-0000-0000-000000000001'
                        ConsumedUnits = 1
                        PrepaidUnits = [PSCustomObject]@{ Enabled = 10; Suspended = 0; Warning = 0 }
                    }
                )
            }

            Mock Get-MgUser {
                return @(
                    [PSCustomObject]@{
                        Id = '1'
                        DisplayName = 'John Smith'
                        UserPrincipalName = 'jsmith@contoso.com'
                        AssignedLicenses = @(
                            [PSCustomObject]@{ SkuId = '00000000-0000-0000-0000-000000000001' }
                        )
                    }
                    [PSCustomObject]@{
                        Id = '2'
                        DisplayName = 'Unlicensed User'
                        UserPrincipalName = 'unlic@contoso.com'
                        AssignedLicenses = @()
                    }
                )
            }
        }

        It 'should return only licensed users' {
            $result = & $script:ScriptPath -IncludeUserDetail
            $result.Count | Should -Be 1
            $result[0].DisplayName | Should -Be 'John Smith'
        }

        It 'should include license names in output' {
            $result = & $script:ScriptPath -IncludeUserDetail
            $result[0].Licenses | Should -Match 'Office 365 E3'
        }

        It 'should include LicenseCount' {
            $result = & $script:ScriptPath -IncludeUserDetail
            $result[0].LicenseCount | Should -Be 1
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgSubscribedSku {
                return @(
                    [PSCustomObject]@{
                        SkuPartNumber = 'ENTERPRISEPACK'
                        SkuId = '1'; ConsumedUnits = 1
                        PrepaidUnits = [PSCustomObject]@{ Enabled = 10; Suspended = 0; Warning = 0 }
                    }
                )
            }
            $script:csvOutputPath = Join-Path $TestDrive 'license-test.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported.*license summary'
        }
    }

    Context 'when not connected to Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should throw an error' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when SKU query fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgSubscribedSku { throw 'Access denied' }
        }

        It 'should throw an error' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve license information*'
        }
    }
}
