BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Collaboration/Get-TeamsAccessReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Invoke-MgGraphRequest { }
}

Describe 'Get-TeamsAccessReport' {
    BeforeAll {
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when all endpoints return data successfully' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                switch -Wildcard ($Uri) {
                    '*teamsAppSettings' {
                        return @{
                            isChatResourceSpecificConsentEnabled                    = $true
                            isUserPersonalScopeResourceSpecificConsentEnabled       = $false
                        }
                    }
                    '*groupSettings' {
                        return @{
                            value = @(
                                @{
                                    displayName = 'Group.Unified.Guest'
                                    values = @(
                                        @{ name = 'AllowGuestsToAccessGroups'; value = 'True' }
                                        @{ name = 'AllowToAddGuests'; value = 'True' }
                                    )
                                }
                            )
                        }
                    }
                    '*allTeams*' {
                        return @{ value = @() }
                    }
                    '*teamwork' {
                        return @{
                            isGuestAccessEnabled           = $true
                            allowGuestCreateUpdateChannels = $true
                            allowThirdPartyApps            = $false
                        }
                    }
                    default {
                        return @{}
                    }
                }
            }
        }

        It 'should return a report object' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
            @($result).Count | Should -Be 1
        }

        It 'should include all expected properties' {
            $result = & $script:ScriptPath
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'AllowGuestAccess'
            $props | Should -Contain 'AllowGuestCreateUpdateChannels'
            $props | Should -Contain 'AllowThirdPartyApps'
            $props | Should -Contain 'AllowSideLoading'
            $props | Should -Contain 'IsUserPersonalScopeResourceSpecificConsentEnabled'
        }

        It 'should report AllowSideLoading from beta teamsAppSettings' {
            $result = & $script:ScriptPath
            $result[0].AllowSideLoading | Should -BeTrue
        }

        It 'should report IsUserPersonalScopeResourceSpecificConsentEnabled' {
            $result = & $script:ScriptPath
            $result[0].IsUserPersonalScopeResourceSpecificConsentEnabled | Should -BeFalse
        }

        It 'should report AllowGuestAccess from teamwork endpoint' {
            $result = & $script:ScriptPath
            $result[0].AllowGuestAccess | Should -BeTrue
        }

        It 'should report AllowGuestCreateUpdateChannels' {
            $result = & $script:ScriptPath
            $result[0].AllowGuestCreateUpdateChannels | Should -BeTrue
        }

        It 'should report AllowThirdPartyApps' {
            $result = & $script:ScriptPath
            $result[0].AllowThirdPartyApps | Should -BeFalse
        }
    }

    Context 'when beta teamsAppSettings endpoint fails (partial failure)' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                switch -Wildcard ($Uri) {
                    '*teamsAppSettings' {
                        throw 'Beta endpoint not available'
                    }
                    '*groupSettings' {
                        return @{
                            value = @(
                                @{
                                    displayName = 'Group.Unified'
                                    values = @(
                                        @{ name = 'AllowGuestsToAccessGroups'; value = 'True' }
                                    )
                                }
                            )
                        }
                    }
                    '*allTeams*' {
                        return @{ value = @() }
                    }
                    '*teamwork' {
                        return @{}
                    }
                    default {
                        return @{}
                    }
                }
            }
        }

        It 'should still return a report object' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should report AllowSideLoading as N/A when beta is unavailable' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result[0].AllowSideLoading | Should -Be 'N/A'
        }

        It 'should report IsUserPersonalScopeResourceSpecificConsentEnabled as N/A' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result[0].IsUserPersonalScopeResourceSpecificConsentEnabled | Should -Be 'N/A'
        }

        It 'should emit a warning about beta endpoint' {
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when groupSettings returns Group.Unified instead of Group.Unified.Guest' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                switch -Wildcard ($Uri) {
                    '*teamsAppSettings' {
                        return @{
                            isChatResourceSpecificConsentEnabled                    = $false
                            isUserPersonalScopeResourceSpecificConsentEnabled       = $false
                        }
                    }
                    '*groupSettings' {
                        return @{
                            value = @(
                                @{
                                    displayName = 'Group.Unified'
                                    values = @(
                                        @{ name = 'AllowGuestsToAccessGroups'; value = 'False' }
                                        @{ name = 'AllowToAddGuests'; value = 'False' }
                                    )
                                }
                            )
                        }
                    }
                    '*allTeams*' {
                        return @{ value = @() }
                    }
                    '*teamwork' {
                        return @{}
                    }
                    default {
                        return @{}
                    }
                }
            }
        }

        It 'should fall back to Group.Unified for guest settings' {
            $result = & $script:ScriptPath
            $result[0].AllowGuestAccess | Should -Be $false
        }
    }

    Context 'when groupSettings endpoint fails' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                switch -Wildcard ($Uri) {
                    '*teamsAppSettings' {
                        return @{
                            isChatResourceSpecificConsentEnabled                    = $true
                            isUserPersonalScopeResourceSpecificConsentEnabled       = $true
                        }
                    }
                    '*groupSettings' {
                        throw 'Access denied to group settings'
                    }
                    '*allTeams*' {
                        return @{ value = @() }
                    }
                    '*teamwork' {
                        return @{}
                    }
                    default {
                        return @{}
                    }
                }
            }
        }

        It 'should still return a report with N/A for guest access' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result | Should -Not -BeNullOrEmpty
            $result[0].AllowGuestAccess | Should -Be 'N/A'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                param($Uri, $Method)
                switch -Wildcard ($Uri) {
                    '*teamsAppSettings' {
                        return @{
                            isChatResourceSpecificConsentEnabled                    = $true
                            isUserPersonalScopeResourceSpecificConsentEnabled       = $true
                        }
                    }
                    '*groupSettings' {
                        return @{ value = @() }
                    }
                    '*allTeams*' {
                        return @{ value = @() }
                    }
                    '*teamwork' {
                        return @{}
                    }
                    default {
                        return @{}
                    }
                }
            }
            $script:csvOutputPath = Join-Path $TestDrive 'teams-access.csv'
        }

        It 'should export results to a CSV file' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported Teams access settings to *'
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
            Mock Invoke-MgGraphRequest { return @{} }
        }

        It 'should reject empty string for OutputPath' {
            { & $script:ScriptPath -OutputPath '' } | Should -Throw
        }
    }
}
