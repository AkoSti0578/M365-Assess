BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Purview/Get-AuditRetentionReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-AdminAuditLogConfig { }
    function Get-UnifiedAuditLogRetentionPolicy { }
}

Describe 'Get-AuditRetentionReport' {
    Context 'when audit config is available and retention policies exist' {
        BeforeAll {
            $mockAuditConfig = [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $true
                AdminAuditLogEnabled            = $true
                AdminAuditLogAgeLimit           = '90.00:00:00'
                AdminAuditLogCmdlets            = @('*')
            }
            Mock Get-AdminAuditLogConfig { return $mockAuditConfig }

            $mockRetentionPolicies = @(
                [PSCustomObject]@{
                    Name              = '10-Year Retention'
                    RetentionDuration = 'TenYears'
                    RecordTypes       = @('ExchangeAdmin', 'SharePoint')
                    Operations        = $null
                    UserIds           = $null
                    Priority          = 1
                    Enabled           = $true
                }
                [PSCustomObject]@{
                    Name              = '1-Year Default'
                    RetentionDuration = 'OneYear'
                    RecordTypes       = $null
                    Operations        = $null
                    UserIds           = $null
                    Priority          = 2
                    Enabled           = $true
                }
            )
            Mock Get-UnifiedAuditLogRetentionPolicy { return $mockRetentionPolicies }
            Mock Get-Command { return @{ Name = 'Get-UnifiedAuditLogRetentionPolicy' } } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
        }

        It 'should return audit config plus retention policy records' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 3
        }

        It 'should have an AuditConfig record' {
            $result = & $script:ScriptPath
            $configRecord = @($result) | Where-Object { $_.ItemType -eq 'AuditConfig' }
            $configRecord | Should -Not -BeNullOrEmpty
            $configRecord.Name | Should -Be 'AdminAuditLogConfig'
        }

        It 'should report UnifiedAuditLogIngestionEnabled' {
            $result = & $script:ScriptPath
            $configRecord = @($result) | Where-Object { $_.ItemType -eq 'AuditConfig' }
            $configRecord.UnifiedAuditLogIngestionEnabled | Should -BeTrue
        }

        It 'should report AdminAuditLogEnabled' {
            $result = & $script:ScriptPath
            $configRecord = @($result) | Where-Object { $_.ItemType -eq 'AuditConfig' }
            $configRecord.AdminAuditLogEnabled | Should -BeTrue
        }

        It 'should include config details with AdminAuditLogAgeLimit' {
            $result = & $script:ScriptPath
            $configRecord = @($result) | Where-Object { $_.ItemType -eq 'AuditConfig' }
            $configRecord.Details | Should -BeLike '*AdminAuditLogAgeLimit=90*'
        }

        It 'should include RetentionPolicy records' {
            $result = & $script:ScriptPath
            $policyRecords = @($result) | Where-Object { $_.ItemType -eq 'RetentionPolicy' }
            $policyRecords.Count | Should -Be 2
        }

        It 'should include retention duration in policy details' {
            $result = & $script:ScriptPath
            $tenYearPolicy = @($result) | Where-Object { $_.Name -eq '10-Year Retention' }
            $tenYearPolicy.Details | Should -BeLike '*RetentionDuration=TenYears*'
        }

        It 'should include record types in policy details' {
            $result = & $script:ScriptPath
            $tenYearPolicy = @($result) | Where-Object { $_.Name -eq '10-Year Retention' }
            $tenYearPolicy.Details | Should -BeLike '*RecordTypes=ExchangeAdmin*'
        }

        It 'should include expected properties on all records' {
            $result = & $script:ScriptPath
            foreach ($record in @($result)) {
                $props = $record.PSObject.Properties.Name
                $props | Should -Contain 'ItemType'
                $props | Should -Contain 'Name'
                $props | Should -Contain 'UnifiedAuditLogIngestionEnabled'
                $props | Should -Contain 'AdminAuditLogEnabled'
                $props | Should -Contain 'Details'
            }
        }
    }

    Context 'when audit config is available but no retention policies exist' {
        BeforeAll {
            $mockAuditConfig = [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $true
                AdminAuditLogEnabled            = $true
                AdminAuditLogAgeLimit           = '90.00:00:00'
                AdminAuditLogCmdlets            = @('*')
            }
            Mock Get-AdminAuditLogConfig { return $mockAuditConfig }
            Mock Get-UnifiedAuditLogRetentionPolicy { return $null }
            Mock Get-Command { return @{ Name = 'Get-UnifiedAuditLogRetentionPolicy' } } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
        }

        It 'should return AuditConfig record plus a placeholder retention record' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 2
        }

        It 'should have a retention policy placeholder showing none configured' {
            $result = & $script:ScriptPath
            $policyRecord = @($result) | Where-Object { $_.ItemType -eq 'RetentionPolicy' }
            $policyRecord.Name | Should -Be '(none configured)'
            $policyRecord.Details | Should -BeLike '*Default retention*'
        }
    }

    Context 'when Get-UnifiedAuditLogRetentionPolicy cmdlet is not available (Purview unavailable)' {
        BeforeAll {
            $mockAuditConfig = [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $true
                AdminAuditLogEnabled            = $true
                AdminAuditLogAgeLimit           = '90.00:00:00'
                AdminAuditLogCmdlets            = @('*')
            }
            Mock Get-AdminAuditLogConfig { return $mockAuditConfig }
            Mock Get-UnifiedAuditLogRetentionPolicy { throw 'Command not found' }
            Mock Get-Command { return $null } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
        }

        It 'should still return the audit config record' {
            $result = & $script:ScriptPath 3>&1 | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
            $result | Should -Not -BeNullOrEmpty
            $configRecord = @($result) | Where-Object { $_.ItemType -eq 'AuditConfig' }
            $configRecord | Should -Not -BeNullOrEmpty
        }

        It 'should emit a warning about Purview unavailability' {
            $allOutput = & $script:ScriptPath 3>&1
            $warnings = $allOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            $warnings | Should -Not -BeNullOrEmpty
            ($warnings | Out-String) | Should -BeLike '*Get-UnifiedAuditLogRetentionPolicy*'
        }
    }

    Context 'when Get-AdminAuditLogConfig fails and cmdlet is not available' {
        BeforeAll {
            Mock Get-AdminAuditLogConfig { throw 'Not connected' }
            Mock Get-Command { return $null } -ParameterFilter {
                $Name -eq 'Get-AdminAuditLogConfig'
            }
        }

        It 'should write an error about missing EXO/Purview connection' {
            { & $script:ScriptPath } | Should -Throw '*Get-AdminAuditLogConfig*'
        }
    }

    Context 'when Get-AdminAuditLogConfig fails but cmdlet exists' {
        BeforeAll {
            Mock Get-AdminAuditLogConfig { throw 'Permission denied' }
            Mock Get-Command { return @{ Name = 'Get-AdminAuditLogConfig' } } -ParameterFilter {
                $Name -eq 'Get-AdminAuditLogConfig'
            }
        }

        It 'should write an error about retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve admin audit log config*'
        }
    }

    Context 'when unified audit log ingestion is disabled' {
        BeforeAll {
            $mockAuditConfig = [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $false
                AdminAuditLogEnabled            = $true
                AdminAuditLogAgeLimit           = '90.00:00:00'
                AdminAuditLogCmdlets            = @('*')
            }
            Mock Get-AdminAuditLogConfig { return $mockAuditConfig }
            Mock Get-UnifiedAuditLogRetentionPolicy { return $null }
            Mock Get-Command { return @{ Name = 'Get-UnifiedAuditLogRetentionPolicy' } } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
        }

        It 'should report UnifiedAuditLogIngestionEnabled as false' {
            $result = & $script:ScriptPath
            $configRecord = @($result) | Where-Object { $_.ItemType -eq 'AuditConfig' }
            $configRecord.UnifiedAuditLogIngestionEnabled | Should -BeFalse
        }
    }

    Context 'when retention policy has Identity instead of Name' {
        BeforeAll {
            $mockAuditConfig = [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $true
                AdminAuditLogEnabled            = $true
                AdminAuditLogAgeLimit           = '90.00:00:00'
                AdminAuditLogCmdlets            = @('*')
            }
            Mock Get-AdminAuditLogConfig { return $mockAuditConfig }

            $mockRetentionPolicies = @(
                [PSCustomObject]@{
                    Identity          = 'IdentityBasedPolicy'
                    RetentionDuration = 'SixMonths'
                    RecordTypes       = $null
                    Operations        = @('FileAccessed')
                    UserIds           = @('admin@contoso.com')
                    Priority          = 5
                    Enabled           = $true
                }
            )
            Mock Get-UnifiedAuditLogRetentionPolicy { return $mockRetentionPolicies }
            Mock Get-Command { return @{ Name = 'Get-UnifiedAuditLogRetentionPolicy' } } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
        }

        It 'should use Identity as the policy name' {
            $result = & $script:ScriptPath
            $policyRecord = @($result) | Where-Object { $_.ItemType -eq 'RetentionPolicy' }
            $policyRecord.Name | Should -Be 'IdentityBasedPolicy'
        }

        It 'should include Operations in details' {
            $result = & $script:ScriptPath
            $policyRecord = @($result) | Where-Object { $_.ItemType -eq 'RetentionPolicy' }
            $policyRecord.Details | Should -BeLike '*Operations=FileAccessed*'
        }

        It 'should include UserIds in details' {
            $result = & $script:ScriptPath
            $policyRecord = @($result) | Where-Object { $_.ItemType -eq 'RetentionPolicy' }
            $policyRecord.Details | Should -BeLike '*UserIds=admin@contoso.com*'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockAuditConfig = [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $true
                AdminAuditLogEnabled            = $true
                AdminAuditLogAgeLimit           = '90.00:00:00'
                AdminAuditLogCmdlets            = @('*')
            }
            Mock Get-AdminAuditLogConfig { return $mockAuditConfig }
            Mock Get-UnifiedAuditLogRetentionPolicy { return $null }
            Mock Get-Command { return @{ Name = 'Get-UnifiedAuditLogRetentionPolicy' } } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
            $script:csvOutputPath = Join-Path $TestDrive 'audit-retention.csv'
        }

        It 'should export results to a CSV file' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -BeLike 'Exported audit retention report*'
        }
    }

    Context 'parameter validation' {
        BeforeAll {
            Mock Get-AdminAuditLogConfig { return [PSCustomObject]@{
                UnifiedAuditLogIngestionEnabled = $true
                AdminAuditLogEnabled = $true
            } }
            Mock Get-UnifiedAuditLogRetentionPolicy { return $null }
            Mock Get-Command { return @{ Name = 'Get-UnifiedAuditLogRetentionPolicy' } } -ParameterFilter {
                $Name -eq 'Get-UnifiedAuditLogRetentionPolicy'
            }
        }

        It 'should reject empty string for OutputPath' {
            { & $script:ScriptPath -OutputPath '' } | Should -Throw
        }
    }
}
