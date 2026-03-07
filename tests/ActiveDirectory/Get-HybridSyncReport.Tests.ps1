BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../ActiveDirectory/Get-HybridSyncReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgOrganization { }
    function Get-ADDomain { }
    function Get-ADForest { }
}

Describe 'Get-HybridSyncReport' {
    BeforeAll {
        Mock Import-Module { }
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when hybrid sync is enabled with password hash sync' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName                       = 'Contoso Ltd'
                    Id                                = 'org-001'
                    OnPremisesSyncEnabled              = $true
                    OnPremisesLastSyncDateTime         = (Get-Date).AddMinutes(-30)
                    OnPremisesLastPasswordSyncDateTime = (Get-Date).AddMinutes(-30)
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
        }

        It 'should return a report object' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
            @($result).Count | Should -Be 1
        }

        It 'should include all expected properties' {
            $result = & $script:ScriptPath
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'TenantDisplayName'
            $props | Should -Contain 'TenantId'
            $props | Should -Contain 'OnPremisesSyncEnabled'
            $props | Should -Contain 'LastDirSyncTime'
            $props | Should -Contain 'DirSyncConfigured'
            $props | Should -Contain 'PasswordHashSyncEnabled'
            $props | Should -Contain 'LastPasswordSyncTime'
            $props | Should -Contain 'SyncType'
            $props | Should -Contain 'OnPremDomainName'
            $props | Should -Contain 'OnPremForestName'
        }

        It 'should report OnPremisesSyncEnabled as true' {
            $result = & $script:ScriptPath
            $result[0].OnPremisesSyncEnabled | Should -BeTrue
        }

        It 'should report DirSyncConfigured as true' {
            $result = & $script:ScriptPath
            $result[0].DirSyncConfigured | Should -BeTrue
        }

        It 'should detect Password Hash Sync in SyncType' {
            $result = & $script:ScriptPath
            $result[0].SyncType | Should -BeLike '*Password Hash Sync*'
        }

        It 'should report PasswordHashSyncEnabled as true' {
            $result = & $script:ScriptPath
            $result[0].PasswordHashSyncEnabled | Should -BeTrue
        }

        It 'should report TenantDisplayName' {
            $result = & $script:ScriptPath
            $result[0].TenantDisplayName | Should -Be 'Contoso Ltd'
        }

        It 'should show N/A for on-prem domain when -IncludeOnPremAD is not specified' {
            $result = & $script:ScriptPath
            $result[0].OnPremDomainName | Should -Be 'N/A'
            $result[0].OnPremForestName | Should -Be 'N/A'
        }
    }

    Context 'when hybrid sync is enabled without password hash sync' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName                       = 'Fabrikam Inc'
                    Id                                = 'org-002'
                    OnPremisesSyncEnabled              = $true
                    OnPremisesLastSyncDateTime         = (Get-Date).AddHours(-1)
                    OnPremisesLastPasswordSyncDateTime = $null
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
        }

        It 'should report SyncType as Entra Connect or Cloud Sync' {
            $result = & $script:ScriptPath
            $result[0].SyncType | Should -Be 'Entra Connect or Cloud Sync'
        }

        It 'should report PasswordHashSyncEnabled as false' {
            $result = & $script:ScriptPath
            $result[0].PasswordHashSyncEnabled | Should -BeFalse
        }
    }

    Context 'when no hybrid sync is configured (cloud-only)' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName                       = 'CloudOnly Corp'
                    Id                                = 'org-003'
                    OnPremisesSyncEnabled              = $false
                    OnPremisesLastSyncDateTime         = $null
                    OnPremisesLastPasswordSyncDateTime = $null
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
        }

        It 'should report SyncType as cloud-only' {
            $result = & $script:ScriptPath
            $result[0].SyncType | Should -BeLike '*Cloud-only*'
        }

        It 'should report OnPremisesSyncEnabled as false' {
            $result = & $script:ScriptPath
            $result[0].OnPremisesSyncEnabled | Should -BeFalse
        }

        It 'should report DirSyncConfigured as false' {
            $result = & $script:ScriptPath
            $result[0].DirSyncConfigured | Should -BeFalse
        }

        It 'should report PasswordHashSyncEnabled as false' {
            $result = & $script:ScriptPath
            $result[0].PasswordHashSyncEnabled | Should -BeFalse
        }

        It 'should have null LastDirSyncTime' {
            $result = & $script:ScriptPath
            $result[0].LastDirSyncTime | Should -BeNullOrEmpty
        }
    }

    Context 'when -IncludeOnPremAD is specified and AD module is available' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName                       = 'Contoso Ltd'
                    Id                                = 'org-001'
                    OnPremisesSyncEnabled              = $true
                    OnPremisesLastSyncDateTime         = (Get-Date).AddMinutes(-30)
                    OnPremisesLastPasswordSyncDateTime = (Get-Date).AddMinutes(-30)
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
            Mock Get-Module { return @{ Name = 'ActiveDirectory' } } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
            Mock Get-ADDomain {
                return [PSCustomObject]@{ DNSRoot = 'contoso.local' }
            }
            Mock Get-ADForest {
                return [PSCustomObject]@{ Name = 'contoso.local' }
            }
        }

        It 'should populate OnPremDomainName from Get-ADDomain' {
            $result = & $script:ScriptPath -IncludeOnPremAD
            $result[0].OnPremDomainName | Should -Be 'contoso.local'
        }

        It 'should populate OnPremForestName from Get-ADForest' {
            $result = & $script:ScriptPath -IncludeOnPremAD
            $result[0].OnPremForestName | Should -Be 'contoso.local'
        }

        It 'should invoke Get-ADDomain' {
            $null = & $script:ScriptPath -IncludeOnPremAD
            Should -Invoke Get-ADDomain -Times 1 -Exactly
        }

        It 'should invoke Get-ADForest' {
            $null = & $script:ScriptPath -IncludeOnPremAD
            Should -Invoke Get-ADForest -Times 1 -Exactly
        }
    }

    Context 'when -IncludeOnPremAD is specified but AD module is not available' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName                       = 'Contoso Ltd'
                    Id                                = 'org-001'
                    OnPremisesSyncEnabled              = $true
                    OnPremisesLastSyncDateTime         = (Get-Date).AddMinutes(-30)
                    OnPremisesLastPasswordSyncDateTime = $null
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
            Mock Get-Module { return $null } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
        }

        It 'should emit a warning about missing AD module' {
            $allOutput = & $script:ScriptPath -IncludeOnPremAD 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -BeLike '*ActiveDirectory*module*'
        }

        It 'should still return a report with N/A for on-prem fields' {
            $result = & $script:ScriptPath -IncludeOnPremAD 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result[0].OnPremDomainName | Should -Be 'N/A'
            $result[0].OnPremForestName | Should -Be 'N/A'
        }
    }

    Context 'when -IncludeOnPremAD is specified and Get-ADDomain fails' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName                       = 'Contoso Ltd'
                    Id                                = 'org-001'
                    OnPremisesSyncEnabled              = $true
                    OnPremisesLastSyncDateTime         = (Get-Date).AddMinutes(-30)
                    OnPremisesLastPasswordSyncDateTime = $null
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
            Mock Get-Module { return @{ Name = 'ActiveDirectory' } } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
            Mock Get-ADDomain { throw 'Cannot contact domain controller' }
            Mock Get-ADForest { return [PSCustomObject]@{ Name = 'contoso.local' } }
        }

        It 'should emit a warning about AD domain query failure' {
            $allOutput = & $script:ScriptPath -IncludeOnPremAD 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -BeLike '*Failed to query on-premises AD domain*'
        }

        It 'should still return forest info when only domain query fails' {
            $result = & $script:ScriptPath -IncludeOnPremAD 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result[0].OnPremDomainName | Should -Be 'N/A'
            $result[0].OnPremForestName | Should -Be 'contoso.local'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName = 'Test Org'; Id = 'org-t1'
                    OnPremisesSyncEnabled = $false
                    OnPremisesLastSyncDateTime = $null
                    OnPremisesLastPasswordSyncDateTime = $null
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
            $script:csvOutputPath = Join-Path $TestDrive 'hybrid-sync.csv'
        }

        It 'should export results to a CSV file' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported hybrid sync report*'
        }
    }

    Context 'when Get-MgOrganization fails' {
        BeforeAll {
            Mock Get-MgOrganization { throw 'Insufficient permissions' }
        }

        It 'should write an error' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve organization details*'
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

    Context 'when multiple organizations are returned' {
        BeforeAll {
            $mockOrgs = @(
                [PSCustomObject]@{
                    DisplayName = 'Org A'; Id = 'org-a'
                    OnPremisesSyncEnabled = $true
                    OnPremisesLastSyncDateTime = (Get-Date)
                    OnPremisesLastPasswordSyncDateTime = (Get-Date)
                }
                [PSCustomObject]@{
                    DisplayName = 'Org B'; Id = 'org-b'
                    OnPremisesSyncEnabled = $false
                    OnPremisesLastSyncDateTime = $null
                    OnPremisesLastPasswordSyncDateTime = $null
                }
            )
            Mock Get-MgOrganization { return $mockOrgs }
        }

        It 'should return a report for each organization' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 2
        }
    }

    Context 'parameter validation' {
        BeforeAll {
            Mock Get-MgOrganization { return @() }
        }

        It 'should reject empty string for OutputPath' {
            { & $script:ScriptPath -OutputPath '' } | Should -Throw
        }
    }
}
