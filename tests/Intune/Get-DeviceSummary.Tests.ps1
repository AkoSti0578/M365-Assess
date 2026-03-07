BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Intune/Get-DeviceSummary.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgDeviceManagementManagedDevice { }
}

Describe 'Get-DeviceSummary' {
    BeforeAll {
        Mock Import-Module { }
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when devices are returned from Intune' {
        BeforeAll {
            $mockDevices = @(
                [PSCustomObject]@{
                    DeviceName        = 'LAPTOP01'
                    UserDisplayName   = 'John Smith'
                    UserPrincipalName = 'jsmith@contoso.com'
                    OperatingSystem   = 'Windows'
                    OsVersion         = '10.0.22631.1'
                    ComplianceState   = 'compliant'
                    ManagementAgent   = 'mdm'
                    EnrolledDateTime  = (Get-Date).AddMonths(-6)
                    LastSyncDateTime  = (Get-Date).AddHours(-2)
                    Model             = 'ThinkPad T14'
                    Manufacturer      = 'Lenovo'
                    SerialNumber      = 'SN-ABC123'
                }
                [PSCustomObject]@{
                    DeviceName        = 'IPHONE01'
                    UserDisplayName   = 'Jane Doe'
                    UserPrincipalName = 'jdoe@contoso.com'
                    OperatingSystem   = 'iOS'
                    OsVersion         = '17.3'
                    ComplianceState   = 'noncompliant'
                    ManagementAgent   = 'mdm'
                    EnrolledDateTime  = (Get-Date).AddMonths(-3)
                    LastSyncDateTime  = (Get-Date).AddDays(-5)
                    Model             = 'iPhone 15'
                    Manufacturer      = 'Apple'
                    SerialNumber      = 'SN-DEF456'
                }
                [PSCustomObject]@{
                    DeviceName        = 'ANDROID01'
                    UserDisplayName   = 'Bob Wilson'
                    UserPrincipalName = 'bwilson@contoso.com'
                    OperatingSystem   = 'Android'
                    OsVersion         = '14'
                    ComplianceState   = 'unknown'
                    ManagementAgent   = 'mdm'
                    EnrolledDateTime  = (Get-Date).AddMonths(-1)
                    LastSyncDateTime  = (Get-Date).AddDays(-30)
                    Model             = 'Pixel 8'
                    Manufacturer      = 'Google'
                    SerialNumber      = 'SN-GHI789'
                }
            )
            Mock Get-MgDeviceManagementManagedDevice { return $mockDevices }
        }

        It 'should return all devices' {
            $result = & $script:ScriptPath
            $result.Count | Should -Be 3
        }

        It 'should include all expected properties' {
            $result = & $script:ScriptPath
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'DeviceName'
            $props | Should -Contain 'UserDisplayName'
            $props | Should -Contain 'UserPrincipalName'
            $props | Should -Contain 'OperatingSystem'
            $props | Should -Contain 'OsVersion'
            $props | Should -Contain 'ComplianceState'
            $props | Should -Contain 'ManagementAgent'
            $props | Should -Contain 'EnrolledDateTime'
            $props | Should -Contain 'LastSyncDateTime'
            $props | Should -Contain 'Model'
            $props | Should -Contain 'Manufacturer'
            $props | Should -Contain 'SerialNumber'
        }

        It 'should sort results by DeviceName' {
            $result = & $script:ScriptPath
            $result[0].DeviceName | Should -Be 'ANDROID01'
            $result[1].DeviceName | Should -Be 'IPHONE01'
            $result[2].DeviceName | Should -Be 'LAPTOP01'
        }

        It 'should map device properties correctly' {
            $result = & $script:ScriptPath
            $laptop = $result | Where-Object { $_.DeviceName -eq 'LAPTOP01' }
            $laptop.UserPrincipalName | Should -Be 'jsmith@contoso.com'
            $laptop.OperatingSystem | Should -Be 'Windows'
            $laptop.ComplianceState | Should -Be 'compliant'
            $laptop.Manufacturer | Should -Be 'Lenovo'
        }
    }

    Context 'when no devices are enrolled' {
        BeforeAll {
            Mock Get-MgDeviceManagementManagedDevice { return @() }
        }

        It 'should return an empty array' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            @($result).Count | Should -Be 0 -Because 'empty device list should produce empty output'
        }

        It 'should emit a warning' {
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockDevices = @(
                [PSCustomObject]@{
                    DeviceName = 'PC01'; UserDisplayName = 'User A'
                    UserPrincipalName = 'a@contoso.com'; OperatingSystem = 'Windows'
                    OsVersion = '10.0'; ComplianceState = 'compliant'
                    ManagementAgent = 'mdm'; EnrolledDateTime = (Get-Date)
                    LastSyncDateTime = (Get-Date); Model = 'Surface Pro'
                    Manufacturer = 'Microsoft'; SerialNumber = 'SN-001'
                }
            )
            Mock Get-MgDeviceManagementManagedDevice { return $mockDevices }
            $script:csvOutputPath = Join-Path $TestDrive 'device-summary.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message string' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported * devices to *'
        }
    }

    Context 'when Graph retrieval fails' {
        BeforeAll {
            Mock Get-MgDeviceManagementManagedDevice { throw 'Insufficient privileges' }
        }

        It 'should write an error and return gracefully' {
            # Script sets $ErrorActionPreference = 'Stop' then uses Write-Error + return
            # which makes Write-Error become terminating, so we catch the throw
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve managed devices*'
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

    Context 'when Get-MgContext throws' {
        BeforeAll {
            Mock Get-MgContext { throw 'Module not loaded' }
        }

        It 'should write an error about missing connection' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'parameter validation' {
        BeforeAll {
            Mock Get-MgDeviceManagementManagedDevice { return @() }
        }

        It 'should reject empty string for OutputPath' {
            { & $script:ScriptPath -OutputPath '' } | Should -Throw
        }
    }
}
