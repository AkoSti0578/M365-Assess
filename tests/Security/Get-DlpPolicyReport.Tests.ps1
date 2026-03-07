BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Security/Get-DlpPolicyReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-DlpCompliancePolicy { }
    function Get-DlpComplianceRule { }
    function Get-Label { }
}

Describe 'Get-DlpPolicyReport' {
    BeforeAll {
        # Mock Purview connection check: Get-Label and Get-DlpCompliancePolicy must succeed
        Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-Label' } } -ParameterFilter { $Name -eq 'Get-Label' }
        Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-DlpCompliancePolicy' } } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
        Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-DlpComplianceRule' } } -ParameterFilter { $Name -eq 'Get-DlpComplianceRule' }
    }

    Context 'when all item types are present' {
        BeforeAll {
            # Mock Get-Label for connection check (first call in the script)
            Mock Get-Label {
                return @(
                    [PSCustomObject]@{
                        DisplayName = 'Confidential'
                        Disabled    = $false
                        Priority    = 0
                        Tooltip     = 'Apply to sensitive business data'
                        ParentId    = $null
                        ContentType = 'File, Email'
                    }
                    [PSCustomObject]@{
                        DisplayName = 'Public'
                        Disabled    = $false
                        Priority    = 1
                        Tooltip     = 'No restrictions'
                        ParentId    = $null
                        ContentType = 'File'
                    }
                )
            }

            $mockPolicies = @(
                [PSCustomObject]@{
                    Name              = 'PII Protection Policy'
                    Mode              = 'Enable'
                    Enabled           = $true
                    Priority          = 0
                    ExchangeLocation  = @('All')
                    SharePointLocation = @('All')
                    OneDriveLocation  = @('All')
                    TeamsLocation     = @('All')
                    EndpointDlpLocation = @()
                }
            )
            Mock Get-DlpCompliancePolicy { return $mockPolicies }

            $mockRules = @(
                [PSCustomObject]@{
                    Name                                = 'PII Rule - High Count'
                    Disabled                            = $false
                    Priority                            = 0
                    ParentPolicyName                    = 'PII Protection Policy'
                    BlockAccess                         = $true
                    NotifyUser                          = @('SiteAdmin', 'LastModifier')
                    ContentContainsSensitiveInformation = @(
                        [PSCustomObject]@{ Name = 'U.S. Social Security Number' }
                        [PSCustomObject]@{ Name = 'Credit Card Number' }
                    )
                }
            )
            Mock Get-DlpComplianceRule { return $mockRules }
        }

        It 'should return results containing all item types' {
            $result = & $script:ScriptPath
            $itemTypes = $result | ForEach-Object { $_.ItemType } | Sort-Object -Unique
            $itemTypes | Should -Contain 'DlpPolicy'
            $itemTypes | Should -Contain 'DlpRule'
            $itemTypes | Should -Contain 'SensitivityLabel'
        }

        It 'should return correct number of DLP policies' {
            $result = & $script:ScriptPath
            $policies = @($result | Where-Object { $_.ItemType -eq 'DlpPolicy' })
            $policies.Count | Should -Be 1
        }

        It 'should return correct number of DLP rules' {
            $result = & $script:ScriptPath
            $rules = @($result | Where-Object { $_.ItemType -eq 'DlpRule' })
            $rules.Count | Should -Be 1
        }

        It 'should return correct number of sensitivity labels' {
            $result = & $script:ScriptPath
            $labels = @($result | Where-Object { $_.ItemType -eq 'SensitivityLabel' })
            $labels.Count | Should -Be 2
        }

        It 'should include ItemType, Name, Enabled, Priority, and Details properties' {
            $result = & $script:ScriptPath
            $result[0].PSObject.Properties.Name | Should -Contain 'ItemType'
            $result[0].PSObject.Properties.Name | Should -Contain 'Name'
            $result[0].PSObject.Properties.Name | Should -Contain 'Enabled'
            $result[0].PSObject.Properties.Name | Should -Contain 'Priority'
            $result[0].PSObject.Properties.Name | Should -Contain 'Details'
        }

        It 'should include locations in DLP policy details' {
            $result = & $script:ScriptPath
            $policy = $result | Where-Object { $_.ItemType -eq 'DlpPolicy' }
            $policy.Details | Should -Match 'Exchange'
            $policy.Details | Should -Match 'SharePoint'
            $policy.Details | Should -Match 'OneDrive'
            $policy.Details | Should -Match 'Teams'
        }

        It 'should include mode in DLP policy details' {
            $result = & $script:ScriptPath
            $policy = $result | Where-Object { $_.ItemType -eq 'DlpPolicy' }
            $policy.Details | Should -Match 'Mode=Enable'
        }

        It 'should include sensitive info types in DLP rule details' {
            $result = & $script:ScriptPath
            $rule = $result | Where-Object { $_.ItemType -eq 'DlpRule' }
            $rule.Details | Should -Match 'U.S. Social Security Number'
            $rule.Details | Should -Match 'Credit Card Number'
        }

        It 'should include BlockAccess in DLP rule details' {
            $result = & $script:ScriptPath
            $rule = $result | Where-Object { $_.ItemType -eq 'DlpRule' }
            $rule.Details | Should -Match 'BlockAccess=True'
        }

        It 'should include tooltip in sensitivity label details' {
            $result = & $script:ScriptPath
            $label = $result | Where-Object { $_.Name -eq 'Confidential' }
            $label.Details | Should -Match 'Apply to sensitive business data'
        }

        It 'should mark enabled labels correctly' {
            $result = & $script:ScriptPath
            $label = $result | Where-Object { $_.Name -eq 'Confidential' }
            $label.Enabled | Should -Be $true
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            Mock Get-Label {
                return @([PSCustomObject]@{
                    DisplayName = 'Test'; Disabled = $false; Priority = 0
                    Tooltip = 'Test label'; ParentId = $null; ContentType = 'File'
                })
            }
            Mock Get-DlpCompliancePolicy { return @() }
            Mock Get-DlpComplianceRule { return @() }
            $script:csvOutputPath = Join-Path $TestDrive 'test-dlp.csv'
        }

        It 'should export results to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported.*DLP/label items'
        }
    }

    Context 'when DLP compliance policy cmdlet is not available' {
        BeforeAll {
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-DlpComplianceRule' } } -ParameterFilter { $Name -eq 'Get-DlpComplianceRule' }

            Mock Get-Label {
                return @([PSCustomObject]@{
                    DisplayName = 'Test Label'; Disabled = $false; Priority = 0
                    Tooltip = 'Test'; ParentId = $null; ContentType = 'File'
                })
            }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should skip DLP policies and still return labels' {
            $result = & $script:ScriptPath 3>$null
            $dlpPolicies = @($result | Where-Object { $_.ItemType -eq 'DlpPolicy' })
            $dlpPolicies.Count | Should -Be 0
            $labels = @($result | Where-Object { $_.ItemType -eq 'SensitivityLabel' })
            $labels.Count | Should -Be 1
        }
    }

    Context 'when DLP compliance rule cmdlet is not available' {
        BeforeAll {
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-DlpCompliancePolicy' } } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-DlpComplianceRule' }

            Mock Get-Label {
                return @([PSCustomObject]@{
                    DisplayName = 'Test Label'; Disabled = $false; Priority = 0
                    Tooltip = 'Test'; ParentId = $null; ContentType = 'File'
                })
            }
            Mock Get-DlpCompliancePolicy { return @() }
        }

        It 'should skip DLP rules and still return labels' {
            $result = & $script:ScriptPath 3>$null
            $dlpRules = @($result | Where-Object { $_.ItemType -eq 'DlpRule' })
            $dlpRules.Count | Should -Be 0
        }
    }

    Context 'when Get-Label cmdlet is not available' {
        BeforeAll {
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-Label' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-DlpCompliancePolicy' } } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
            Mock Get-Command { return [PSCustomObject]@{ Name = 'Get-DlpComplianceRule' } } -ParameterFilter { $Name -eq 'Get-DlpComplianceRule' }

            Mock Get-DlpCompliancePolicy {
                return @([PSCustomObject]@{
                    Name = 'Test Policy'; Mode = 'Enable'; Enabled = $true; Priority = 0
                    ExchangeLocation = @('All'); SharePointLocation = @()
                    OneDriveLocation = @(); TeamsLocation = @(); EndpointDlpLocation = @()
                })
            }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should skip labels and still return DLP policies' {
            $result = & $script:ScriptPath 3>$null
            $labels = @($result | Where-Object { $_.ItemType -eq 'SensitivityLabel' })
            $labels.Count | Should -Be 0
            $policies = @($result | Where-Object { $_.ItemType -eq 'DlpPolicy' })
            $policies.Count | Should -Be 1
        }
    }

    Context 'when Purview is not connected at all' {
        BeforeAll {
            # Both Get-Label and Get-DlpCompliancePolicy cmdlets fail
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-Label' }
            Mock Get-Command { throw 'Command not found' } -ParameterFilter { $Name -eq 'Get-DlpCompliancePolicy' }
        }

        It 'should write an error and return nothing' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Purview*'
        }
    }

    Context 'when no DLP policies, rules, or labels exist' {
        BeforeAll {
            Mock Get-Label { return @() }
            Mock Get-DlpCompliancePolicy { return @() }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should return nothing and issue a warning' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when DLP policy retrieval fails at runtime' {
        BeforeAll {
            Mock Get-Label {
                return @([PSCustomObject]@{
                    DisplayName = 'Fallback Label'; Disabled = $false; Priority = 0
                    Tooltip = 'Test'; ParentId = $null; ContentType = 'File'
                })
            }
            Mock Get-DlpCompliancePolicy { throw 'Access denied' }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should handle the error and still return labels' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -Not -BeNullOrEmpty
            $labels = @($result | Where-Object { $_.ItemType -eq 'SensitivityLabel' })
            $labels.Count | Should -Be 1
        }
    }

    Context 'when sensitivity label is disabled' {
        BeforeAll {
            Mock Get-Label {
                return @([PSCustomObject]@{
                    DisplayName = 'Retired Label'; Disabled = $true; Priority = 5
                    Tooltip = 'No longer in use'; ParentId = $null; ContentType = 'File'
                })
            }
            Mock Get-DlpCompliancePolicy { return @() }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should mark the label as disabled' {
            $result = & $script:ScriptPath
            $label = $result | Where-Object { $_.Name -eq 'Retired Label' }
            $label.Enabled | Should -Be $false
        }
    }

    Context 'when DLP rule is disabled' {
        BeforeAll {
            Mock Get-Label { return @() }
            Mock Get-DlpCompliancePolicy { return @() }
            Mock Get-DlpComplianceRule {
                return @([PSCustomObject]@{
                    Name                                = 'Disabled Rule'
                    Disabled                            = $true
                    Priority                            = 0
                    ParentPolicyName                    = 'Test Policy'
                    BlockAccess                         = $false
                    NotifyUser                          = $null
                    ContentContainsSensitiveInformation = $null
                })
            }
        }

        It 'should mark the rule as disabled' {
            $result = & $script:ScriptPath
            $rule = $result | Where-Object { $_.Name -eq 'Disabled Rule' }
            $rule.Enabled | Should -Be $false
        }
    }

    Context 'when sensitivity label has a parent' {
        BeforeAll {
            Mock Get-Label {
                return @([PSCustomObject]@{
                    DisplayName = 'Sub-Label'
                    Disabled    = $false
                    Priority    = 2
                    Tooltip     = 'A sub-label'
                    ParentId    = 'parent-guid-1234'
                    ContentType = 'File, Email'
                })
            }
            Mock Get-DlpCompliancePolicy { return @() }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should include ParentId in label details' {
            $result = & $script:ScriptPath
            $label = $result | Where-Object { $_.Name -eq 'Sub-Label' }
            $label.Details | Should -Match 'ParentId=parent-guid-1234'
        }
    }

    Context 'when DLP policy has no locations configured' {
        BeforeAll {
            Mock Get-Label { return @() }
            Mock Get-DlpCompliancePolicy {
                return @([PSCustomObject]@{
                    Name = 'Empty Policy'; Mode = 'Enable'; Enabled = $true; Priority = 0
                    ExchangeLocation = @(); SharePointLocation = @()
                    OneDriveLocation = @(); TeamsLocation = @(); EndpointDlpLocation = @()
                })
            }
            Mock Get-DlpComplianceRule { return @() }
        }

        It 'should show Locations=None in details' {
            $result = & $script:ScriptPath
            $policy = $result | Where-Object { $_.ItemType -eq 'DlpPolicy' }
            $policy.Details | Should -Match 'Locations=None'
        }
    }
}
