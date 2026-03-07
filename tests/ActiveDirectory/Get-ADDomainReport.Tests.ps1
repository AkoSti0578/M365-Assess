BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../ActiveDirectory/Get-ADDomainReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-ADDomain { }
    function Get-ADForest { }
    function Get-ADReplicationSite { }
    function Get-ADReplicationSubnet { }
    function Get-ADTrust { }
}

Describe 'Get-ADDomainReport' {
    BeforeAll {
        # Mock the ActiveDirectory module availability and Import-Module
        Mock Get-Module { return @{ Name = 'ActiveDirectory' } } -ParameterFilter {
            $Name -eq 'ActiveDirectory' -and $ListAvailable
        }
        Mock Import-Module { }
        Mock Write-Warning { }
    }

    Context 'when all AD data is available (happy path)' {
        BeforeAll {
            $mockDomain = [PSCustomObject]@{
                DNSRoot              = 'contoso.com'
                DistinguishedName    = 'DC=contoso,DC=com'
                NetBIOSName          = 'CONTOSO'
                DomainMode           = 'Windows2016Domain'
                PDCEmulator          = 'DC01.contoso.com'
                RIDMaster            = 'DC01.contoso.com'
                InfrastructureMaster = 'DC01.contoso.com'
            }
            Mock Get-ADDomain { return $mockDomain }

            $mockForest = [PSCustomObject]@{
                Name                = 'contoso.com'
                RootDomain          = 'DC=contoso,DC=com'
                ForestMode          = 'Windows2016Forest'
                SchemaMaster        = 'DC01.contoso.com'
                DomainNamingMaster  = 'DC01.contoso.com'
                GlobalCatalogs      = @('DC01.contoso.com', 'DC02.contoso.com')
                Domains             = @('contoso.com')
                Sites               = @('Default-First-Site-Name', 'Branch-Office')
            }
            Mock Get-ADForest { return $mockForest }

            $mockSites = @(
                [PSCustomObject]@{
                    Name              = 'Default-First-Site-Name'
                    DistinguishedName = 'CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
                }
                [PSCustomObject]@{
                    Name              = 'Branch-Office'
                    DistinguishedName = 'CN=Branch-Office,CN=Sites,CN=Configuration,DC=contoso,DC=com'
                }
            )
            Mock Get-ADReplicationSite { return $mockSites }

            Mock Get-ADReplicationSubnet {
                return @([PSCustomObject]@{ Name = '10.0.0.0/24' })
            }

            $mockTrusts = @(
                [PSCustomObject]@{
                    Name                      = 'partner.com'
                    DistinguishedName         = 'CN=partner.com,CN=System,DC=contoso,DC=com'
                    Direction                 = 3
                    TrustType                 = 2
                    SelectiveAuthentication   = $false
                    ForestTransitive          = $true
                }
            )
            Mock Get-ADTrust { return $mockTrusts }
        }

        It 'should return records for all four types' {
            $result = & $script:ScriptPath
            $recordTypes = @($result | ForEach-Object { $_.RecordType } | Sort-Object -Unique)
            $recordTypes | Should -Contain 'Domain'
            $recordTypes | Should -Contain 'Forest'
            $recordTypes | Should -Contain 'Site'
            $recordTypes | Should -Contain 'Trust'
        }

        It 'should return exactly one Domain record' {
            $result = & $script:ScriptPath
            $domains = @($result | Where-Object { $_.RecordType -eq 'Domain' })
            $domains.Count | Should -Be 1
        }

        It 'should return exactly one Forest record' {
            $result = & $script:ScriptPath
            $forests = @($result | Where-Object { $_.RecordType -eq 'Forest' })
            $forests.Count | Should -Be 1
        }

        It 'should return two Site records' {
            $result = & $script:ScriptPath
            $sites = @($result | Where-Object { $_.RecordType -eq 'Site' })
            $sites.Count | Should -Be 2
        }

        It 'should return one Trust record' {
            $result = & $script:ScriptPath
            $trusts = @($result | Where-Object { $_.RecordType -eq 'Trust' })
            $trusts.Count | Should -Be 1
        }

        It 'should populate Domain properties correctly' {
            $result = & $script:ScriptPath
            $domain = $result | Where-Object { $_.RecordType -eq 'Domain' }
            $domain.Name | Should -Be 'contoso.com'
            $domain.NetBIOSName | Should -Be 'CONTOSO'
            $domain.FunctionalLevel | Should -Be 'Windows2016Domain'
            $domain.PDCEmulator | Should -Be 'DC01.contoso.com'
            $domain.RIDMaster | Should -Be 'DC01.contoso.com'
            $domain.InfrastructureMaster | Should -Be 'DC01.contoso.com'
        }

        It 'should populate Forest detail with FSMO roles and catalogs' {
            $result = & $script:ScriptPath
            $forest = $result | Where-Object { $_.RecordType -eq 'Forest' }
            $forest.FunctionalLevel | Should -Be 'Windows2016Forest'
            $forest.Detail | Should -Match 'SchemaMaster=DC01.contoso.com'
            $forest.Detail | Should -Match 'DomainNamingMaster=DC01.contoso.com'
            $forest.Detail | Should -Match 'GlobalCatalogs=DC01.contoso.com'
        }

        It 'should populate Trust detail with direction and type' {
            $result = & $script:ScriptPath
            $trust = $result | Where-Object { $_.RecordType -eq 'Trust' }
            $trust.Name | Should -Be 'partner.com'
            $trust.Detail | Should -Match 'Direction=Bidirectional'
            $trust.Detail | Should -Match 'SelectiveAuth=False'
        }

        It 'should include expected properties on all records' {
            $result = & $script:ScriptPath
            $expectedProps = @('RecordType', 'Name', 'DistinguishedName', 'NetBIOSName',
                              'FunctionalLevel', 'PDCEmulator', 'RIDMaster',
                              'InfrastructureMaster', 'Detail')
            foreach ($record in $result) {
                foreach ($prop in $expectedProps) {
                    $record.PSObject.Properties.Name | Should -Contain $prop
                }
            }
        }
    }

    Context 'when there are no trust relationships' {
        BeforeAll {
            Mock Get-ADDomain { return [PSCustomObject]@{
                DNSRoot = 'contoso.com'; DistinguishedName = 'DC=contoso,DC=com'
                NetBIOSName = 'CONTOSO'; DomainMode = 'Windows2016Domain'
                PDCEmulator = 'DC01.contoso.com'; RIDMaster = 'DC01.contoso.com'
                InfrastructureMaster = 'DC01.contoso.com'
            }}
            Mock Get-ADForest { return [PSCustomObject]@{
                Name = 'contoso.com'; RootDomain = 'DC=contoso,DC=com'
                ForestMode = 'Windows2016Forest'; SchemaMaster = 'DC01.contoso.com'
                DomainNamingMaster = 'DC01.contoso.com'
                GlobalCatalogs = @('DC01.contoso.com'); Domains = @('contoso.com')
                Sites = @('Default-First-Site-Name')
            }}
            Mock Get-ADReplicationSite { return @([PSCustomObject]@{
                Name = 'Default-First-Site-Name'
                DistinguishedName = 'CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
            })}
            Mock Get-ADReplicationSubnet { return $null }
            Mock Get-ADTrust { return $null }
        }

        It 'should return Domain, Forest, and Site records but no Trust' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
            $trusts = @($result | Where-Object { $_.RecordType -eq 'Trust' })
            $trusts.Count | Should -Be 0
        }

        It 'should still have Domain and Forest records' {
            $result = & $script:ScriptPath
            $domains = @($result | Where-Object { $_.RecordType -eq 'Domain' })
            $domains.Count | Should -Be 1
            $forests = @($result | Where-Object { $_.RecordType -eq 'Forest' })
            $forests.Count | Should -Be 1
        }
    }

    Context 'when Get-ADTrust fails (partial failure)' {
        BeforeAll {
            Mock Get-ADDomain { return [PSCustomObject]@{
                DNSRoot = 'contoso.com'; DistinguishedName = 'DC=contoso,DC=com'
                NetBIOSName = 'CONTOSO'; DomainMode = 'Windows2016Domain'
                PDCEmulator = 'DC01.contoso.com'; RIDMaster = 'DC01.contoso.com'
                InfrastructureMaster = 'DC01.contoso.com'
            }}
            Mock Get-ADForest { return [PSCustomObject]@{
                Name = 'contoso.com'; RootDomain = 'DC=contoso,DC=com'
                ForestMode = 'Windows2016Forest'; SchemaMaster = 'DC01.contoso.com'
                DomainNamingMaster = 'DC01.contoso.com'
                GlobalCatalogs = @('DC01.contoso.com'); Domains = @('contoso.com')
                Sites = @('Default-First-Site-Name')
            }}
            Mock Get-ADReplicationSite { return @([PSCustomObject]@{
                Name = 'Default-First-Site-Name'
                DistinguishedName = 'CN=Default-First-Site-Name,CN=Sites,CN=Configuration,DC=contoso,DC=com'
            })}
            Mock Get-ADReplicationSubnet { return $null }
            Mock Get-ADTrust { throw 'Access denied' }
        }

        It 'should still return Domain and Forest records' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $domains = @($result | Where-Object { $_.RecordType -eq 'Domain' })
            $domains.Count | Should -Be 1
        }

        It 'should emit a warning about trust failure' {
            & $script:ScriptPath 3>$null
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
                $Message -match 'trust'
            }
        }
    }

    Context 'when Get-ADForest fails (partial failure)' {
        BeforeAll {
            Mock Get-ADDomain { return [PSCustomObject]@{
                DNSRoot = 'contoso.com'; DistinguishedName = 'DC=contoso,DC=com'
                NetBIOSName = 'CONTOSO'; DomainMode = 'Windows2016Domain'
                PDCEmulator = 'DC01.contoso.com'; RIDMaster = 'DC01.contoso.com'
                InfrastructureMaster = 'DC01.contoso.com'
            }}
            Mock Get-ADForest { throw 'Access denied' }
            Mock Get-ADReplicationSite { return @() }
            Mock Get-ADReplicationSubnet { return $null }
            Mock Get-ADTrust { return $null }
        }

        It 'should still return the Domain record' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $domains = @($result | Where-Object { $_.RecordType -eq 'Domain' })
            $domains.Count | Should -Be 1
        }
    }

    Context 'when ActiveDirectory module is not available' {
        BeforeAll {
            Mock Get-Module { return $null } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
        }

        It 'should throw an error about missing module' {
            { & $script:ScriptPath } | Should -Throw '*ActiveDirectory module*'
        }
    }

    Context 'when Get-ADDomain fails (cannot contact DC)' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'ActiveDirectory' } } -ParameterFilter {
                $Name -eq 'ActiveDirectory' -and $ListAvailable
            }
            Mock Get-ADDomain { throw 'Unable to contact domain controller' }
        }

        It 'should throw an error about domain query failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to query AD domain*'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-ADDomain { return [PSCustomObject]@{
                DNSRoot = 'contoso.com'; DistinguishedName = 'DC=contoso,DC=com'
                NetBIOSName = 'CONTOSO'; DomainMode = 'Windows2016Domain'
                PDCEmulator = 'DC01.contoso.com'; RIDMaster = 'DC01.contoso.com'
                InfrastructureMaster = 'DC01.contoso.com'
            }}
            Mock Get-ADForest { return [PSCustomObject]@{
                Name = 'contoso.com'; RootDomain = 'DC=contoso,DC=com'
                ForestMode = 'Windows2016Forest'; SchemaMaster = 'DC01.contoso.com'
                DomainNamingMaster = 'DC01.contoso.com'
                GlobalCatalogs = @('DC01.contoso.com'); Domains = @('contoso.com')
                Sites = @('Default-First-Site-Name')
            }}
            Mock Get-ADReplicationSite { return @() }
            Mock Get-ADTrust { return $null }
            $script:csvOutputPath = Join-Path $TestDrive 'test-domain-report.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported.*AD domain topology records'
        }
    }
}
