BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Exchange-Online/Get-EmailSecurityReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-OrganizationConfig { }
    function Get-HostedContentFilterPolicy { }
    function Get-AntiPhishPolicy { }
    function Get-MalwareFilterPolicy { }
    function Get-DkimSigningConfig { }
    function Get-AcceptedDomain { }
    function Resolve-DnsName { param($Name, $Type, $ErrorAction) }
}

Describe 'Get-EmailSecurityReport' {
    BeforeAll {
        # Mock EXO connection check
        Mock Get-OrganizationConfig { return @{ Name = 'contoso' } }
    }

    Context 'when all policy types are present' {
        BeforeAll {
            $mockAntiSpam = @(
                [PSCustomObject]@{
                    Name                       = 'Default'
                    IsDefault                  = $true
                    IsEnabled                  = $null
                    BulkThreshold              = 7
                    SpamAction                 = 'MoveToJmf'
                    HighConfidenceSpamAction   = 'Quarantine'
                    PhishSpamAction            = 'Quarantine'
                    BulkSpamAction             = 'MoveToJmf'
                    QuarantineRetentionPeriod  = 30
                    InlineSafetyTipsEnabled    = $true
                    SpamZapEnabled             = $true
                    PhishZapEnabled            = $true
                    AllowedSenders             = @()
                    AllowedSenderDomains       = @()
                    BlockedSenders             = @()
                    BlockedSenderDomains       = @()
                }
            )
            Mock Get-HostedContentFilterPolicy { return $mockAntiSpam }

            $mockAntiPhish = @(
                [PSCustomObject]@{
                    Name                              = 'Office365 AntiPhish Default'
                    Enabled                           = $true
                    PhishThresholdLevel               = 2
                    EnableMailboxIntelligence          = $true
                    EnableMailboxIntelligenceProtection = $true
                    EnableSpoofIntelligence           = $true
                    EnableFirstContactSafetyTips      = $true
                    EnableUnauthenticatedSender       = $true
                    EnableViaTag                      = $true
                    EnableTargetedUserProtection      = $false
                    EnableTargetedDomainsProtection   = $false
                    EnableOrganizationDomainsProtection = $true
                    TargetedUsersToProtect            = @()
                }
            )
            Mock Get-AntiPhishPolicy { return $mockAntiPhish }

            $mockMalware = @(
                [PSCustomObject]@{
                    Name                                     = 'Default'
                    IsDefault                                = $true
                    IsEnabled                                = $null
                    EnableFileFilter                         = $true
                    FileFilterAction                         = 'Reject'
                    ZapEnabled                               = $true
                    EnableInternalSenderAdminNotifications    = $false
                    EnableExternalSenderAdminNotifications    = $false
                    InternalSenderAdminAddress               = $null
                    ExternalSenderAdminAddress               = $null
                    FileTypes                                = @('.exe', '.bat', '.cmd')
                }
            )
            Mock Get-MalwareFilterPolicy { return $mockMalware }

            $mockDkim = @(
                [PSCustomObject]@{
                    Domain          = 'contoso.com'
                    Enabled         = $true
                    Status          = 'Valid'
                    Selector1CNAME  = 'selector1-contoso-com._domainkey.contoso.onmicrosoft.com'
                    Selector2CNAME  = 'selector2-contoso-com._domainkey.contoso.onmicrosoft.com'
                }
            )
            Mock Get-DkimSigningConfig { return $mockDkim }
        }

        It 'should return results containing all policy types' {
            $result = & $script:ScriptPath
            $policyTypes = $result | ForEach-Object { $_.PolicyType } | Sort-Object -Unique
            $policyTypes | Should -Contain 'AntiSpam'
            $policyTypes | Should -Contain 'AntiPhish'
            $policyTypes | Should -Contain 'AntiMalware'
            $policyTypes | Should -Contain 'DKIM'
        }

        It 'should include PolicyType, Name, Enabled, and KeySettings properties' {
            $result = & $script:ScriptPath
            $result[0].PSObject.Properties.Name | Should -Contain 'PolicyType'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Enabled'
            $result[0].PSObject.Properties.Name | Should -Contain 'KeySettings'
        }

        It 'should mark default anti-spam policy as enabled' {
            $result = & $script:ScriptPath
            $antiSpam = $result | Where-Object { $_.PolicyType -eq 'AntiSpam' }
            $antiSpam.Enabled | Should -Be $true
        }

        It 'should include BulkThreshold in anti-spam key settings' {
            $result = & $script:ScriptPath
            $antiSpam = $result | Where-Object { $_.PolicyType -eq 'AntiSpam' }
            $antiSpam.KeySettings | Should -Match 'BulkThreshold=7'
        }

        It 'should include PhishThresholdLevel in anti-phish key settings' {
            $result = & $script:ScriptPath
            $antiPhish = $result | Where-Object { $_.PolicyType -eq 'AntiPhish' }
            $antiPhish.KeySettings | Should -Match 'PhishThresholdLevel=2'
        }

        It 'should include DKIM domain name as the Name field' {
            $result = & $script:ScriptPath
            $dkim = $result | Where-Object { $_.PolicyType -eq 'DKIM' }
            $dkim.Name | Should -Be 'contoso.com'
        }

        It 'should mark DKIM as enabled when Enabled property is true' {
            $result = & $script:ScriptPath
            $dkim = $result | Where-Object { $_.PolicyType -eq 'DKIM' }
            $dkim.Enabled | Should -Be $true
        }

        It 'should include FileTypesCount in anti-malware key settings' {
            $result = & $script:ScriptPath
            $malware = $result | Where-Object { $_.PolicyType -eq 'AntiMalware' }
            $malware.KeySettings | Should -Match 'FileTypesCount=3'
        }
    }

    Context 'when IncludeDnsChecks is specified' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy { return @() }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { return @() }

            Mock Get-Command { return $true } -ParameterFilter { $Name -eq 'Resolve-DnsName' }

            $mockDomains = @(
                [PSCustomObject]@{ DomainName = 'contoso.com' }
            )
            Mock Get-AcceptedDomain { return $mockDomains }

            # Mock SPF record
            Mock Resolve-DnsName {
                return @(
                    [PSCustomObject]@{
                        Strings = @('v=spf1 include:spf.protection.outlook.com -all')
                    }
                )
            } -ParameterFilter { $Name -eq 'contoso.com' -and $Type -eq 'TXT' }

            # Mock DMARC record
            Mock Resolve-DnsName {
                return @(
                    [PSCustomObject]@{
                        Strings = @('v=DMARC1; p=reject; rua=mailto:dmarc@contoso.com')
                    }
                )
            } -ParameterFilter { $Name -eq '_dmarc.contoso.com' -and $Type -eq 'TXT' }
        }

        It 'should include SPF and DMARC entries' {
            $result = & $script:ScriptPath -IncludeDnsChecks
            $policyTypes = $result | ForEach-Object { $_.PolicyType } | Sort-Object -Unique
            $policyTypes | Should -Contain 'SPF'
            $policyTypes | Should -Contain 'DMARC'
        }

        It 'should mark SPF as enabled when record is found' {
            $result = & $script:ScriptPath -IncludeDnsChecks
            $spf = $result | Where-Object { $_.PolicyType -eq 'SPF' }
            $spf.Enabled | Should -Be $true
        }

        It 'should detect hard fail enforcement in SPF' {
            $result = & $script:ScriptPath -IncludeDnsChecks
            $spf = $result | Where-Object { $_.PolicyType -eq 'SPF' }
            $spf.KeySettings | Should -Match 'HardFail'
        }

        It 'should parse DMARC policy correctly' {
            $result = & $script:ScriptPath -IncludeDnsChecks
            $dmarc = $result | Where-Object { $_.PolicyType -eq 'DMARC' }
            $dmarc.KeySettings | Should -Match 'Policy=reject'
        }
    }

    Context 'when IncludeDnsChecks is specified but Resolve-DnsName is unavailable' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy { return @() }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { return @() }

            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Resolve-DnsName' }
        }

        It 'should skip DNS checks gracefully' {
            $result = & $script:ScriptPath -IncludeDnsChecks 3>$null
            $spf = @($result | Where-Object { $_.PolicyType -eq 'SPF' })
            $spf.Count | Should -Be 0
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy {
                return @([PSCustomObject]@{
                    Name = 'Default'; IsDefault = $true; IsEnabled = $null
                    BulkThreshold = 7; SpamAction = 'MoveToJmf'
                    HighConfidenceSpamAction = 'Quarantine'
                    PhishSpamAction = 'Quarantine'; BulkSpamAction = 'MoveToJmf'
                    QuarantineRetentionPeriod = 30; InlineSafetyTipsEnabled = $true
                    SpamZapEnabled = $true; PhishZapEnabled = $true
                    AllowedSenders = @(); AllowedSenderDomains = @()
                    BlockedSenders = @(); BlockedSenderDomains = @()
                })
            }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { return @() }
            $script:csvOutputPath = Join-Path $TestDrive 'test-email-security.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported email security report'
        }
    }

    Context 'when anti-spam policy retrieval fails' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy { throw 'Access denied' }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { return @() }
        }

        It 'should still return results without anti-spam policies' {
            $result = & $script:ScriptPath 3>$null
            $antiSpam = @($result | Where-Object { $_.PolicyType -eq 'AntiSpam' })
            $antiSpam.Count | Should -Be 0
        }
    }

    Context 'when anti-phish policy retrieval fails' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy { return @() }
            Mock Get-AntiPhishPolicy { throw 'Access denied' }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { return @() }
        }

        It 'should still return results without anti-phish policies' {
            $result = & $script:ScriptPath 3>$null
            $antiPhish = @($result | Where-Object { $_.PolicyType -eq 'AntiPhish' })
            $antiPhish.Count | Should -Be 0
        }
    }

    Context 'when malware policy retrieval fails' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy { return @() }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { throw 'Access denied' }
            Mock Get-DkimSigningConfig { return @() }
        }

        It 'should still return results without malware policies' {
            $result = & $script:ScriptPath 3>$null
            $malware = @($result | Where-Object { $_.PolicyType -eq 'AntiMalware' })
            $malware.Count | Should -Be 0
        }
    }

    Context 'when DKIM retrieval fails' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy { return @() }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { throw 'Not available' }
        }

        It 'should still return results without DKIM entries' {
            $result = & $script:ScriptPath 3>$null
            $dkim = @($result | Where-Object { $_.PolicyType -eq 'DKIM' })
            $dkim.Count | Should -Be 0
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

    Context 'when anti-spam policy has allowed and blocked senders' {
        BeforeAll {
            Mock Get-HostedContentFilterPolicy {
                return @([PSCustomObject]@{
                    Name = 'Custom'; IsDefault = $false; IsEnabled = $true
                    BulkThreshold = 5; SpamAction = 'Quarantine'
                    HighConfidenceSpamAction = 'Quarantine'
                    PhishSpamAction = 'Quarantine'; BulkSpamAction = 'Quarantine'
                    QuarantineRetentionPeriod = 15; InlineSafetyTipsEnabled = $true
                    SpamZapEnabled = $true; PhishZapEnabled = $true
                    AllowedSenders = @('trusted@partner.com')
                    AllowedSenderDomains = @('trusted.com', 'partner.com')
                    BlockedSenders = @('spammer@bad.com')
                    BlockedSenderDomains = @('bad.com')
                })
            }
            Mock Get-AntiPhishPolicy { return @() }
            Mock Get-MalwareFilterPolicy { return @() }
            Mock Get-DkimSigningConfig { return @() }
        }

        It 'should include allowed and blocked sender counts in key settings' {
            $result = & $script:ScriptPath
            $antiSpam = $result | Where-Object { $_.PolicyType -eq 'AntiSpam' }
            $antiSpam.KeySettings | Should -Match 'AllowedSenderDomains=2'
            $antiSpam.KeySettings | Should -Match 'BlockedSenders=1'
        }
    }
}
