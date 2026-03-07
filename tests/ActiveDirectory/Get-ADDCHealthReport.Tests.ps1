BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../ActiveDirectory/Get-ADDCHealthReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-ADDomainController { param($Filter, $Identity) }

    # Pre-define Invoke-Dcdiag so the script skips its own definition (conditional pattern)
    function Invoke-Dcdiag {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$Target,
            [Parameter()]
            [string[]]$Tests
        )
    }
}

Describe 'Get-ADDCHealthReport' {
    BeforeAll {
        # Mock the ActiveDirectory module availability and Import-Module
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } } -ParameterFilter {
            $Name -eq 'ActiveDirectory' -and $ListAvailable
        }
        Mock Import-Module { }
        Mock Write-Warning { }
    }

    Context 'happy path with dcdiag passing all tests' {
        BeforeAll {
            # NOTE: Mock data must be inline, not via $script: variables,
            # because $script: scope does not resolve inside mock scriptblocks
            # when invoked by a child script (& $ScriptPath).
            Mock Get-ADDomainController {
                return @(
                    [PSCustomObject]@{
                        HostName             = 'DC01.contoso.com'
                        Site                 = 'Default-First-Site-Name'
                        IPv4Address          = '10.0.0.10'
                        OperatingSystem      = 'Windows Server 2022 Datacenter'
                        IsGlobalCatalog      = $true
                        IsReadOnly           = $false
                        OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                    }
                    [PSCustomObject]@{
                        HostName             = 'DC02.contoso.com'
                        Site                 = 'Branch-Office'
                        IPv4Address          = '10.0.1.10'
                        OperatingSystem      = 'Windows Server 2019 Standard'
                        IsGlobalCatalog      = $true
                        IsReadOnly           = $false
                        OperationMasterRoles = @()
                    }
                )
            }

            Mock Invoke-Dcdiag {
                return @(
                    'Directory Server Diagnosis'
                    'Performing initial setup:'
                    '   Trying to find home server...'
                    '   Home Server = DC01'
                    '   * Identified AD Forest.'
                    '   Done gathering initial info.'
                    ''
                    'Testing server: Default-First-Site-Name\DC01'
                    '   Starting test: Connectivity'
                    '      ......................... DC01 passed test Connectivity'
                    '   Starting test: Advertising'
                    '      ......................... DC01 passed test Advertising'
                    '   Starting test: Services'
                    '      ......................... DC01 passed test Services'
                )
            }
        }

        It 'should return results for all DCs' {
            $result = & $script:ScriptPath
            $dcNames = @($result | ForEach-Object { $_.DomainController } | Sort-Object -Unique)
            $dcNames | Should -Contain 'DC01.contoso.com'
            $dcNames | Should -Contain 'DC02.contoso.com'
        }

        It 'should include expected properties' {
            $result = & $script:ScriptPath
            $first = $result[0]
            $first.PSObject.Properties.Name | Should -Contain 'DomainController'
            $first.PSObject.Properties.Name | Should -Contain 'Site'
            $first.PSObject.Properties.Name | Should -Contain 'IPv4Address'
            $first.PSObject.Properties.Name | Should -Contain 'OperatingSystem'
            $first.PSObject.Properties.Name | Should -Contain 'IsGlobalCatalog'
            $first.PSObject.Properties.Name | Should -Contain 'DcdiagTest'
            $first.PSObject.Properties.Name | Should -Contain 'DcdiagResult'
        }

        It 'should have Passed results for dcdiag tests' {
            $result = & $script:ScriptPath
            $dc1Tests = @($result | Where-Object { $_.DomainController -eq 'DC01.contoso.com' })
            $dc1Tests.Count | Should -BeGreaterOrEqual 3
            $dc1Tests | ForEach-Object { $_.DcdiagResult | Should -Be 'Passed' }
        }

        It 'should populate FSMO roles for DC01' {
            $result = & $script:ScriptPath
            $dc1 = $result | Where-Object { $_.DomainController -eq 'DC01.contoso.com' } | Select-Object -First 1
            $dc1.FSMORoles | Should -Match 'PDCEmulator'
            $dc1.FSMORoles | Should -Match 'RIDMaster'
        }

        It 'should have empty FSMO roles for DC02' {
            $result = & $script:ScriptPath
            $dc2 = $result | Where-Object { $_.DomainController -eq 'DC02.contoso.com' } | Select-Object -First 1
            $dc2.FSMORoles | Should -BeNullOrEmpty
        }
    }

    Context 'when dcdiag reports failures' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName = 'DC01.contoso.com'; Site = 'Default-First-Site-Name'
                    IPv4Address = '10.0.0.10'; OperatingSystem = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog = $true; IsReadOnly = $false
                    OperationMasterRoles = @('PDCEmulator')
                })
            }

            Mock Invoke-Dcdiag {
                return @(
                    'Directory Server Diagnosis'
                    'Testing server: Default-First-Site-Name\DC01'
                    '   Starting test: Connectivity'
                    '      ......................... DC01 passed test Connectivity'
                    '   Starting test: Services'
                    '      ......................... DC01 failed test Services'
                    '   Starting test: Advertising'
                    '      ......................... DC01 passed test Advertising'
                )
            }
        }

        It 'should report Failed for the failed test' {
            $result = & $script:ScriptPath
            $failedTest = $result | Where-Object { $_.DcdiagTest -eq 'Services' }
            $failedTest | Should -Not -BeNullOrEmpty
            $failedTest.DcdiagResult | Should -Be 'Failed'
        }

        It 'should report Passed for passing tests' {
            $result = & $script:ScriptPath
            $passedTest = $result | Where-Object { $_.DcdiagTest -eq 'Connectivity' }
            $passedTest.DcdiagResult | Should -Be 'Passed'
        }

        It 'should include failure details' {
            $result = & $script:ScriptPath
            $failedTest = $result | Where-Object { $_.DcdiagTest -eq 'Services' }
            $failedTest.DcdiagDetails | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when dcdiag.exe is not available (Invoke-Dcdiag throws)' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName = 'DC01.contoso.com'; Site = 'Default-First-Site-Name'
                    IPv4Address = '10.0.0.10'; OperatingSystem = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog = $true; IsReadOnly = $false
                    OperationMasterRoles = @('PDCEmulator')
                })
            }
            Mock Invoke-Dcdiag { throw 'dcdiag.exe is not available on this machine.' }
        }

        It 'should still return DC inventory data' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $result[0].DomainController | Should -Be 'DC01.contoso.com'
            $result[0].OperatingSystem | Should -Be 'Windows Server 2022 Datacenter'
        }

        It 'should mark dcdiag as Skipped' {
            $result = & $script:ScriptPath 3>$null
            $result[0].DcdiagResult | Should -Be 'Skipped'
        }

        It 'should include unavailable reason in details' {
            $result = & $script:ScriptPath 3>$null
            $result[0].DcdiagDetails | Should -Match 'dcdiag'
        }
    }

    Context 'when -SkipDcdiag is specified' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @(
                    [PSCustomObject]@{
                        HostName = 'DC01.contoso.com'; Site = 'Default-First-Site-Name'
                        IPv4Address = '10.0.0.10'; OperatingSystem = 'Windows Server 2022 Datacenter'
                        IsGlobalCatalog = $true; IsReadOnly = $false
                        OperationMasterRoles = @('PDCEmulator', 'RIDMaster')
                    }
                    [PSCustomObject]@{
                        HostName = 'DC02.contoso.com'; Site = 'Branch-Office'
                        IPv4Address = '10.0.1.10'; OperatingSystem = 'Windows Server 2019 Standard'
                        IsGlobalCatalog = $true; IsReadOnly = $false
                        OperationMasterRoles = @()
                    }
                )
            }
            Mock Invoke-Dcdiag { throw 'Should not be called' }
        }

        It 'should not invoke dcdiag' {
            $null = & $script:ScriptPath -SkipDcdiag
            Should -Invoke Invoke-Dcdiag -Times 0
        }

        It 'should return one row per DC with Skipped status' {
            $result = & $script:ScriptPath -SkipDcdiag
            $result.Count | Should -Be 2
            $result | ForEach-Object { $_.DcdiagResult | Should -Be 'Skipped' }
        }

        It 'should still populate DC inventory properties' {
            $result = & $script:ScriptPath -SkipDcdiag
            $dc1 = $result | Where-Object { $_.DomainController -eq 'DC01.contoso.com' }
            $dc1.Site | Should -Be 'Default-First-Site-Name'
            $dc1.IPv4Address | Should -Be '10.0.0.10'
            $dc1.IsGlobalCatalog | Should -Be $true
        }
    }

    Context 'when specific DomainController parameter is provided' {
        BeforeAll {
            Mock Get-ADDomainController {
                return [PSCustomObject]@{
                    HostName = 'DC01.contoso.com'; Site = 'Default-First-Site-Name'
                    IPv4Address = '10.0.0.10'; OperatingSystem = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog = $true; IsReadOnly = $false
                    OperationMasterRoles = @('PDCEmulator')
                }
            }
            Mock Invoke-Dcdiag {
                return @(
                    '      ......................... DC01 passed test Connectivity'
                )
            }
        }

        It 'should query only the specified DC' {
            $null = & $script:ScriptPath -DomainController 'DC01'
            Should -Invoke Get-ADDomainController -Times 1 -Exactly
        }

        It 'should return results only for the specified DC' {
            $result = & $script:ScriptPath -DomainController 'DC01'
            $dcNames = @($result | ForEach-Object { $_.DomainController } | Sort-Object -Unique)
            $dcNames.Count | Should -Be 1
            $dcNames[0] | Should -Be 'DC01.contoso.com'
        }
    }

    Context 'when ActiveDirectory module is not available' {
        BeforeAll {
            Mock Get-Module { return $null } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
        }

        It 'should throw an error about missing module' {
            { & $script:ScriptPath } | Should -Throw '*ActiveDirectory module*'
        }
    }

    Context 'when no domain controllers are found' {
        BeforeAll {
            Mock Get-ADDomainController { return @() }
        }

        It 'should throw an error about no DCs found' {
            { & $script:ScriptPath } | Should -Throw '*No domain controllers found*'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDomainController {
                return @([PSCustomObject]@{
                    HostName = 'DC01.contoso.com'; Site = 'Default-First-Site-Name'
                    IPv4Address = '10.0.0.10'; OperatingSystem = 'Windows Server 2022 Datacenter'
                    IsGlobalCatalog = $true; IsReadOnly = $false
                    OperationMasterRoles = @()
                })
            }
            Mock Invoke-Dcdiag {
                return @(
                    '      ......................... DC01 passed test Connectivity'
                )
            }
            $script:csvOutputPath = Join-Path $TestDrive 'test-dc-health.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported.*DC health records'
        }
    }
}
