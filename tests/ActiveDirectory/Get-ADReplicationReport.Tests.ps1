BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../ActiveDirectory/Get-ADReplicationReport.ps1'

    # Stub functions for AD cmdlets not present in the session (need params for ParameterFilter)
    function Get-ADDomainController { param($Identity, $Filter) }
    function Get-ADReplicationPartnerMetadata { param($Target) }
    function Get-ADReplicationFailure { param($Target) }
    function Get-ADReplicationSiteLink { param($Filter) }
}

Describe 'Get-ADReplicationReport' {
    BeforeAll {
        Mock Import-Module { }
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } }
    }

    Context 'healthy replication with two DCs' {
        BeforeAll {
            $mockDCs = @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Default-First-Site-Name'; IPv4Address = '10.0.0.1' }
                [PSCustomObject]@{ HostName = 'DC02.contoso.com'; Site = 'Default-First-Site-Name'; IPv4Address = '10.0.0.2' }
            )
            Mock Get-ADDomainController { return $mockDCs }

            $now = Get-Date
            $mockPartners = @(
                [PSCustomObject]@{
                    Partner                        = 'CN=NTDS Settings,CN=DC02,CN=Servers,CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
                    PartnerType                    = 'Inbound'
                    LastReplicationAttempt          = $now
                    LastReplicationSuccess          = $now
                    LastReplicationResult           = 0
                    ConsecutiveReplicationFailures  = 0
                }
            )
            Mock Get-ADReplicationPartnerMetadata { return $mockPartners }
            Mock Get-ADReplicationFailure { return @() }

            $mockSiteLinks = @(
                [PSCustomObject]@{
                    Name                          = 'DEFAULTIPSITELINK'
                    SitesIncluded                 = @('CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com')
                    Cost                          = 100
                    ReplicationFrequencyInMinutes  = 180
                }
            )
            Mock Get-ADReplicationSiteLink { return $mockSiteLinks }
        }

        It 'should return replication partner records' {
            $result = & $script:ScriptPath
            $partnerRecords = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })
            $partnerRecords.Count | Should -BeGreaterOrEqual 1
        }

        It 'should include expected properties' {
            $result = & $script:ScriptPath
            $first = @($result)[0]
            $first.PSObject.Properties.Name | Should -Contain 'RecordType'
            $first.PSObject.Properties.Name | Should -Contain 'DomainController'
            $first.PSObject.Properties.Name | Should -Contain 'Partner'
            $first.PSObject.Properties.Name | Should -Contain 'ReplicationStatus'
            $first.PSObject.Properties.Name | Should -Contain 'ConsecutiveFailures'
        }

        It 'should report Healthy status for zero failures and result 0' {
            $result = & $script:ScriptPath
            $partnerRecords = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })
            $partnerRecords[0].ReplicationStatus | Should -Be 'Healthy'
        }

        It 'should return site link records' {
            $result = & $script:ScriptPath
            $siteLinks = @($result | Where-Object { $_.RecordType -eq 'SiteLink' })
            $siteLinks.Count | Should -Be 1
            $siteLinks[0].Partner | Should -Be 'DEFAULTIPSITELINK'
        }

        It 'should include cost and frequency in site link detail' {
            $result = & $script:ScriptPath
            $siteLink = @($result | Where-Object { $_.RecordType -eq 'SiteLink' })[0]
            $siteLink.Detail | Should -Match 'Cost=100'
            $siteLink.Detail | Should -Match 'ReplicationFrequency=180min'
        }
    }

    Context 'when replication has consecutive failures' {
        BeforeAll {
            $mockDCs = @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Site1'; IPv4Address = '10.0.0.1' }
            )
            Mock Get-ADDomainController { return $mockDCs }

            $now = Get-Date
            $mockPartners = @(
                [PSCustomObject]@{
                    Partner                        = 'DC02'
                    PartnerType                    = 'Inbound'
                    LastReplicationAttempt          = $now
                    LastReplicationSuccess          = $now.AddHours(-2)
                    LastReplicationResult           = 8524
                    ConsecutiveReplicationFailures  = 5
                }
            )
            Mock Get-ADReplicationPartnerMetadata { return $mockPartners }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should report Error status for many failures' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.ReplicationStatus | Should -Be 'Error'
        }

        It 'should include failure count in detail' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.Detail | Should -Match 'ConsecutiveFailures=5'
        }

        It 'should include result code in detail' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.Detail | Should -Match 'LastResultCode=8524'
        }
    }

    Context 'when replication lag exceeds 24 hours' {
        BeforeAll {
            $mockDCs = @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Site1'; IPv4Address = '10.0.0.1' }
            )
            Mock Get-ADDomainController { return $mockDCs }

            $now = Get-Date
            $mockPartners = @(
                [PSCustomObject]@{
                    Partner                        = 'DC02'
                    PartnerType                    = 'Inbound'
                    LastReplicationAttempt          = $now
                    LastReplicationSuccess          = $now.AddHours(-48)
                    LastReplicationResult           = 0
                    ConsecutiveReplicationFailures  = 0
                }
            )
            Mock Get-ADReplicationPartnerMetadata { return $mockPartners }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should report Error status for excessive lag' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.ReplicationStatus | Should -Be 'Error'
        }

        It 'should include lag duration in detail' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.Detail | Should -Match 'ReplicationLag='
        }
    }

    Context 'when replication failure history exists' {
        BeforeAll {
            $mockDCs = @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Site1'; IPv4Address = '10.0.0.1' }
            )
            Mock Get-ADDomainController { return $mockDCs }

            $now = Get-Date
            $mockPartners = @(
                [PSCustomObject]@{
                    Partner                        = 'DC02'
                    PartnerType                    = 'Inbound'
                    LastReplicationAttempt          = $now
                    LastReplicationSuccess          = $now
                    LastReplicationResult           = 0
                    ConsecutiveReplicationFailures  = 0
                }
            )
            Mock Get-ADReplicationPartnerMetadata { return $mockPartners }

            $mockFailures = @(
                [PSCustomObject]@{
                    Partner          = 'DC02'
                    FirstFailureTime = $now.AddDays(-3)
                    FailureCount     = 12
                    FailureType      = 'KCC'
                    LastError        = 1256
                }
            )
            Mock Get-ADReplicationFailure { return $mockFailures }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should include ReplicationFailure records' {
            $result = & $script:ScriptPath
            $failures = @($result | Where-Object { $_.RecordType -eq 'ReplicationFailure' })
            $failures.Count | Should -Be 1
        }

        It 'should report failure count and type' {
            $result = & $script:ScriptPath
            $failure = @($result | Where-Object { $_.RecordType -eq 'ReplicationFailure' })[0]
            $failure.ConsecutiveFailures | Should -Be 12
            $failure.Detail | Should -Match 'FailureType=KCC'
        }
    }

    Context 'when specific DomainController parameter is provided' {
        BeforeAll {
            Mock Get-ADDomainController {
                return [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Site1'; IPv4Address = '10.0.0.1' }
            } -ParameterFilter { $Identity -eq 'DC01' }

            $now = Get-Date
            Mock Get-ADReplicationPartnerMetadata {
                return @([PSCustomObject]@{
                    Partner                        = 'DC02'
                    PartnerType                    = 'Inbound'
                    LastReplicationAttempt          = $now
                    LastReplicationSuccess          = $now
                    LastReplicationResult           = 0
                    ConsecutiveReplicationFailures  = 0
                })
            }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should query only the specified DC' {
            & $script:ScriptPath -DomainController 'DC01'
            Should -Invoke Get-ADDomainController -Times 1 -Exactly -ParameterFilter { $Identity -eq 'DC01' }
        }
    }

    Context 'when Get-ADReplicationPartnerMetadata fails' {
        BeforeAll {
            $mockDCs = @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Site1'; IPv4Address = '10.0.0.1' }
            )
            Mock Get-ADDomainController { return $mockDCs }
            Mock Get-ADReplicationPartnerMetadata { throw 'Access denied' }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should return a QueryFailed record' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.ReplicationStatus | Should -Be 'QueryFailed'
        }

        It 'should include error detail' {
            $result = & $script:ScriptPath
            $partner = @($result | Where-Object { $_.RecordType -eq 'ReplicationPartner' })[0]
            $partner.Detail | Should -Match 'Failed to query'
        }
    }

    Context 'when no domain controllers are found' {
        BeforeAll {
            Mock Get-ADDomainController { return @() }
        }

        It 'should throw an error about no DCs found' {
            { & $script:ScriptPath } | Should -Throw '*No domain controllers found*'
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
            $mockDCs = @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com'; Site = 'Site1'; IPv4Address = '10.0.0.1' }
            )
            Mock Get-ADDomainController { return $mockDCs }

            $now = Get-Date
            Mock Get-ADReplicationPartnerMetadata {
                return @([PSCustomObject]@{
                    Partner                        = 'DC02'
                    PartnerType                    = 'Inbound'
                    LastReplicationAttempt          = $now
                    LastReplicationSuccess          = $now
                    LastReplicationResult           = 0
                    ConsecutiveReplicationFailures  = 0
                })
            }
            Mock Get-ADReplicationFailure { return @() }
            Mock Get-ADReplicationSiteLink { return @() }
        }

        It 'should export results to CSV' {
            $csvPath = Join-Path $TestDrive 'replication.csv'
            & $script:ScriptPath -OutputPath $csvPath
            Test-Path -Path $csvPath | Should -Be $true
        }

        It 'should return a confirmation message' {
            $csvPath = Join-Path $TestDrive 'replication2.csv'
            $result = & $script:ScriptPath -OutputPath $csvPath
            $result | Should -Match 'Exported.*replication records'
        }
    }
}
