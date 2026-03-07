BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Security/Get-DefenderPolicyReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-OrganizationConfig { }
    function Get-SafeLinksPolicy { }
    function Get-SafeAttachmentPolicy { }
}

Describe 'Get-DefenderPolicyReport' {
    BeforeAll {
        # Mock EXO connection check
        Mock Get-OrganizationConfig { return @{ Name = 'contoso' } }
    }

    Context 'when both Safe Links and Safe Attachments policies exist' {
        BeforeAll {
            # Mock Get-Command to indicate both cmdlets are available
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeLinksPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeAttachmentPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            $mockSafeLinks = @(
                [PSCustomObject]@{
                    Name                     = 'Built-In Protection Policy'
                    IsEnabled                = $true
                    Priority                 = 0
                    DoNotTrackUserClicks     = $false
                    ScanUrls                 = $true
                    EnableForInternalSenders = $true
                }
                [PSCustomObject]@{
                    Name                     = 'Custom Safe Links'
                    IsEnabled                = $true
                    Priority                 = 1
                    DoNotTrackUserClicks     = $false
                    ScanUrls                 = $true
                    EnableForInternalSenders = $false
                }
            )
            Mock Get-SafeLinksPolicy { return $mockSafeLinks }

            $mockSafeAttachments = @(
                [PSCustomObject]@{
                    Name            = 'Default Safe Attachments'
                    Enable          = $true
                    Priority        = 0
                    Action          = 'Block'
                    Redirect        = $true
                    RedirectAddress = 'admin@contoso.com'
                }
            )
            Mock Get-SafeAttachmentPolicy { return $mockSafeAttachments }
        }

        It 'should return results containing both policy types' {
            $result = & $script:ScriptPath
            $policyTypes = $result | ForEach-Object { $_.PolicyType } | Sort-Object -Unique
            $policyTypes | Should -Contain 'SafeLinks'
            $policyTypes | Should -Contain 'SafeAttachments'
        }

        It 'should return correct number of Safe Links policies' {
            $result = & $script:ScriptPath
            $safeLinks = @($result | Where-Object { $_.PolicyType -eq 'SafeLinks' })
            $safeLinks.Count | Should -Be 2
        }

        It 'should return correct number of Safe Attachments policies' {
            $result = & $script:ScriptPath
            $safeAttach = @($result | Where-Object { $_.PolicyType -eq 'SafeAttachments' })
            $safeAttach.Count | Should -Be 1
        }

        It 'should include PolicyType, Name, Enabled, Priority, and KeySettings properties' {
            $result = & $script:ScriptPath
            $result[0].PSObject.Properties.Name | Should -Contain 'PolicyType'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Enabled'
            $result[0].PSObject.Properties.Name | Should -Contain 'Priority'
            $result[0].PSObject.Properties.Name | Should -Contain 'KeySettings'
        }

        It 'should report Enabled state for Safe Links policies' {
            $result = & $script:ScriptPath
            $builtIn = $result | Where-Object { $_.Name -eq 'Built-In Protection Policy' }
            $builtIn.Enabled | Should -Be $true
        }

        It 'should report priority for Safe Links policies' {
            $result = & $script:ScriptPath
            $builtIn = $result | Where-Object { $_.Name -eq 'Built-In Protection Policy' }
            $builtIn.Priority | Should -Be 0
        }

        It 'should include ScanUrls in Safe Links key settings' {
            $result = & $script:ScriptPath
            $builtIn = $result | Where-Object { $_.Name -eq 'Built-In Protection Policy' }
            $builtIn.KeySettings | Should -Match 'ScanUrls=True'
        }

        It 'should include Action in Safe Attachments key settings' {
            $result = & $script:ScriptPath
            $safeAttach = $result | Where-Object { $_.PolicyType -eq 'SafeAttachments' }
            $safeAttach.KeySettings | Should -Match 'Action=Block'
        }

        It 'should include RedirectAddress in Safe Attachments key settings' {
            $result = & $script:ScriptPath
            $safeAttach = $result | Where-Object { $_.PolicyType -eq 'SafeAttachments' }
            $safeAttach.KeySettings | Should -Match 'RedirectAddress=admin@contoso.com'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeLinksPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeAttachmentPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            Mock Get-SafeLinksPolicy {
                return @([PSCustomObject]@{
                    Name = 'Test'; IsEnabled = $true; Priority = 0
                    DoNotTrackUserClicks = $false; ScanUrls = $true; EnableForInternalSenders = $true
                })
            }
            Mock Get-SafeAttachmentPolicy { return @() }
            $script:csvOutputPath = Join-Path $TestDrive 'test-defender.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported.*Defender for Office 365 policies'
        }
    }

    Context 'when Safe Links cmdlet is not found (no Defender license)' {
        BeforeAll {
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeAttachmentPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            Mock Get-SafeAttachmentPolicy {
                return @([PSCustomObject]@{
                    Name = 'Default'; Enable = $true; Priority = 0
                    Action = 'Block'; Redirect = $false; RedirectAddress = ''
                })
            }
        }

        It 'should skip Safe Links and still return Safe Attachments' {
            $result = & $script:ScriptPath 3>$null
            $safeLinks = @($result | Where-Object { $_.PolicyType -eq 'SafeLinks' })
            $safeLinks.Count | Should -Be 0
            $safeAttach = @($result | Where-Object { $_.PolicyType -eq 'SafeAttachments' })
            $safeAttach.Count | Should -Be 1
        }
    }

    Context 'when Safe Attachments cmdlet is not found (no Defender license)' {
        BeforeAll {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeLinksPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            Mock Get-SafeLinksPolicy {
                return @([PSCustomObject]@{
                    Name = 'Default'; IsEnabled = $true; Priority = 0
                    DoNotTrackUserClicks = $false; ScanUrls = $true; EnableForInternalSenders = $true
                })
            }
        }

        It 'should skip Safe Attachments and still return Safe Links' {
            $result = & $script:ScriptPath 3>$null
            $safeAttach = @($result | Where-Object { $_.PolicyType -eq 'SafeAttachments' })
            $safeAttach.Count | Should -Be 0
            $safeLinks = @($result | Where-Object { $_.PolicyType -eq 'SafeLinks' })
            $safeLinks.Count | Should -Be 1
        }
    }

    Context 'when both Defender cmdlets are not found (no Defender license at all)' {
        BeforeAll {
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }
        }

        It 'should return nothing and issue a warning' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when Get-SafeLinksPolicy throws at retrieval time' {
        BeforeAll {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeLinksPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeAttachmentPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            Mock Get-SafeLinksPolicy { throw 'Access denied' }
            Mock Get-SafeAttachmentPolicy { return @() }
        }

        It 'should handle the error gracefully and return no results' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when no policies are returned despite cmdlets being available' {
        BeforeAll {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeLinksPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeAttachmentPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            Mock Get-SafeLinksPolicy { return $null }
            Mock Get-SafeAttachmentPolicy { return $null }
        }

        It 'should return nothing and issue a warning about no policies found' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when not connected to Exchange Online' {
        BeforeAll {
            Mock Get-OrganizationConfig { throw 'Not connected' }
        }

        It 'should write an error and return nothing' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Exchange Online*'
        }
    }

    Context 'when Safe Links policy has no priority set' {
        BeforeAll {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeLinksPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeLinksPolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-SafeAttachmentPolicy' } } -ParameterFilter { $Name -eq 'Get-SafeAttachmentPolicy' }

            Mock Get-SafeLinksPolicy {
                return @([PSCustomObject]@{
                    Name = 'No Priority'; IsEnabled = $true; Priority = $null
                    DoNotTrackUserClicks = $false; ScanUrls = $true; EnableForInternalSenders = $false
                })
            }
            Mock Get-SafeAttachmentPolicy { return @() }
        }

        It 'should default priority to N/A' {
            $result = & $script:ScriptPath
            $policy = $result | Where-Object { $_.Name -eq 'No Priority' }
            $policy.Priority | Should -Be 'N/A'
        }
    }
}
