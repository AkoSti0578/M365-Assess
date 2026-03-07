BeforeAll {
    . (Join-Path $PSScriptRoot '../../Windows/Get-InstalledSoftware.ps1')
}

Describe 'Get-InstalledSoftware' {
    Context 'when querying the local computer' {
        BeforeAll {
            Mock Get-ItemProperty {
                @(
                    [PSCustomObject]@{
                        DisplayName = 'Microsoft Visual Studio Code'
                        DisplayVersion = '1.85.0'
                        Publisher = 'Microsoft Corporation'
                        InstallDate = '20240115'
                        InstallLocation = 'C:\Program Files\VS Code'
                        UninstallString = 'C:\Program Files\VS Code\uninstall.exe'
                    }
                    [PSCustomObject]@{
                        DisplayName = 'Git for Windows'
                        DisplayVersion = '2.43.0'
                        Publisher = 'The Git Development Community'
                        InstallDate = '20240110'
                        InstallLocation = 'C:\Program Files\Git'
                        UninstallString = 'C:\Program Files\Git\uninstall.exe'
                    }
                    [PSCustomObject]@{
                        DisplayName = $null
                        DisplayVersion = '1.0'
                        Publisher = 'Unknown'
                        InstallDate = $null
                        InstallLocation = $null
                        UninstallString = $null
                    }
                )
            }
        }

        It 'should return installed software entries' {
            $result = Get-InstalledSoftware
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should exclude entries without DisplayName' {
            $result = Get-InstalledSoftware
            $result | Where-Object { $null -eq $_.DisplayName } | Should -BeNullOrEmpty
        }

        It 'should include expected properties' {
            $result = Get-InstalledSoftware
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'DisplayName'
            $result[0].PSObject.Properties.Name | Should -Contain 'DisplayVersion'
            $result[0].PSObject.Properties.Name | Should -Contain 'Publisher'
            $result[0].PSObject.Properties.Name | Should -Contain 'Architecture'
        }

        It 'should include architecture information' {
            $result = Get-InstalledSoftware
            $result[0].Architecture | Should -BeIn @('32-bit', '64-bit')
        }
    }

    Context 'when querying a remote computer' {
        BeforeAll {
            Mock Invoke-Command {
                @(
                    [PSCustomObject]@{
                        DisplayName = 'Remote App'
                        DisplayVersion = '2.0'
                        Publisher = 'Test Corp'
                        InstallDate = '20240101'
                        InstallLocation = 'C:\Program Files\RemoteApp'
                        UninstallString = 'msiexec /x {guid}'
                        Architecture = '64-bit'
                    }
                )
            }
        }

        It 'should use Invoke-Command for remote queries' {
            $result = Get-InstalledSoftware -ComputerName 'REMOTE01'
            Should -Invoke Invoke-Command -Times 1 -Exactly
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should set ComputerName on remote results' {
            $result = Get-InstalledSoftware -ComputerName 'REMOTE01'
            $result[0].ComputerName | Should -Be 'REMOTE01'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ItemProperty {
                @([PSCustomObject]@{
                    DisplayName = 'Test App'; DisplayVersion = '1.0'
                    Publisher = 'Test'; InstallDate = '20240101'
                    InstallLocation = 'C:\test'; UninstallString = 'test'
                })
            }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Get-InstalledSoftware -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'when remote computer is unreachable' {
        BeforeAll {
            Mock Invoke-Command { throw 'WinRM cannot complete the operation' }
        }

        It 'should return an error entry instead of throwing' {
            $result = Get-InstalledSoftware -ComputerName 'UNREACHABLE01'
            $result | Should -Not -BeNullOrEmpty
            $result[0].DisplayName | Should -Match 'ERROR'
        }
    }

    Context 'pipeline input' {
        BeforeAll {
            Mock Invoke-Command {
                @([PSCustomObject]@{
                    DisplayName = 'App'; DisplayVersion = '1.0'
                    Publisher = 'P'; InstallDate = ''; InstallLocation = ''
                    UninstallString = ''; Architecture = '64-bit'
                })
            }
        }

        It 'should accept pipeline input' {
            $result = @('SERVER01', 'SERVER02') | Get-InstalledSoftware
            Should -Invoke Invoke-Command -Times 2 -Exactly
        }
    }
}
