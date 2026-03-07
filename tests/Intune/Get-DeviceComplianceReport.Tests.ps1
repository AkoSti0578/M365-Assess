BeforeAll {
    . (Join-Path $PSScriptRoot '../../Intune/Get-DeviceComplianceReport.ps1')
}

Describe 'Get-DeviceComplianceReport' {
    BeforeAll {
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when given valid input with devices returned' {
        BeforeAll {
            $mockDevices = @(
                [PSCustomObject]@{
                    DeviceName = 'LAPTOP01'; UserDisplayName = 'John Smith'
                    UserPrincipalName = 'jsmith@contoso.com'
                    OperatingSystem = 'Windows'; OsVersion = '10.0.22631.1'
                    ComplianceState = 'compliant'; IsEncrypted = $true
                    LastSyncDateTime = (Get-Date).AddHours(-2)
                    EnrolledDateTime = (Get-Date).AddMonths(-6)
                    Model = 'ThinkPad T14'; Manufacturer = 'Lenovo'
                    SerialNumber = 'ABC123'; ManagementAgent = 'mdm'
                }
                [PSCustomObject]@{
                    DeviceName = 'IPHONE01'; UserDisplayName = 'Jane Doe'
                    UserPrincipalName = 'jdoe@contoso.com'
                    OperatingSystem = 'iOS'; OsVersion = '17.3'
                    ComplianceState = 'noncompliant'; IsEncrypted = $true
                    LastSyncDateTime = (Get-Date).AddDays(-5)
                    EnrolledDateTime = (Get-Date).AddMonths(-3)
                    Model = 'iPhone 15'; Manufacturer = 'Apple'
                    SerialNumber = 'DEF456'; ManagementAgent = 'mdm'
                }
                [PSCustomObject]@{
                    DeviceName = 'PIXEL01'; UserDisplayName = 'Bob Wilson'
                    UserPrincipalName = 'bwilson@contoso.com'
                    OperatingSystem = 'Android'; OsVersion = '14'
                    ComplianceState = 'unknown'; IsEncrypted = $false
                    LastSyncDateTime = (Get-Date).AddDays(-30)
                    EnrolledDateTime = (Get-Date).AddMonths(-1)
                    Model = 'Pixel 8'; Manufacturer = 'Google'
                    SerialNumber = 'GHI789'; ManagementAgent = 'mdm'
                }
            )
            Mock Get-MgDeviceManagementManagedDevice { return $mockDevices }
        }

        It 'should return all devices when no filters are applied' {
            $result = Get-DeviceComplianceReport
            $result.Count | Should -Be 3
        }

        It 'should include expected properties' {
            $result = Get-DeviceComplianceReport
            $result[0].PSObject.Properties.Name | Should -Contain 'DeviceName'
            $result[0].PSObject.Properties.Name | Should -Contain 'ComplianceState'
            $result[0].PSObject.Properties.Name | Should -Contain 'OperatingSystem'
            $result[0].PSObject.Properties.Name | Should -Contain 'UserPrincipalName'
        }
    }

    Context 'when filtering by ComplianceState' {
        BeforeAll {
            $mockDevices = @(
                [PSCustomObject]@{
                    DeviceName = 'LAPTOP01'; UserDisplayName = 'John'
                    UserPrincipalName = 'j@test.com'; OperatingSystem = 'Windows'
                    OsVersion = '10'; ComplianceState = 'compliant'; IsEncrypted = $true
                    LastSyncDateTime = (Get-Date); EnrolledDateTime = (Get-Date)
                    Model = 'X'; Manufacturer = 'Y'; SerialNumber = '1'; ManagementAgent = 'mdm'
                }
                [PSCustomObject]@{
                    DeviceName = 'LAPTOP02'; UserDisplayName = 'Jane'
                    UserPrincipalName = 'ja@test.com'; OperatingSystem = 'Windows'
                    OsVersion = '10'; ComplianceState = 'noncompliant'; IsEncrypted = $false
                    LastSyncDateTime = (Get-Date); EnrolledDateTime = (Get-Date)
                    Model = 'X'; Manufacturer = 'Y'; SerialNumber = '2'; ManagementAgent = 'mdm'
                }
            )
            Mock Get-MgDeviceManagementManagedDevice { return $mockDevices }
        }

        It 'should return only noncompliant devices' {
            $result = Get-DeviceComplianceReport -ComplianceState NonCompliant
            $result.Count | Should -Be 1
            $result[0].DeviceName | Should -Be 'LAPTOP02'
        }

        It 'should return only compliant devices' {
            $result = Get-DeviceComplianceReport -ComplianceState Compliant
            $result.Count | Should -Be 1
            $result[0].DeviceName | Should -Be 'LAPTOP01'
        }
    }

    Context 'when filtering by Platform' {
        BeforeAll {
            $mockDevices = @(
                [PSCustomObject]@{
                    DeviceName = 'WIN01'; UserDisplayName = 'A'; UserPrincipalName = 'a@test.com'
                    OperatingSystem = 'Windows'; OsVersion = '10'; ComplianceState = 'compliant'
                    IsEncrypted = $true; LastSyncDateTime = (Get-Date); EnrolledDateTime = (Get-Date)
                    Model = 'X'; Manufacturer = 'Y'; SerialNumber = '1'; ManagementAgent = 'mdm'
                }
                [PSCustomObject]@{
                    DeviceName = 'IOS01'; UserDisplayName = 'B'; UserPrincipalName = 'b@test.com'
                    OperatingSystem = 'iOS'; OsVersion = '17'; ComplianceState = 'compliant'
                    IsEncrypted = $true; LastSyncDateTime = (Get-Date); EnrolledDateTime = (Get-Date)
                    Model = 'X'; Manufacturer = 'Apple'; SerialNumber = '2'; ManagementAgent = 'mdm'
                }
            )
            Mock Get-MgDeviceManagementManagedDevice { return $mockDevices }
        }

        It 'should filter to Windows devices only' {
            $result = Get-DeviceComplianceReport -Platform Windows
            $result.Count | Should -Be 1
            $result[0].DeviceName | Should -Be 'WIN01'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-MgDeviceManagementManagedDevice { return @(
                [PSCustomObject]@{
                    DeviceName = 'PC01'; UserDisplayName = 'A'; UserPrincipalName = 'a@test.com'
                    OperatingSystem = 'Windows'; OsVersion = '10'; ComplianceState = 'compliant'
                    IsEncrypted = $true; LastSyncDateTime = (Get-Date); EnrolledDateTime = (Get-Date)
                    Model = 'X'; Manufacturer = 'Y'; SerialNumber = '1'; ManagementAgent = 'mdm'
                }
            ) }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Get-DeviceComplianceReport -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'when not connected to Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should throw an error' {
            { Get-DeviceComplianceReport } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }
}
