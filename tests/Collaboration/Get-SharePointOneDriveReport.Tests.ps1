BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Collaboration/Get-SharePointOneDriveReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Invoke-MgGraphRequest { }
}

Describe 'Get-SharePointOneDriveReport' {
    BeforeAll {
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when SharePoint settings are returned successfully' {
        BeforeAll {
            $mockSpoSettings = @{
                sharingCapability                 = 'ExternalUserAndGuestSharing'
                sharingDomainRestrictionMode      = 'none'
                isResharingByExternalUsersEnabled = $true
                isUnmanagedSyncClientRestricted   = $false
                tenantDefaultTimezone             = 'UTC'
                oneDriveLoopSharingCapability     = 'ExternalUserAndGuestSharing'
                isMacSyncAppEnabled               = $true
                isLoopEnabled                     = $true
            }
            Mock Invoke-MgGraphRequest { return $mockSpoSettings }
        }

        It 'should return a report object' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
            @($result).Count | Should -Be 1
        }

        It 'should include all expected properties' {
            $result = & $script:ScriptPath
            $props = $result[0].PSObject.Properties.Name
            $props | Should -Contain 'SharingCapability'
            $props | Should -Contain 'SharingDomainRestrictionMode'
            $props | Should -Contain 'IsResharingByExternalUsersEnabled'
            $props | Should -Contain 'IsUnmanagedSyncClientRestricted'
            $props | Should -Contain 'TenantDefaultTimezone'
            $props | Should -Contain 'OneDriveLoopSharingCapability'
            $props | Should -Contain 'IsMacSyncAppEnabled'
            $props | Should -Contain 'IsLoopEnabled'
        }

        It 'should correctly map SharingCapability' {
            $result = & $script:ScriptPath
            $result[0].SharingCapability | Should -Be 'ExternalUserAndGuestSharing'
        }

        It 'should correctly map boolean properties' {
            $result = & $script:ScriptPath
            $result[0].IsResharingByExternalUsersEnabled | Should -BeTrue
            $result[0].IsUnmanagedSyncClientRestricted | Should -BeFalse
            $result[0].IsMacSyncAppEnabled | Should -BeTrue
            $result[0].IsLoopEnabled | Should -BeTrue
        }

        It 'should correctly map TenantDefaultTimezone' {
            $result = & $script:ScriptPath
            $result[0].TenantDefaultTimezone | Should -Be 'UTC'
        }
    }

    Context 'when the API returns a 403 Forbidden' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                $ex = [System.Net.Http.HttpRequestException]::new('403 Forbidden')
                $mockResponse = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]::Forbidden }
                $ex | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse -Force
                throw $ex
            }
        }

        It 'should handle the 403 gracefully and not throw an unhandled error' {
            # The script catches 403 and calls Write-Warning + return
            # Under $ErrorActionPreference = 'Stop', Write-Warning does not terminate
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -BeLike '*403*'
        }
    }

    Context 'when the API returns a 404 Not Found' {
        BeforeAll {
            Mock Invoke-MgGraphRequest {
                $ex = [System.Net.Http.HttpRequestException]::new('404 Not Found')
                $mockResponse = [PSCustomObject]@{ StatusCode = [System.Net.HttpStatusCode]::NotFound }
                $ex | Add-Member -NotePropertyName 'Response' -NotePropertyValue $mockResponse -Force
                throw $ex
            }
        }

        It 'should handle the 404 gracefully and warn about missing SharePoint license' {
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -BeLike '*404*'
        }
    }

    Context 'when the API throws an unexpected error without Response' {
        BeforeAll {
            Mock Invoke-MgGraphRequest { throw 'Unexpected network error' }
        }

        It 'should write an error about failed retrieval' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve SharePoint tenant settings*'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockSpoSettings = @{
                sharingCapability                 = 'Disabled'
                sharingDomainRestrictionMode      = 'allowList'
                isResharingByExternalUsersEnabled = $false
                isUnmanagedSyncClientRestricted   = $true
                tenantDefaultTimezone             = 'Eastern Standard Time'
                oneDriveLoopSharingCapability     = 'Disabled'
                isMacSyncAppEnabled               = $false
                isLoopEnabled                     = $false
            }
            Mock Invoke-MgGraphRequest { return $mockSpoSettings }
            $script:csvOutputPath = Join-Path $TestDrive 'spo-settings.csv'
        }

        It 'should export results to a CSV file' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported SharePoint/OneDrive settings to *'
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
