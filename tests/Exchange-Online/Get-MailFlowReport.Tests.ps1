BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Exchange-Online/Get-MailFlowReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-OrganizationConfig { }
    function Get-AcceptedDomain { }
    function Get-InboundConnector { }
    function Get-OutboundConnector { }
    function Get-TransportRule { }
}

Describe 'Get-MailFlowReport' {
    BeforeAll {
        # Mock EXO connection check
        Mock Get-OrganizationConfig { return @{ Name = 'contoso' } }
    }

    Context 'when all item types are present' {
        BeforeAll {
            $mockDomains = @(
                [PSCustomObject]@{
                    DomainName = 'contoso.com'
                    DomainType = 'Authoritative'
                    Default    = $true
                }
                [PSCustomObject]@{
                    DomainName = 'fabrikam.com'
                    DomainType = 'Authoritative'
                    Default    = $false
                }
            )
            Mock Get-AcceptedDomain { return $mockDomains }

            $mockInbound = @(
                [PSCustomObject]@{
                    Name                        = 'From Partner Org'
                    ConnectorType               = 'Partner'
                    Enabled                     = $true
                    RequireTls                  = $true
                    RestrictDomainsToCertificate = $false
                    SenderDomains               = @('partner.com')
                    SenderIPAddresses           = @('10.0.0.1')
                    TlsSenderCertificateName    = 'partner.com'
                }
            )
            Mock Get-InboundConnector { return $mockInbound }

            $mockOutbound = @(
                [PSCustomObject]@{
                    Name             = 'To On-Prem'
                    ConnectorType    = 'OnPremises'
                    Enabled          = $true
                    RecipientDomains = @('internal.contoso.com')
                    UseMXRecord      = $false
                    TlsSettings      = 'EncryptionOnly'
                    SmartHosts       = @('mail.contoso.com')
                }
            )
            Mock Get-OutboundConnector { return $mockOutbound }

            $mockTransportRules = @(
                [PSCustomObject]@{
                    Name              = 'Disclaimer Rule'
                    Priority          = 0
                    Mode              = 'Enforce'
                    State             = 'Enabled'
                    SentTo            = $null
                    SentToMemberOf    = $null
                    FromMemberOf      = $null
                    From              = $null
                    SubjectContainsWords   = $null
                    HasAttachment     = $false
                    AddToRecipients   = $null
                    BlindCopyTo       = $null
                    ModerateMessageByUser  = $null
                    RejectMessageReasonText = $null
                    DeleteMessage     = $false
                    PrependSubject    = $null
                    SetHeaderName     = $null
                    SetHeaderValue    = $null
                    ApplyHtmlDisclaimerText = 'Confidential'
                }
            )
            Mock Get-TransportRule { return $mockTransportRules }
        }

        It 'should return results containing all item types' {
            $result = & $script:ScriptPath
            $itemTypes = $result | ForEach-Object { $_.ItemType } | Sort-Object -Unique
            $itemTypes | Should -Contain 'Domain'
            $itemTypes | Should -Contain 'InboundConnector'
            $itemTypes | Should -Contain 'OutboundConnector'
            $itemTypes | Should -Contain 'TransportRule'
        }

        It 'should return correct number of domains' {
            $result = & $script:ScriptPath
            $domains = @($result | Where-Object { $_.ItemType -eq 'Domain' })
            $domains.Count | Should -Be 2
        }

        It 'should mark default domain as Default status' {
            $result = & $script:ScriptPath
            $defaultDomain = $result | Where-Object { $_.Name -eq 'contoso.com' }
            $defaultDomain.Status | Should -Be 'Default'
        }

        It 'should mark non-default domain as Active status' {
            $result = & $script:ScriptPath
            $otherDomain = $result | Where-Object { $_.Name -eq 'fabrikam.com' }
            $otherDomain.Status | Should -Be 'Active'
        }

        It 'should mark enabled connectors as Enabled' {
            $result = & $script:ScriptPath
            $inbound = $result | Where-Object { $_.ItemType -eq 'InboundConnector' }
            $inbound.Status | Should -Be 'Enabled'
        }

        It 'should include ItemType, Name, Status, and Details properties' {
            $result = & $script:ScriptPath
            $result[0].PSObject.Properties.Name | Should -Contain 'ItemType'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Status'
            $result[0].PSObject.Properties.Name | Should -Contain 'Details'
        }

        It 'should include transport rule action in details' {
            $result = & $script:ScriptPath
            $rule = $result | Where-Object { $_.ItemType -eq 'TransportRule' }
            $rule.Details | Should -Match 'ApplyDisclaimer'
        }

        It 'should show total item count across all types' {
            $result = & $script:ScriptPath
            # 2 domains + 1 inbound + 1 outbound + 1 transport rule = 5
            @($result).Count | Should -Be 5
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @([PSCustomObject]@{ DomainName = 'contoso.com'; DomainType = 'Authoritative'; Default = $true }) }
            Mock Get-InboundConnector { return @() }
            Mock Get-OutboundConnector { return @() }
            Mock Get-TransportRule { return @() }
            $script:csvOutputPath = Join-Path $TestDrive 'test-mailflow.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported mail flow report'
        }
    }

    Context 'when no connectors exist' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @([PSCustomObject]@{ DomainName = 'contoso.com'; DomainType = 'Authoritative'; Default = $true }) }
            Mock Get-InboundConnector { return @() }
            Mock Get-OutboundConnector { return @() }
            Mock Get-TransportRule { return @() }
        }

        It 'should still return domain entries' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
            @($result).Count | Should -Be 1
            $result[0].ItemType | Should -Be 'Domain'
        }
    }

    Context 'when inbound connector retrieval fails' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @([PSCustomObject]@{ DomainName = 'contoso.com'; DomainType = 'Authoritative'; Default = $true }) }
            Mock Get-InboundConnector { throw 'Permission denied' }
            Mock Get-OutboundConnector { return @() }
            Mock Get-TransportRule { return @() }
        }

        It 'should still return results without inbound connectors' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $inbound = @($result | Where-Object { $_.ItemType -eq 'InboundConnector' })
            $inbound.Count | Should -Be 0
        }
    }

    Context 'when outbound connector retrieval fails' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @([PSCustomObject]@{ DomainName = 'contoso.com'; DomainType = 'Authoritative'; Default = $true }) }
            Mock Get-InboundConnector { return @() }
            Mock Get-OutboundConnector { throw 'Timeout' }
            Mock Get-TransportRule { return @() }
        }

        It 'should still return results without outbound connectors' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $outbound = @($result | Where-Object { $_.ItemType -eq 'OutboundConnector' })
            $outbound.Count | Should -Be 0
        }
    }

    Context 'when transport rule retrieval fails' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @([PSCustomObject]@{ DomainName = 'contoso.com'; DomainType = 'Authoritative'; Default = $true }) }
            Mock Get-InboundConnector { return @() }
            Mock Get-OutboundConnector { return @() }
            Mock Get-TransportRule { throw 'Access denied' }
        }

        It 'should still return results without transport rules' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $rules = @($result | Where-Object { $_.ItemType -eq 'TransportRule' })
            $rules.Count | Should -Be 0
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

    Context 'when transport rule has disabled state' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @() }
            Mock Get-InboundConnector { return @() }
            Mock Get-OutboundConnector { return @() }
            Mock Get-TransportRule {
                return @([PSCustomObject]@{
                    Name              = 'Disabled Rule'
                    Priority          = 1
                    Mode              = 'Enforce'
                    State             = 'Disabled'
                    SentTo            = $null
                    SentToMemberOf    = $null
                    FromMemberOf      = $null
                    From              = $null
                    SubjectContainsWords   = $null
                    HasAttachment     = $false
                    AddToRecipients   = $null
                    BlindCopyTo       = $null
                    ModerateMessageByUser  = $null
                    RejectMessageReasonText = $null
                    DeleteMessage     = $false
                    PrependSubject    = $null
                    SetHeaderName     = $null
                    SetHeaderValue    = $null
                    ApplyHtmlDisclaimerText = $null
                })
            }
        }

        It 'should show Disabled status for disabled transport rules' {
            $result = & $script:ScriptPath
            $rule = $result | Where-Object { $_.ItemType -eq 'TransportRule' }
            $rule.Status | Should -Be 'Disabled'
        }
    }

    Context 'when disabled inbound connector exists' {
        BeforeAll {
            Mock Get-AcceptedDomain { return @() }
            Mock Get-InboundConnector {
                return @([PSCustomObject]@{
                    Name                        = 'Disabled Connector'
                    ConnectorType               = 'Partner'
                    Enabled                     = $false
                    RequireTls                  = $false
                    RestrictDomainsToCertificate = $false
                    SenderDomains               = @()
                    SenderIPAddresses           = @()
                    TlsSenderCertificateName    = $null
                })
            }
            Mock Get-OutboundConnector { return @() }
            Mock Get-TransportRule { return @() }
        }

        It 'should show Disabled status for disabled connectors' {
            $result = & $script:ScriptPath
            $connector = $result | Where-Object { $_.ItemType -eq 'InboundConnector' }
            $connector.Status | Should -Be 'Disabled'
        }
    }
}
