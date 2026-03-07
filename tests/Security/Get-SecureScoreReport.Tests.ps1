BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Security/Get-SecureScoreReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgSecuritySecureScore { }
}

Describe 'Get-SecureScoreReport' {
    BeforeAll {
        Mock Import-Module { }
        # Mock Graph connection check
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when Secure Score data is available' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 42.5
                MaxScore                 = 100
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @(
                    [PSCustomObject]@{
                        Basis        = 'AllTenants'
                        AverageScore = 55.3
                    }
                )
                ControlScores = @(
                    [PSCustomObject]@{
                        ControlName      = 'MFARegistrationV2'
                        Score            = 10
                        ScoreInPercentage = 5.0
                        AdditionalProperties = @{
                            controlCategory      = 'Identity'
                            implementationStatus = 'Implemented'
                            userImpact           = 'Low'
                            threats              = @('AccountBreach', 'DataExfiltration')
                            maxScore             = 10
                        }
                    }
                    [PSCustomObject]@{
                        ControlName      = 'BlockLegacyAuthentication'
                        Score            = 0
                        ScoreInPercentage = 3.0
                        AdditionalProperties = @{
                            controlCategory      = 'Identity'
                            implementationStatus = 'NotImplemented'
                            userImpact           = 'Moderate'
                            threats              = @('AccountBreach')
                            maxScore             = 8
                        }
                    }
                )
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
        }

        It 'should return a score summary object' {
            $result = & $script:ScriptPath
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should include CurrentScore property' {
            $result = & $script:ScriptPath
            $result.CurrentScore | Should -Be 42.5
        }

        It 'should include MaxScore property' {
            $result = & $script:ScriptPath
            $result.MaxScore | Should -Be 100
        }

        It 'should calculate percentage correctly' {
            $result = & $script:ScriptPath
            $result.Percentage | Should -Be 42.5
        }

        It 'should include AverageComparativeScore' {
            $result = & $script:ScriptPath
            $result.AverageComparativeScore | Should -Be 55.3
        }

        It 'should include CreatedDateTime' {
            $result = & $script:ScriptPath
            $result.CreatedDateTime | Should -Be '2026-03-01T00:00:00Z'
        }

        It 'should include expected summary properties' {
            $result = & $script:ScriptPath
            $result.PSObject.Properties.Name | Should -Contain 'CurrentScore'
            $result.PSObject.Properties.Name | Should -Contain 'MaxScore'
            $result.PSObject.Properties.Name | Should -Contain 'Percentage'
            $result.PSObject.Properties.Name | Should -Contain 'CreatedDateTime'
            $result.PSObject.Properties.Name | Should -Contain 'AverageComparativeScore'
        }
    }

    Context 'when ImprovementActionsPath is specified' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 60
                MaxScore                 = 100
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @(
                    [PSCustomObject]@{ Basis = 'AllTenants'; AverageScore = 50 }
                )
                ControlScores = @(
                    [PSCustomObject]@{
                        ControlName      = 'EnableMFA'
                        Score            = 10
                        ScoreInPercentage = 5.0
                        AdditionalProperties = @{
                            controlCategory      = 'Identity'
                            implementationStatus = 'Implemented'
                            userImpact           = 'Low'
                            threats              = @('AccountBreach')
                            maxScore             = 10
                        }
                    }
                )
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
            $script:csvActionsPath = Join-Path $TestDrive 'test-actions.csv'
        }

        It 'should export improvement actions to the specified path' {
            $null = & $script:ScriptPath -ImprovementActionsPath $script:csvActionsPath
            Test-Path $script:csvActionsPath | Should -BeTrue
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 75
                MaxScore                 = 100
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @(
                    [PSCustomObject]@{ Basis = 'AllTenants'; AverageScore = 50 }
                )
                ControlScores = @()
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
            $script:csvScorePath = Join-Path $TestDrive 'test-score.csv'
        }

        It 'should export score summary to CSV' {
            $null = & $script:ScriptPath -OutputPath $script:csvScorePath
            Test-Path $script:csvScorePath | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvScorePath
            $result | Should -Match 'Exported Secure Score summary'
        }
    }

    Context 'when both OutputPath and ImprovementActionsPath are specified' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 80
                MaxScore                 = 100
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @(
                    [PSCustomObject]@{ Basis = 'AllTenants'; AverageScore = 55 }
                )
                ControlScores = @(
                    [PSCustomObject]@{
                        ControlName      = 'TestControl'
                        Score            = 5
                        ScoreInPercentage = 2.5
                        AdditionalProperties = @{
                            controlCategory = 'Data'
                            implementationStatus = 'Planned'
                            userImpact = 'High'
                            threats = 'DataExfiltration'
                            maxScore = 10
                        }
                    }
                )
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
            $script:csvBothScorePath = Join-Path $TestDrive 'test-both-score.csv'
            $script:csvBothActionsPath = Join-Path $TestDrive 'test-both-actions.csv'
        }

        It 'should export both summary and improvement actions CSV files' {
            $null = & $script:ScriptPath -OutputPath $script:csvBothScorePath -ImprovementActionsPath $script:csvBothActionsPath
            Test-Path $script:csvBothScorePath | Should -BeTrue
            Test-Path $script:csvBothActionsPath | Should -BeTrue
        }

        It 'should return messages about both exports' {
            $result = & $script:ScriptPath -OutputPath $script:csvBothScorePath -ImprovementActionsPath $script:csvBothActionsPath
            $result | Should -Not -BeNullOrEmpty
            ($result -join ' ') | Should -Match 'Exported Secure Score summary'
            ($result -join ' ') | Should -Match 'improvement actions'
        }
    }

    Context 'when no Secure Score data is found' {
        BeforeAll {
            Mock Get-MgSecuritySecureScore { return $null }
        }

        It 'should return nothing and issue a warning' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when Get-MgSecuritySecureScore returns an empty array' {
        BeforeAll {
            Mock Get-MgSecuritySecureScore { return @() }
        }

        It 'should return nothing and issue a warning' {
            $result = & $script:ScriptPath 3>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when Get-MgSecuritySecureScore fails' {
        BeforeAll {
            Mock Get-MgSecuritySecureScore { throw 'Insufficient privileges' }
        }

        It 'should write an error and return nothing' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve Secure Score*'
        }
    }

    Context 'when not connected to Microsoft Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should write an error and return nothing' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when Get-MgContext throws' {
        BeforeAll {
            Mock Get-MgContext { throw 'Module not loaded' }
        }

        It 'should write an error and return nothing' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when MaxScore is zero' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 0
                MaxScore                 = 0
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @()
                ControlScores            = @()
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
        }

        It 'should set percentage to 0 when MaxScore is zero' {
            $result = & $script:ScriptPath
            $result.Percentage | Should -Be 0
        }
    }

    Context 'when no AverageComparativeScores exist' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 50
                MaxScore                 = 100
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @()
                ControlScores            = @()
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
        }

        It 'should default AverageComparativeScore to 0' {
            $result = & $script:ScriptPath
            $result.AverageComparativeScore | Should -Be 0
        }
    }

    Context 'when ControlScores have no AdditionalProperties' {
        BeforeAll {
            $mockScore = [PSCustomObject]@{
                CurrentScore             = 30
                MaxScore                 = 100
                CreatedDateTime          = '2026-03-01T00:00:00Z'
                AverageComparativeScores = @(
                    [PSCustomObject]@{ Basis = 'AllTenants'; AverageScore = 40 }
                )
                ControlScores = @(
                    [PSCustomObject]@{
                        ControlName      = 'MinimalControl'
                        Score            = 5
                        ScoreInPercentage = $null
                        AdditionalProperties = $null
                    }
                )
            }
            Mock Get-MgSecuritySecureScore { return $mockScore }
            $script:csvMinimalActionsPath = Join-Path $TestDrive 'test-minimal-actions.csv'
        }

        It 'should handle missing AdditionalProperties with N/A defaults' {
            $null = & $script:ScriptPath -ImprovementActionsPath $script:csvMinimalActionsPath
            Test-Path $script:csvMinimalActionsPath | Should -BeTrue
        }
    }
}
