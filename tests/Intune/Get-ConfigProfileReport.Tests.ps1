BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Intune/Get-ConfigProfileReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgDeviceManagementDeviceConfiguration { }
}

Describe 'Get-ConfigProfileReport' {
    BeforeAll {
        Mock Import-Module { }
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when configuration profiles are returned' {
        BeforeAll {
            $mockProfiles = @(
                [PSCustomObject]@{
                    DisplayName          = 'Windows 10 General Config'
                    Id                   = 'profile-001'
                    CreatedDateTime      = (Get-Date).AddMonths(-6)
                    LastModifiedDateTime = (Get-Date).AddDays(-10)
                    Version              = 1
                    Description          = 'General Windows 10 settings'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                    }
                }
                [PSCustomObject]@{
                    DisplayName          = 'iOS Device Config'
                    Id                   = 'profile-002'
                    CreatedDateTime      = (Get-Date).AddMonths(-3)
                    LastModifiedDateTime = (Get-Date).AddDays(-5)
                    Version              = 2
                    Description          = 'iOS general settings'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.iosGeneralDeviceConfiguration'
                    }
                }
                [PSCustomObject]@{
                    DisplayName          = 'macOS Custom Config'
                    Id                   = 'profile-003'
                    CreatedDateTime      = (Get-Date).AddMonths(-1)
                    LastModifiedDateTime = (Get-Date).AddDays(-1)
                    Version              = 1
                    Description          = 'Custom macOS configuration'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.macOSCustomConfiguration'
                    }
                }
                [PSCustomObject]@{
                    DisplayName          = 'Defender ATP Config'
                    Id                   = 'profile-004'
                    CreatedDateTime      = (Get-Date).AddMonths(-2)
                    LastModifiedDateTime = (Get-Date).AddDays(-3)
                    Version              = 1
                    Description          = 'Windows Defender ATP settings'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.windowsDefenderAdvancedThreatProtectionConfiguration'
                    }
                }
            )
            Mock Get-MgDeviceManagementDeviceConfiguration { return $mockProfiles }
        }

        It 'should return all profiles' {
            $result = & $script:ScriptPath
            $result.Count | Should -Be 4
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

        It 'should map windows10GeneralConfiguration to Windows 10' {
            $result = & $script:ScriptPath
            $win = $result | Where-Object { $_.DisplayName -eq 'Windows 10 General Config' }
            $win.Platform | Should -Be 'Windows 10'
        }

        It 'should map iosGeneralDeviceConfiguration to iOS' {
            $result = & $script:ScriptPath
            $ios = $result | Where-Object { $_.DisplayName -eq 'iOS Device Config' }
            $ios.Platform | Should -Be 'iOS'
        }

        It 'should map macOSCustomConfiguration to macOS (Custom)' {
            $result = & $script:ScriptPath
            $mac = $result | Where-Object { $_.DisplayName -eq 'macOS Custom Config' }
            $mac.Platform | Should -Be 'macOS (Custom)'
        }

        It 'should map windowsDefenderAdvancedThreatProtectionConfiguration to Windows Defender ATP' {
            $result = & $script:ScriptPath
            $atp = $result | Where-Object { $_.DisplayName -eq 'Defender ATP Config' }
            $atp.Platform | Should -Be 'Windows Defender ATP'
        }

        It 'should sort results by DisplayName' {
            $result = & $script:ScriptPath
            $result[0].DisplayName | Should -Be 'Defender ATP Config'
            $result[1].DisplayName | Should -Be 'iOS Device Config'
            $result[2].DisplayName | Should -Be 'macOS Custom Config'
            $result[3].DisplayName | Should -Be 'Windows 10 General Config'
        }
    }

    Context 'when odata.type is not in the platform map' {
        BeforeAll {
            $mockProfiles = @(
                [PSCustomObject]@{
                    DisplayName = 'Future Platform Config'; Id = 'profile-x'
                    CreatedDateTime = (Get-Date); LastModifiedDateTime = (Get-Date)
                    Version = 1; Description = 'Unknown platform'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.chromebookGeneralConfiguration'
                    }
                }
            )
            Mock Get-MgDeviceManagementDeviceConfiguration { return $mockProfiles }
        }

        It 'should fall back to the raw odata.type value' {
            $result = & $script:ScriptPath
            $result[0].Platform | Should -Be '#microsoft.graph.chromebookGeneralConfiguration'
        }
    }

    Context 'when no profiles are found' {
        BeforeAll {
            Mock Get-MgDeviceManagementDeviceConfiguration { return @() }
        }

        It 'should return an empty array' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            @($result).Count | Should -Be 0
        }

        It 'should emit a warning about no profiles' {
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockProfiles = @(
                [PSCustomObject]@{
                    DisplayName = 'Test Profile'; Id = 'tp-1'
                    CreatedDateTime = (Get-Date); LastModifiedDateTime = (Get-Date)
                    Version = 1; Description = 'Test'
                    AdditionalProperties = @{
                        '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration'
                    }
                }
            )
            Mock Get-MgDeviceManagementDeviceConfiguration { return $mockProfiles }
            $script:csvOutputPath = Join-Path $TestDrive 'config-profiles.csv'
        }

        It 'should export results to a CSV file' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported * configuration profiles to *'
        }
    }

    Context 'when Graph retrieval fails' {
        BeforeAll {
            Mock Get-MgDeviceManagementDeviceConfiguration { throw 'Access denied' }
        }

        It 'should write an error' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve configuration profiles*'
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
            Mock Get-MgDeviceManagementDeviceConfiguration { return @() }
        }

        It 'should reject empty string for OutputPath' {
            { & $script:ScriptPath -OutputPath '' } | Should -Throw
        }
    }
}
