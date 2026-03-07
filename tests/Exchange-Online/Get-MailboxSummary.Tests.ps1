BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Exchange-Online/Get-MailboxSummary.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-OrganizationConfig { }
    function Get-EXOMailbox { }
    function Get-EXOMailboxStatistics { }
    function Get-DistributionGroup { }
    function Get-UnifiedGroup { }
}

Describe 'Get-MailboxSummary' {
    BeforeAll {
        Mock Import-Module { }
        # Mock EXO connection check
        Mock Get-OrganizationConfig { return @{ Name = 'contoso' } }
    }

    Context 'when mailboxes and groups exist' {
        BeforeAll {
            $mockMailboxes = @(
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox';      ItemCount = 1500 }
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox';      ItemCount = 2300 }
                [PSCustomObject]@{ RecipientTypeDetails = 'SharedMailbox';    ItemCount = 400 }
                [PSCustomObject]@{ RecipientTypeDetails = 'RoomMailbox';      ItemCount = 50 }
                [PSCustomObject]@{ RecipientTypeDetails = 'EquipmentMailbox'; ItemCount = 10 }
            )
            Mock Get-EXOMailbox { return $mockMailboxes }
            Mock Get-EXOMailboxStatistics { return [PSCustomObject]@{ ItemCount = 852 } }

            $mockDistGroups = @(
                [PSCustomObject]@{ Name = 'DL-Sales'; PrimarySmtpAddress = 'sales@contoso.com' }
                [PSCustomObject]@{ Name = 'DL-IT';    PrimarySmtpAddress = 'it@contoso.com' }
            )
            Mock Get-DistributionGroup { return $mockDistGroups }

            $mockM365Groups = @(
                [PSCustomObject]@{ DisplayName = 'Project Alpha'; PrimarySmtpAddress = 'alpha@contoso.com' }
            )
            Mock Get-UnifiedGroup { return $mockM365Groups }
        }

        It 'should return results with correct metric names' {
            $result = & $script:ScriptPath
            $metrics = $result | ForEach-Object { $_.Metric }
            $metrics | Should -Contain 'TotalMailboxes'
            $metrics | Should -Contain 'UserMailboxes'
            $metrics | Should -Contain 'SharedMailboxes'
            $metrics | Should -Contain 'RoomMailboxes'
            $metrics | Should -Contain 'EquipmentMailboxes'
            $metrics | Should -Contain 'DistributionGroups'
            $metrics | Should -Contain 'M365Groups'
            $metrics | Should -Contain 'TotalItems'
        }

        It 'should count total mailboxes correctly' {
            $result = & $script:ScriptPath
            $total = $result | Where-Object { $_.Metric -eq 'TotalMailboxes' }
            $total.Count | Should -Be 5
        }

        It 'should count user mailboxes correctly' {
            $result = & $script:ScriptPath
            $user = $result | Where-Object { $_.Metric -eq 'UserMailboxes' }
            $user.Count | Should -Be 2
        }

        It 'should count shared mailboxes correctly' {
            $result = & $script:ScriptPath
            $shared = $result | Where-Object { $_.Metric -eq 'SharedMailboxes' }
            $shared.Count | Should -Be 1
        }

        It 'should count room mailboxes correctly' {
            $result = & $script:ScriptPath
            $room = $result | Where-Object { $_.Metric -eq 'RoomMailboxes' }
            $room.Count | Should -Be 1
        }

        It 'should count equipment mailboxes correctly' {
            $result = & $script:ScriptPath
            $equip = $result | Where-Object { $_.Metric -eq 'EquipmentMailboxes' }
            $equip.Count | Should -Be 1
        }

        It 'should count distribution groups correctly' {
            $result = & $script:ScriptPath
            $dls = $result | Where-Object { $_.Metric -eq 'DistributionGroups' }
            $dls.Count | Should -Be 2
        }

        It 'should count M365 groups correctly' {
            $result = & $script:ScriptPath
            $m365 = $result | Where-Object { $_.Metric -eq 'M365Groups' }
            $m365.Count | Should -Be 1
        }

        It 'should calculate total item count across all mailboxes' {
            $result = & $script:ScriptPath
            $items = $result | Where-Object { $_.Metric -eq 'TotalItems' }
            $items.Count | Should -Be '4260'
        }

        It 'should include Metric and Count properties' {
            $result = & $script:ScriptPath
            $result[0].PSObject.Properties.Name | Should -Contain 'Metric'
            $result[0].PSObject.Properties.Name | Should -Contain 'Count'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockMailboxes = @(
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox'; ItemCount = 100 }
            )
            Mock Get-EXOMailbox { return $mockMailboxes }
            Mock Get-DistributionGroup { return @() }
            Mock Get-UnifiedGroup { return @() }
            $script:csvOutputPath = Join-Path $TestDrive 'test-summary.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported mailbox summary'
        }
    }

    Context 'when no mailboxes are found' {
        BeforeAll {
            Mock Get-EXOMailbox { return @() }
            Mock Get-DistributionGroup { return @() }
            Mock Get-UnifiedGroup { return @() }
        }

        It 'should return results with zero counts' {
            $result = & $script:ScriptPath
            $total = $result | Where-Object { $_.Metric -eq 'TotalMailboxes' }
            $total.Count | Should -Be 0
        }

        It 'should show N/A for total items when no mailboxes exist' {
            $result = & $script:ScriptPath
            $items = $result | Where-Object { $_.Metric -eq 'TotalItems' }
            $items.Count | Should -Be 'N/A'
        }
    }

    Context 'when mailbox statistics are unavailable' {
        BeforeAll {
            $mockMailboxes = @(
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox'; ExchangeObjectId = 'a1' }
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox'; ExchangeObjectId = 'a2' }
            )
            Mock Get-EXOMailbox { return $mockMailboxes }
            Mock Get-EXOMailboxStatistics { throw 'Mailbox statistics unavailable' }
            Mock Get-DistributionGroup { return @() }
            Mock Get-UnifiedGroup { return @() }
        }

        It 'should show N/A for total items when statistics are unavailable' {
            $result = & $script:ScriptPath
            $items = $result | Where-Object { $_.Metric -eq 'TotalItems' }
            $items.Count | Should -Be 'N/A'
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

    Context 'when Get-EXOMailbox fails' {
        BeforeAll {
            Mock Get-EXOMailbox { throw 'Access denied' }
        }

        It 'should write an error and return nothing' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve mailboxes*'
        }
    }

    Context 'when distribution group retrieval fails' {
        BeforeAll {
            $mockMailboxes = @(
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox'; ItemCount = 100 }
            )
            Mock Get-EXOMailbox { return $mockMailboxes }
            Mock Get-DistributionGroup { throw 'Permission denied' }
            Mock Get-UnifiedGroup { return @() }
        }

        It 'should still return results with zero distribution group count' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $dls = $result | Where-Object { $_.Metric -eq 'DistributionGroups' }
            $dls.Count | Should -Be 0
        }
    }

    Context 'when M365 group retrieval fails' {
        BeforeAll {
            $mockMailboxes = @(
                [PSCustomObject]@{ RecipientTypeDetails = 'UserMailbox'; ItemCount = 100 }
            )
            Mock Get-EXOMailbox { return $mockMailboxes }
            Mock Get-DistributionGroup { return @() }
            Mock Get-UnifiedGroup { throw 'Timeout' }
        }

        It 'should still return results with zero M365 group count' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $m365 = $result | Where-Object { $_.Metric -eq 'M365Groups' }
            $m365.Count | Should -Be 0
        }
    }
}
