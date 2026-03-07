BeforeAll {
    . (Join-Path $PSScriptRoot '../../Security/Get-LocalAdmins.ps1')
}

Describe 'Get-LocalAdmins' {
    Context 'when querying the local computer' {
        BeforeAll {
            Mock Get-LocalGroupMember {
                @(
                    [PSCustomObject]@{
                        Name = 'CONTOSO\DomainAdmins'
                        ObjectClass = 'Group'
                        PrincipalSource = 'ActiveDirectory'
                    }
                    [PSCustomObject]@{
                        Name = 'COMPUTER\Administrator'
                        ObjectClass = 'User'
                        PrincipalSource = 'Local'
                    }
                )
            }
        }

        It 'should return local admin members' {
            $result = Get-LocalAdmins
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'should include expected properties' {
            $result = Get-LocalAdmins
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'ObjectClass'
            $result[0].PSObject.Properties.Name | Should -Contain 'PrincipalSource'
        }

        It 'should use Get-LocalGroupMember for local queries' {
            $null = Get-LocalAdmins
            Should -Invoke Get-LocalGroupMember -Times 1 -Exactly -ParameterFilter {
                $Group -eq 'Administrators'
            }
        }
    }

    Context 'when querying a remote computer' {
        BeforeAll {
            Mock Get-CimInstance {
                param($ClassName, $Filter, $Query)
                if ($ClassName -eq 'Win32_Group') {
                    return [PSCustomObject]@{ Name = 'Administrators' }
                }
                if ($Query) {
                    return @(
                        [PSCustomObject]@{
                            PartComponent = [PSCustomObject]@{
                                Domain = 'CONTOSO'
                                Name = 'RemoteAdmin'
                                CimClass = [PSCustomObject]@{ CimClassName = 'Win32_UserAccount' }
                            }
                        }
                    )
                }
            }
            Mock New-CimSession { return [PSCustomObject]@{ Id = 1 } }
            Mock Remove-CimSession { }
        }

        It 'should use CIM for remote queries' {
            $result = Get-LocalAdmins -ComputerName 'REMOTE01'
            $result | Should -Not -BeNullOrEmpty
            Should -Invoke New-CimSession -Times 1 -Exactly
        }

        It 'should clean up CIM session' {
            $null = Get-LocalAdmins -ComputerName 'REMOTE01'
            Should -Invoke Remove-CimSession -Times 1 -Exactly
        }
    }

    Context 'when remote computer is unreachable' {
        BeforeAll {
            Mock New-CimSession { throw 'WinRM cannot connect' }
            Mock Get-CimInstance { throw 'WinRM cannot connect' }
        }

        It 'should return an error entry' {
            $result = Get-LocalAdmins -ComputerName 'BADHOST'
            $result | Should -Not -BeNullOrEmpty
            $result[0].ObjectClass | Should -Be 'Error'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-LocalGroupMember {
                @([PSCustomObject]@{
                    Name = 'COMPUTER\Admin'
                    ObjectClass = 'User'
                    PrincipalSource = 'Local'
                })
            }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Get-LocalAdmins -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'pipeline input' {
        BeforeAll {
            Mock New-CimSession { return [PSCustomObject]@{ Id = 1 } }
            Mock Remove-CimSession { }
            Mock Get-CimInstance {
                param($ClassName, $Filter, $Query)
                if ($ClassName -eq 'Win32_Group') {
                    return [PSCustomObject]@{ Name = 'Administrators' }
                }
                if ($Query) {
                    return @(
                        [PSCustomObject]@{
                            PartComponent = [PSCustomObject]@{
                                Domain = 'TEST'
                                Name = 'Admin'
                                CimClass = [PSCustomObject]@{ CimClassName = 'Win32_UserAccount' }
                            }
                        }
                    )
                }
            }
        }

        It 'should accept pipeline input' {
            $result = @('SERVER01', 'SERVER02') | Get-LocalAdmins
            $result.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context 'when using Credential parameter for remote queries' {
        BeforeAll {
            $testCred = [PSCredential]::new('admin', (ConvertTo-SecureString 'pass' -AsPlainText -Force))
            Mock New-CimSession { return [PSCustomObject]@{ Id = 1 } }
            Mock Remove-CimSession { }
            Mock Get-CimInstance {
                param($ClassName, $Filter, $Query)
                if ($ClassName -eq 'Win32_Group') {
                    return [PSCustomObject]@{ Name = 'Administrators' }
                }
                if ($Query) { return @() }
            }
        }

        It 'should pass Credential to New-CimSession' {
            $null = Get-LocalAdmins -ComputerName 'REMOTE01' -Credential $testCred
            Should -Invoke New-CimSession -Times 1 -Exactly -ParameterFilter {
                $Credential -eq $testCred
            }
        }
    }
}
