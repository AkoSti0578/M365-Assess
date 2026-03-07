BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Intune/Get-CompliancePolicyReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgDeviceManagementDeviceCompliancePolicy { }
}

Describe 'Get-CompliancePolicyReport' {
    BeforeAll {
        Mock Import-Module { }
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when compliance policies are returned' {
        BeforeAll {
            $mockPolicies = @(
                [PSCustomObject]@{
                    DisplayName          = 'Windows 10 Compliance'
                    Id                   = 'policy-001'
                    CreatedDateTime      = (Get-Date).AddMonths(-6)
                    LastModifiedDateTime = (Get-Date).AddDays(-10)
                    Version              = 1
                    Description          = 'Baseline compliance for Windows 10 devices'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'
                    }
                }
                [PSCustomObject]@{
                    DisplayName          = 'iOS Compliance'
                    Id                   = 'policy-002'
                    CreatedDateTime      = (Get-Date).AddMonths(-3)
                    LastModifiedDateTime = (Get-Date).AddDays(-5)
                    Version              = 2
                    Description          = 'Compliance for iOS devices'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.iosCompliancePolicy'
                    }
                }
                [PSCustomObject]@{
                    DisplayName          = 'Android Work Profile Compliance'
                    Id                   = 'policy-003'
                    CreatedDateTime      = (Get-Date).AddMonths(-1)
                    LastModifiedDateTime = (Get-Date).AddDays(-1)
                    Version              = 1
                    Description          = 'Android Work Profile policy'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.androidWorkProfileCompliancePolicy'
                    }
                }
            )
            Mock Get-MgDeviceManagementDeviceCompliancePolicy { return $mockPolicies }
        }

        It 'should return all policies' {
            $result = & $script:ScriptPath
            $result.Count | Should -Be 3
        }

        It 'should include expected properties' {
            $result = & $script:ScriptPath
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'DisplayName'
            $props | Should -Contain 'Id'
            $props | Should -Contain 'CreatedDateTime'
            $props | Should -Contain 'LastModifiedDateTime'
            $props | Should -Contain 'Platform'
            $props | Should -Contain 'Version'
            $props | Should -Contain 'Description'
        }

        It 'should map Windows 10 odata.type to friendly platform name' {
            $result = & $script:ScriptPath
            $win = $result | Where-Object { $_.DisplayName -eq 'Windows 10 Compliance' }
            $win.Platform | Should -Be 'Windows 10'
        }

        It 'should map iOS odata.type to friendly platform name' {
            $result = & $script:ScriptPath
            $ios = $result | Where-Object { $_.DisplayName -eq 'iOS Compliance' }
            $ios.Platform | Should -Be 'iOS'
        }

        It 'should map Android Work Profile odata.type to friendly platform name' {
            $result = & $script:ScriptPath
            $android = $result | Where-Object { $_.DisplayName -eq 'Android Work Profile Compliance' }
            $android.Platform | Should -Be 'Android Work Profile'
        }

        It 'should sort results by DisplayName' {
            $result = & $script:ScriptPath
            $result[0].DisplayName | Should -Be 'Android Work Profile Compliance'
            $result[1].DisplayName | Should -Be 'iOS Compliance'
            $result[2].DisplayName | Should -Be 'Windows 10 Compliance'
        }
    }

    Context 'when odata.type is not in the platform map' {
        BeforeAll {
            $mockPolicies = @(
                [PSCustomObject]@{
                    DisplayName          = 'Custom Policy'
                    Id                   = 'policy-x'
                    CreatedDateTime      = (Get-Date)
                    LastModifiedDateTime = (Get-Date)
                    Version              = 1
                    Description          = 'Unknown type'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.someNewPlatformCompliancePolicy'
                    }
                }
            )
            Mock Get-MgDeviceManagementDeviceCompliancePolicy { return $mockPolicies }
        }

        It 'should fall back to the raw odata.type value' {
            $result = & $script:ScriptPath
            $result[0].Platform | Should -Be '#microsoft.graph.someNewPlatformCompliancePolicy'
        }
    }

    Context 'when no policies are found' {
        BeforeAll {
            Mock Get-MgDeviceManagementDeviceCompliancePolicy { return @() }
        }

        It 'should return an empty array' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            @($result).Count | Should -Be 0
        }

        It 'should emit a warning' {
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockPolicies = @(
                [PSCustomObject]@{
                    DisplayName = 'Test Policy'; Id = 'p-1'
                    CreatedDateTime = (Get-Date); LastModifiedDateTime = (Get-Date)
                    Version = 1; Description = 'Test'
                    AdditionalProperties = @{ '@odata.type' = '#microsoft.graph.windows10CompliancePolicy' }
                }
            )
            Mock Get-MgDeviceManagementDeviceCompliancePolicy { return $mockPolicies }
            $script:csvOutputPath = Join-Path $TestDrive 'compliance.csv'
        }

        It 'should export results to a CSV file' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported * compliance policies to *'
        }
    }

    Context 'when Graph retrieval fails' {
        BeforeAll {
            Mock Get-MgDeviceManagementDeviceCompliancePolicy { throw 'Insufficient privileges' }
        }

        It 'should write an error' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve compliance policies*'
        }
    }

    Context 'when not connected to Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should write an error about missing connection' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'parameter validation' {
        BeforeAll {
            Mock Get-MgDeviceManagementDeviceCompliancePolicy { return @() }
        }

        It 'should reject empty string for OutputPath' {
            { & $script:ScriptPath -OutputPath '' } | Should -Throw
        }
    }
}
