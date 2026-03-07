BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../ActiveDirectory/Get-ADSecurityReport.ps1'

    # Stub functions for AD cmdlets not present in the session (need params for ParameterFilter)
    function Get-ADDefaultDomainPasswordPolicy { param($Identity, $Current) }
    function Get-ADFineGrainedPasswordPolicy { param($Filter) }
    function Get-ADGroupMember { param($Identity) }
    function Get-ADUser { param($Filter, $Properties) }
}

Describe 'Get-ADSecurityReport' {
    BeforeAll {
        Mock Import-Module { }
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } }
    }

    Context 'default domain password policy with strong settings' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 14
                    MaxPasswordAge               = [TimeSpan]::FromDays(90)
                    MinPasswordAge               = [TimeSpan]::FromDays(1)
                    PasswordHistoryCount         = 24
                    ComplexityEnabled             = $true
                    ReversibleEncryptionEnabled   = $false
                    LockoutThreshold             = 5
                    LockoutDuration              = [TimeSpan]::FromMinutes(30)
                    LockoutObservationWindow     = [TimeSpan]::FromMinutes(30)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }
        }

        It 'should return a PasswordPolicy record' {
            $result = & $script:ScriptPath
            $policies = @($result | Where-Object { $_.RecordType -eq 'PasswordPolicy' })
            $policies.Count | Should -BeGreaterOrEqual 1
        }

        It 'should include all policy details' {
            $result = & $script:ScriptPath
            $policy = @($result | Where-Object { $_.RecordType -eq 'PasswordPolicy' -and $_.Category -eq 'Default Domain Policy' -and $_.RiskLevel -eq 'Info' })[0]
            $policy.Detail | Should -Match 'MinPasswordLength=14'
            $policy.Detail | Should -Match 'ComplexityEnabled=True'
            $policy.Detail | Should -Match 'LockoutThreshold=5'
        }

        It 'should not flag any risks for strong policy' {
            $result = & $script:ScriptPath
            $risks = @($result | Where-Object { $_.RecordType -eq 'PasswordPolicy' -and $_.RiskLevel -in @('High', 'Critical') })
            $risks.Count | Should -Be 0
        }
    }

    Context 'default domain password policy with weak settings' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength            = 6
                    MaxPasswordAge               = [TimeSpan]::FromDays(0)
                    MinPasswordAge               = [TimeSpan]::FromDays(0)
                    PasswordHistoryCount         = 0
                    ComplexityEnabled             = $false
                    ReversibleEncryptionEnabled   = $true
                    LockoutThreshold             = 0
                    LockoutDuration              = [TimeSpan]::FromMinutes(0)
                    LockoutObservationWindow     = [TimeSpan]::FromMinutes(0)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }
        }

        It 'should flag weak minimum password length' {
            $result = & $script:ScriptPath
            $weakLen = @($result | Where-Object { $_.Name -match 'Weak minimum password length' })
            $weakLen.Count | Should -Be 1
            $weakLen[0].RiskLevel | Should -Be 'High'
        }

        It 'should flag disabled complexity' {
            $result = & $script:ScriptPath
            $noComplex = @($result | Where-Object { $_.Name -match 'complexity disabled' })
            $noComplex.Count | Should -Be 1
            $noComplex[0].RiskLevel | Should -Be 'High'
        }

        It 'should flag no account lockout' {
            $result = & $script:ScriptPath
            $noLockout = @($result | Where-Object { $_.Name -match 'No account lockout' })
            $noLockout.Count | Should -Be 1
            $noLockout[0].RiskLevel | Should -Be 'High'
        }

        It 'should flag reversible encryption' {
            $result = & $script:ScriptPath
            $reversible = @($result | Where-Object { $_.Name -match 'Reversible encryption enabled' })
            $reversible.Count | Should -Be 1
            $reversible[0].RiskLevel | Should -Be 'Critical'
        }
    }

    Context 'fine-grained password policies' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength = 14; MaxPasswordAge = [TimeSpan]::FromDays(90)
                    MinPasswordAge = [TimeSpan]::FromDays(1); PasswordHistoryCount = 24
                    ComplexityEnabled = $true; ReversibleEncryptionEnabled = $false
                    LockoutThreshold = 5; LockoutDuration = [TimeSpan]::FromMinutes(30)
                    LockoutObservationWindow = [TimeSpan]::FromMinutes(30)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy {
                return @(
                    [PSCustomObject]@{
                        Name                 = 'Service Accounts Policy'
                        Precedence           = 10
                        MinPasswordLength    = 20
                        MaxPasswordAge       = [TimeSpan]::FromDays(365)
                        PasswordHistoryCount = 12
                        ComplexityEnabled    = $true
                        LockoutThreshold     = 3
                        AppliesTo            = @('CN=Service Accounts,OU=Groups,DC=contoso,DC=com')
                    }
                )
            }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }
        }

        It 'should return fine-grained policy records' {
            $result = & $script:ScriptPath
            $fgp = @($result | Where-Object { $_.Category -eq 'Fine-Grained Policy' })
            $fgp.Count | Should -Be 1
            $fgp[0].Name | Should -Be 'Service Accounts Policy'
        }

        It 'should include precedence and AppliesTo in detail' {
            $result = & $script:ScriptPath
            $fgp = @($result | Where-Object { $_.Category -eq 'Fine-Grained Policy' })[0]
            $fgp.Value | Should -Match 'Precedence=10'
            $fgp.Detail | Should -Match 'AppliesTo=Service Accounts'
        }
    }

    Context 'privileged group membership' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength = 14; MaxPasswordAge = [TimeSpan]::FromDays(90)
                    MinPasswordAge = [TimeSpan]::FromDays(1); PasswordHistoryCount = 24
                    ComplexityEnabled = $true; ReversibleEncryptionEnabled = $false
                    LockoutThreshold = 5; LockoutDuration = [TimeSpan]::FromMinutes(30)
                    LockoutObservationWindow = [TimeSpan]::FromMinutes(30)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy { return @() }

            Mock Get-ADGroupMember {
                return @(
                    [PSCustomObject]@{ SamAccountName = 'admin1'; objectClass = 'user' }
                    [PSCustomObject]@{ SamAccountName = 'admin2'; objectClass = 'user' }
                )
            } -ParameterFilter { $Identity -eq 'Domain Admins' }

            Mock Get-ADGroupMember {
                return @()
            } -ParameterFilter { $Identity -ne 'Domain Admins' }

            Mock Get-ADUser { return @() }
        }

        It 'should return privileged group records' {
            $result = & $script:ScriptPath
            $groups = @($result | Where-Object { $_.RecordType -eq 'PrivilegedGroup' })
            $groups.Count | Should -BeGreaterOrEqual 1
        }

        It 'should list Domain Admins members' {
            $result = & $script:ScriptPath
            $da = @($result | Where-Object { $_.RecordType -eq 'PrivilegedGroup' -and $_.Name -eq 'Domain Admins' })[0]
            $da.Value | Should -Be '2 members'
            $da.Detail | Should -Match 'admin1'
            $da.Detail | Should -Match 'admin2'
        }

        It 'should report empty groups with 0 members' {
            $result = & $script:ScriptPath
            $empty = @($result | Where-Object { $_.RecordType -eq 'PrivilegedGroup' -and $_.Value -eq '0 members' })
            $empty.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'privileged group with excessive membership' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength = 14; MaxPasswordAge = [TimeSpan]::FromDays(90)
                    MinPasswordAge = [TimeSpan]::FromDays(1); PasswordHistoryCount = 24
                    ComplexityEnabled = $true; ReversibleEncryptionEnabled = $false
                    LockoutThreshold = 5; LockoutDuration = [TimeSpan]::FromMinutes(30)
                    LockoutObservationWindow = [TimeSpan]::FromMinutes(30)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy { return @() }

            $manyAdmins = 1..8 | ForEach-Object { [PSCustomObject]@{ SamAccountName = "admin$_"; objectClass = 'user' } }
            Mock Get-ADGroupMember { return $manyAdmins } -ParameterFilter { $Identity -eq 'Domain Admins' }
            Mock Get-ADGroupMember { return @() } -ParameterFilter { $Identity -ne 'Domain Admins' }
            Mock Get-ADUser { return @() }
        }

        It 'should flag Warning for groups with more than 5 members' {
            $result = & $script:ScriptPath
            $da = @($result | Where-Object { $_.RecordType -eq 'PrivilegedGroup' -and $_.Name -eq 'Domain Admins' })[0]
            $da.RiskLevel | Should -Be 'Warning'
        }
    }

    Context 'flagged user accounts' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength = 14; MaxPasswordAge = [TimeSpan]::FromDays(90)
                    MinPasswordAge = [TimeSpan]::FromDays(1); PasswordHistoryCount = 24
                    ComplexityEnabled = $true; ReversibleEncryptionEnabled = $false
                    LockoutThreshold = 5; LockoutDuration = [TimeSpan]::FromMinutes(30)
                    LockoutObservationWindow = [TimeSpan]::FromMinutes(30)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }

            # PasswordNeverExpires accounts
            Mock Get-ADUser {
                return @(
                    [PSCustomObject]@{ SamAccountName = 'svc-backup'; PasswordNeverExpires = $true }
                    [PSCustomObject]@{ SamAccountName = 'svc-sql'; PasswordNeverExpires = $true }
                )
            } -ParameterFilter { "$Filter" -match 'PasswordNeverExpires' }

            # PasswordNotRequired accounts
            Mock Get-ADUser {
                return @(
                    [PSCustomObject]@{ SamAccountName = 'guest-test'; PasswordNotRequired = $true }
                )
            } -ParameterFilter { "$Filter" -match 'PasswordNotRequired' }

            # Reversible encryption accounts
            Mock Get-ADUser {
                return @()
            } -ParameterFilter { "$Filter" -match 'AllowReversiblePasswordEncryption' }
        }

        It 'should flag PasswordNeverExpires accounts' {
            $result = & $script:ScriptPath
            $neverExpires = @($result | Where-Object { $_.Category -eq 'Password Never Expires' })
            $neverExpires.Count | Should -Be 1
            $neverExpires[0].Value | Should -Be '2 accounts'
            $neverExpires[0].Detail | Should -Match 'svc-backup'
        }

        It 'should flag PasswordNotRequired accounts as Critical' {
            $result = & $script:ScriptPath
            $noPass = @($result | Where-Object { $_.Category -eq 'Password Not Required' })
            $noPass.Count | Should -Be 1
            $noPass[0].RiskLevel | Should -Be 'Critical'
            $noPass[0].Detail | Should -Match 'guest-test'
        }

        It 'should not include reversible encryption when no accounts match' {
            $result = & $script:ScriptPath
            $reversible = @($result | Where-Object { $_.Category -eq 'Reversible Encryption' })
            $reversible.Count | Should -Be 0
        }
    }

    Context 'when ActiveDirectory module is not available' {
        BeforeAll {
            Mock Get-Module { return $null }
        }

        It 'should throw an error about missing module' {
            { & $script:ScriptPath } | Should -Throw '*ActiveDirectory module*'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDefaultDomainPasswordPolicy {
                return [PSCustomObject]@{
                    MinPasswordLength = 14; MaxPasswordAge = [TimeSpan]::FromDays(90)
                    MinPasswordAge = [TimeSpan]::FromDays(1); PasswordHistoryCount = 24
                    ComplexityEnabled = $true; ReversibleEncryptionEnabled = $false
                    LockoutThreshold = 5; LockoutDuration = [TimeSpan]::FromMinutes(30)
                    LockoutObservationWindow = [TimeSpan]::FromMinutes(30)
                }
            }
            Mock Get-ADFineGrainedPasswordPolicy { return @() }
            Mock Get-ADGroupMember { return @() }
            Mock Get-ADUser { return @() }
        }

        It 'should export results to CSV' {
            $csvPath = Join-Path $TestDrive 'security.csv'
            & $script:ScriptPath -OutputPath $csvPath
            Test-Path -Path $csvPath | Should -Be $true
        }

        It 'should return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'security2.csv'
            $result = & $script:ScriptPath -OutputPath $csvPath
            $result | Should -Match 'Exported.*security records'
        }
    }
}
