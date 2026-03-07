BeforeAll {
    . (Join-Path $PSScriptRoot '../../Exchange-Online/Get-MailboxPermissionReport.ps1')
}

Describe 'Get-MailboxPermissionReport' {
    BeforeAll {
        Mock Get-OrganizationConfig { return @{ Name = 'contoso' } }
    }

    Context 'when auditing all permission types on a specific mailbox' {
        BeforeAll {
            $mockMailbox = [PSCustomObject]@{
                DisplayName = 'John Smith'
                PrimarySmtpAddress = 'jsmith@contoso.com'
                GrantSendOnBehalfTo = @('jdoe@contoso.com')
            }
            Mock Get-EXOMailbox { return $mockMailbox }

            Mock Get-MailboxPermission {
                @(
                    [PSCustomObject]@{
                        User = 'jdoe@contoso.com'
                        AccessRights = @('FullAccess')
                        IsInherited = $false
                    }
                    [PSCustomObject]@{
                        User = 'NT AUTHORITY\SELF'
                        AccessRights = @('FullAccess')
                        IsInherited = $false
                    }
                )
            }

            Mock Get-RecipientPermission {
                @(
                    [PSCustomObject]@{
                        Trustee = 'manager@contoso.com'
                        AccessRights = @('SendAs')
                    }
                    [PSCustomObject]@{
                        Trustee = 'NT AUTHORITY\SELF'
                        AccessRights = @('SendAs')
                    }
                )
            }
        }

        It 'should return permission entries' {
            $result = Get-MailboxPermissionReport -Identity 'jsmith@contoso.com'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should exclude NT AUTHORITY entries from FullAccess' {
            $result = Get-MailboxPermissionReport -Identity 'jsmith@contoso.com' -PermissionType FullAccess
            $ntEntries = $result | Where-Object { $_.GrantedTo -like 'NT AUTHORITY*' }
            $ntEntries | Should -BeNullOrEmpty
        }

        It 'should exclude NT AUTHORITY entries from SendAs' {
            $result = Get-MailboxPermissionReport -Identity 'jsmith@contoso.com' -PermissionType SendAs
            $ntEntries = $result | Where-Object { $_.GrantedTo -like 'NT AUTHORITY*' }
            $ntEntries | Should -BeNullOrEmpty
        }

        It 'should include SendOnBehalf delegates' {
            $result = Get-MailboxPermissionReport -Identity 'jsmith@contoso.com' -PermissionType SendOnBehalf
            $result.Count | Should -Be 1
            $result[0].GrantedTo | Should -Be 'jdoe@contoso.com'
        }

        It 'should include expected properties' {
            $result = Get-MailboxPermissionReport -Identity 'jsmith@contoso.com'
            $result[0].PSObject.Properties.Name | Should -Contain 'Mailbox'
            $result[0].PSObject.Properties.Name | Should -Contain 'MailboxAddress'
            $result[0].PSObject.Properties.Name | Should -Contain 'PermissionType'
            $result[0].PSObject.Properties.Name | Should -Contain 'GrantedTo'
        }
    }

    Context 'when filtering by PermissionType FullAccess' {
        BeforeAll {
            $mockMailbox = [PSCustomObject]@{
                DisplayName = 'Test User'
                PrimarySmtpAddress = 'test@contoso.com'
                GrantSendOnBehalfTo = @()
            }
            Mock Get-EXOMailbox { return $mockMailbox }
            Mock Get-MailboxPermission {
                @([PSCustomObject]@{
                    User = 'delegate@contoso.com'
                    AccessRights = @('FullAccess')
                    IsInherited = $false
                })
            }
            Mock Get-RecipientPermission { }
        }

        It 'should only check FullAccess permissions' {
            $result = Get-MailboxPermissionReport -Identity 'test@contoso.com' -PermissionType FullAccess
            Should -Invoke Get-MailboxPermission -Times 1 -Exactly
            Should -Invoke Get-RecipientPermission -Times 0 -Exactly
        }
    }

    Context 'when auditing all mailboxes' {
        BeforeAll {
            $mockMailboxes = @(
                [PSCustomObject]@{
                    DisplayName = 'User1'; PrimarySmtpAddress = 'user1@contoso.com'
                    GrantSendOnBehalfTo = @()
                }
                [PSCustomObject]@{
                    DisplayName = 'User2'; PrimarySmtpAddress = 'user2@contoso.com'
                    GrantSendOnBehalfTo = @()
                }
            )
            Mock Get-EXOMailbox { return $mockMailboxes } -ParameterFilter {
                $ResultSize -eq 'Unlimited'
            }
            Mock Get-MailboxPermission { @() }
            Mock Get-RecipientPermission { @() }
        }

        It 'should query all user mailboxes when no Identity specified' {
            $null = Get-MailboxPermissionReport
            Should -Invoke Get-EXOMailbox -Times 1 -Exactly -ParameterFilter {
                $ResultSize -eq 'Unlimited' -and $RecipientTypeDetails -eq 'UserMailbox'
            }
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockMailbox = [PSCustomObject]@{
                DisplayName = 'Test'; PrimarySmtpAddress = 'test@contoso.com'
                GrantSendOnBehalfTo = @()
            }
            Mock Get-EXOMailbox { return $mockMailbox }
            Mock Get-MailboxPermission { @() }
            Mock Get-RecipientPermission { @() }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Get-MailboxPermissionReport -Identity 'test@contoso.com' -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'when not connected to Exchange Online' {
        BeforeAll {
            Mock Get-OrganizationConfig { throw 'Not connected' }
        }

        It 'should throw an error' {
            { Get-MailboxPermissionReport } | Should -Throw '*Not connected to Exchange Online*'
        }
    }

    Context 'when a mailbox identity is not found' {
        BeforeAll {
            Mock Get-EXOMailbox { throw 'Mailbox not found' }
        }

        It 'should warn but not throw' {
            Get-MailboxPermissionReport -Identity 'nonexistent@contoso.com' 3>&1 | Should -Not -BeNullOrEmpty
        }
    }

    Context 'parameter validation' {
        It 'should reject invalid PermissionType' {
            { Get-MailboxPermissionReport -PermissionType 'Invalid' } | Should -Throw
        }
    }
}
