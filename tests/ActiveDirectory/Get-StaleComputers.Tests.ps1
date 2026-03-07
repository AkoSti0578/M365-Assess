BeforeAll {
    . (Join-Path $PSScriptRoot '../../ActiveDirectory/Get-StaleComputers.ps1')
}

Describe 'Get-StaleComputers' {
    BeforeAll {
        # Mock the ActiveDirectory module availability and Import-Module
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } } -ParameterFilter {
            $Name -eq 'ActiveDirectory' -and $ListAvailable
        }
        Mock Import-Module { }
    }

    Context 'when given valid input with stale computers found' {
        BeforeAll {
            $mockComputers = @(
                [PSCustomObject]@{
                    Name                   = 'OLDPC01'
                    Enabled                = $true
                    OperatingSystem        = 'Windows 10 Enterprise'
                    OperatingSystemVersion = '10.0 (19045)'
                    LastLogonTimestamp      = (Get-Date).AddDays(-120).ToFileTime()
                    Description            = 'Conference room PC'
                    WhenCreated            = (Get-Date).AddYears(-2)
                    DistinguishedName      = 'CN=OLDPC01,OU=Workstations,DC=contoso,DC=com'
                }
                [PSCustomObject]@{
                    Name                   = 'OLDPC02'
                    Enabled                = $true
                    OperatingSystem        = 'Windows 11 Enterprise'
                    OperatingSystemVersion = '10.0 (22631)'
                    LastLogonTimestamp      = (Get-Date).AddDays(-200).ToFileTime()
                    Description            = 'Decommissioned laptop'
                    WhenCreated            = (Get-Date).AddYears(-3)
                    DistinguishedName      = 'CN=OLDPC02,OU=Laptops,DC=contoso,DC=com'
                }
            )
            Mock Get-ADComputer { return $mockComputers }
        }

        It 'should return stale computer objects' {
            $result = Get-StaleComputers -DaysInactive 90
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'should include expected properties' {
            $result = Get-StaleComputers -DaysInactive 90
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'LastLogon'
            $result[0].PSObject.Properties.Name | Should -Contain 'DaysSinceLogon'
            $result[0].PSObject.Properties.Name | Should -Contain 'OperatingSystem'
        }

        It 'should calculate DaysSinceLogon correctly' {
            $result = Get-StaleComputers -DaysInactive 90
            $result | ForEach-Object {
                $_.DaysSinceLogon | Should -BeGreaterThan 90
            }
        }
    }

    Context 'when using SearchBase parameter' {
        BeforeAll {
            Mock Get-ADComputer { return @() }
        }

        It 'should pass SearchBase to Get-ADComputer' {
            $null = Get-StaleComputers -DaysInactive 90 -SearchBase 'OU=Workstations,DC=contoso,DC=com'
            Should -Invoke Get-ADComputer -Times 1 -Exactly -ParameterFilter {
                $SearchBase -eq 'OU=Workstations,DC=contoso,DC=com'
            }
        }
    }

    Context 'when IncludeDisabled is not set' {
        BeforeAll {
            $mockComputers = @(
                [PSCustomObject]@{
                    Name = 'ENABLED01'; Enabled = $true
                    LastLogonTimestamp = (Get-Date).AddDays(-100).ToFileTime()
                    OperatingSystem = 'Windows 10'; OperatingSystemVersion = '10.0'
                    Description = ''; WhenCreated = (Get-Date); DistinguishedName = 'CN=ENABLED01,DC=test'
                }
                [PSCustomObject]@{
                    Name = 'DISABLED01'; Enabled = $false
                    LastLogonTimestamp = (Get-Date).AddDays(-100).ToFileTime()
                    OperatingSystem = 'Windows 10'; OperatingSystemVersion = '10.0'
                    Description = ''; WhenCreated = (Get-Date); DistinguishedName = 'CN=DISABLED01,DC=test'
                }
            )
            Mock Get-ADComputer { return $mockComputers }
        }

        It 'should exclude disabled computers by default' {
            $result = Get-StaleComputers -DaysInactive 90
            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'ENABLED01'
        }
    }

    Context 'when IncludeDisabled is set' {
        BeforeAll {
            $mockComputers = @(
                [PSCustomObject]@{
                    Name = 'ENABLED01'; Enabled = $true
                    LastLogonTimestamp = (Get-Date).AddDays(-100).ToFileTime()
                    OperatingSystem = 'Windows 10'; OperatingSystemVersion = '10.0'
                    Description = ''; WhenCreated = (Get-Date); DistinguishedName = 'CN=ENABLED01,DC=test'
                }
                [PSCustomObject]@{
                    Name = 'DISABLED01'; Enabled = $false
                    LastLogonTimestamp = (Get-Date).AddDays(-100).ToFileTime()
                    OperatingSystem = 'Windows 10'; OperatingSystemVersion = '10.0'
                    Description = ''; WhenCreated = (Get-Date); DistinguishedName = 'CN=DISABLED01,DC=test'
                }
            )
            Mock Get-ADComputer { return $mockComputers }
        }

        It 'should include disabled computers' {
            $result = Get-StaleComputers -DaysInactive 90 -IncludeDisabled
            $result.Count | Should -Be 2
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADComputer { return @(
                [PSCustomObject]@{
                    Name = 'PC01'; Enabled = $true
                    LastLogonTimestamp = (Get-Date).AddDays(-100).ToFileTime()
                    OperatingSystem = 'Windows 10'; OperatingSystemVersion = '10.0'
                    Description = ''; WhenCreated = (Get-Date); DistinguishedName = 'CN=PC01,DC=test'
                }
            ) }
            Mock Export-Csv { }
        }

        It 'should export to CSV' {
            $null = Get-StaleComputers -DaysInactive 90 -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'when ActiveDirectory module is not available' {
        BeforeAll {
            Mock Get-Module { return $null } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
        }

        It 'should throw an error' {
            { Get-StaleComputers -DaysInactive 90 } | Should -Throw '*ActiveDirectory module*'
        }
    }

    Context 'when AD query fails' {
        BeforeAll {
            Mock Get-ADComputer { throw 'Cannot contact domain controller' }
        }

        It 'should throw an error' {
            { Get-StaleComputers -DaysInactive 90 } | Should -Throw '*Failed to query Active Directory*'
        }
    }
}
