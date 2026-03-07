BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Common/Export-AssessmentReport.ps1'
}

Describe 'Export-AssessmentReport' {
    BeforeAll {
        Mock Write-Output { }
        Mock Write-Verbose { }
    }

    Context 'parameter validation' {
        It 'should require AssessmentFolder parameter' {
            $cmd = Get-Command $script:ScriptPath
            $param = $cmd.Parameters['AssessmentFolder']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -Not -BeNullOrEmpty
        }

        It 'should have optional TenantName parameter' {
            $cmd = Get-Command $script:ScriptPath
            $cmd.Parameters['TenantName'] | Should -Not -BeNullOrEmpty
        }

        It 'should have optional SkipPdf switch' {
            $cmd = Get-Command $script:ScriptPath
            $cmd.Parameters['SkipPdf'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when assessment folder contains CIS-mapped security config CSVs' {
        BeforeAll {
            # Create mock assessment folder
            $script:assessDir = Join-Path $TestDrive 'Assessment_20260306_120000'
            New-Item -Path $script:assessDir -ItemType Directory -Force | Out-Null

            # Create summary CSV with security config collector
            $summaryData = @(
                [PSCustomObject]@{
                    Section   = 'Identity'
                    Collector = 'Entra Security Config'
                    Status    = 'Complete'
                    Items     = '5'
                    Duration  = '1.2s'
                    FileName  = '15-Entra-Security-Config.csv'
                    Error     = ''
                }
                [PSCustomObject]@{
                    Section   = 'Tenant'
                    Collector = 'Tenant Information'
                    Status    = 'Complete'
                    Items     = '1'
                    Duration  = '0.5s'
                    FileName  = '01-Tenant-Info.csv'
                    Error     = ''
                }
            )
            $summaryData | Export-Csv -Path (Join-Path $script:assessDir '_Assessment-Summary.csv') -NoTypeInformation

            # Create CIS-mapped security config CSV
            $secConfigData = @(
                [PSCustomObject]@{
                    Category         = 'Security Defaults'
                    Setting          = 'Security Defaults Enabled'
                    CurrentValue     = 'True'
                    RecommendedValue = 'True (if no CA)'
                    Status           = 'Pass'
                    CisControl       = '5.1.1.1'
                    Remediation      = 'Enable security defaults in Entra.'
                }
                [PSCustomObject]@{
                    Category         = 'Admin Accounts'
                    Setting          = 'Global Administrator Count'
                    CurrentValue     = '8'
                    RecommendedValue = '2-4'
                    Status           = 'Warning'
                    CisControl       = '1.1.3'
                    Remediation      = 'Reduce global admins to 2-4.'
                }
                [PSCustomObject]@{
                    Category         = 'Application Consent'
                    Setting          = 'User Consent for Applications'
                    CurrentValue     = 'Allow user consent (legacy)'
                    RecommendedValue = 'Do not allow user consent'
                    Status           = 'Warning'
                    CisControl       = '5.3.1'
                    Remediation      = 'Disable user consent for applications.'
                }
                [PSCustomObject]@{
                    Category         = 'Application Consent'
                    Setting          = 'Users Can Register Applications'
                    CurrentValue     = 'True'
                    RecommendedValue = 'False'
                    Status           = 'Fail'
                    CisControl       = '5.3.2'
                    Remediation      = 'Set to No in Entra user settings.'
                }
                [PSCustomObject]@{
                    Category         = 'Conditional Access'
                    Setting          = 'Total CA Policies'
                    CurrentValue     = '3'
                    RecommendedValue = '1+'
                    Status           = 'Pass'
                    CisControl       = '5.1.2.1'
                    Remediation      = 'Create CA policies.'
                }
            )
            $secConfigData | Export-Csv -Path (Join-Path $script:assessDir '15-Entra-Security-Config.csv') -NoTypeInformation

            # Create tenant info CSV (no CIS columns)
            $tenantData = @(
                [PSCustomObject]@{
                    OrgDisplayName = 'Contoso Ltd'
                    DefaultDomain  = 'contoso.onmicrosoft.com'
                    TenantId       = '00000000-0000-0000-0000-000000000000'
                }
            )
            $tenantData | Export-Csv -Path (Join-Path $script:assessDir '01-Tenant-Info.csv') -NoTypeInformation

            # Run the report generator
            $outputPath = Join-Path $script:assessDir '_Assessment-Report.html'
            & $script:ScriptPath -AssessmentFolder $script:assessDir -OutputPath $outputPath -SkipPdf -TenantName 'Contoso Ltd'

            $script:htmlContent = Get-Content -Path $outputPath -Raw
        }

        It 'should generate an HTML report file' {
            Test-Path -Path (Join-Path $script:assessDir '_Assessment-Report.html') | Should -BeTrue
        }

        It 'should include CIS Compliance Summary section' {
            $script:htmlContent | Should -Match 'CIS Compliance Summary'
        }

        It 'should include CIS Benchmark reference text' {
            $script:htmlContent | Should -Match 'CIS Microsoft 365 Foundations Benchmark v6.0.1'
        }

        It 'should show CIS L1 Score card' {
            $script:htmlContent | Should -Match 'CIS L1 Score'
        }

        It 'should include Areas of Improvement heading' {
            $script:htmlContent | Should -Match 'Areas of Improvement'
        }

        It 'should display CIS control IDs' {
            $script:htmlContent | Should -Match '5\.3\.2'  # The Fail control
            $script:htmlContent | Should -Match '1\.1\.3'  # A Warning control
        }

        It 'should include remediation guidance' {
            $script:htmlContent | Should -Match 'Remediation'
        }

        It 'should include CIS reference link in executive summary' {
            $script:htmlContent | Should -Match 'CIS Microsoft 365'
            $script:htmlContent | Should -Match 'finding\(s\)'
            $script:htmlContent | Should -Match 'attention'
        }

        It 'should include cisecurity.org reference' {
            $script:htmlContent | Should -Match 'cisecurity\.org'
        }

        It 'should calculate correct non-passing count' {
            # 3 non-passing: 1 Fail + 2 Warning
            $script:htmlContent | Should -Match '3 finding'
        }
    }

    Context 'when CIS findings have Unknown status' {
        BeforeAll {
            $script:unknownDir = Join-Path $TestDrive 'Assessment_Unknown'
            New-Item -Path $script:unknownDir -ItemType Directory -Force | Out-Null

            $summaryData = @(
                [PSCustomObject]@{
                    Section   = 'Identity'
                    Collector = 'Entra Security Config'
                    Status    = 'Complete'
                    Items     = '1'
                    Duration  = '0.8s'
                    FileName  = '15-Entra-Security-Config.csv'
                    Error     = ''
                }
            )
            $summaryData | Export-Csv -Path (Join-Path $script:unknownDir '_Assessment-Summary.csv') -NoTypeInformation

            $secConfigData = @(
                [PSCustomObject]@{
                    Category         = 'Security Defaults'
                    Setting          = 'Security Defaults Enabled'
                    CurrentValue     = 'Unable to retrieve'
                    RecommendedValue = 'True (if no CA)'
                    Status           = 'Unknown'
                    CisControl       = '5.1.1.1'
                    Remediation      = 'Enable security defaults in Entra.'
                }
            )
            $secConfigData | Export-Csv -Path (Join-Path $script:unknownDir '15-Entra-Security-Config.csv') -NoTypeInformation

            $outputPath = Join-Path $script:unknownDir '_Assessment-Report.html'
            & $script:ScriptPath -AssessmentFolder $script:unknownDir -OutputPath $outputPath -SkipPdf -TenantName 'Unknown Corp'

            $script:unknownHtml = Get-Content -Path $outputPath -Raw
        }

        It 'should show N/A score when all findings are Unknown' {
            $script:unknownHtml | Should -Match 'N/A'
        }

        It 'should show Unknown stat card' {
            $script:unknownHtml | Should -Match 'Unknown'
        }

        It 'should exclude Unknown from score denominator' {
            # Score display should be N/A, not a percentage, when all findings are Unknown
            $script:unknownHtml | Should -Match 'stat-value.*N/A'
        }
    }

    Context 'when assessment folder has no CIS-mapped data' {
        BeforeAll {
            $script:noCisDir = Join-Path $TestDrive 'Assessment_NoCIS'
            New-Item -Path $script:noCisDir -ItemType Directory -Force | Out-Null

            $summaryData = @(
                [PSCustomObject]@{
                    Section   = 'Tenant'
                    Collector = 'Tenant Information'
                    Status    = 'Complete'
                    Items     = '1'
                    Duration  = '0.5s'
                    FileName  = '01-Tenant-Info.csv'
                    Error     = ''
                }
            )
            $summaryData | Export-Csv -Path (Join-Path $script:noCisDir '_Assessment-Summary.csv') -NoTypeInformation

            $tenantData = @(
                [PSCustomObject]@{
                    OrgDisplayName = 'NoCIS Corp'
                    DefaultDomain  = 'nocis.onmicrosoft.com'
                }
            )
            $tenantData | Export-Csv -Path (Join-Path $script:noCisDir '01-Tenant-Info.csv') -NoTypeInformation

            $outputPath = Join-Path $script:noCisDir '_Assessment-Report.html'
            & $script:ScriptPath -AssessmentFolder $script:noCisDir -OutputPath $outputPath -SkipPdf -TenantName 'NoCIS Corp'

            $script:noCisHtml = Get-Content -Path $outputPath -Raw
        }

        It 'should generate the report successfully' {
            Test-Path -Path (Join-Path $script:noCisDir '_Assessment-Report.html') | Should -BeTrue
        }

        It 'should NOT include CIS Compliance Summary section' {
            $script:noCisHtml | Should -Not -Match 'CIS Compliance Summary'
        }
    }
}
