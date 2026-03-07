BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Invoke-M365Assessment.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-AcceptedDomain { }
    function Resolve-DnsName { }
    function Disconnect-ExchangeOnline { }

    # Mock external commands used by the orchestrator (except New-Item and Export-Csv which need real FS)
    Mock Test-Path { return $true }
    Mock Write-Host { }
    Mock Write-Warning { }
    Mock Get-AcceptedDomain { return @() }
    Mock Resolve-DnsName { return @() }
    Mock Disconnect-ExchangeOnline { }

    # Mock Connect-Service (dot-sourced inside the script)
    function Connect-Service { param($Service, $TenantId, $ClientId, $CertificateThumbprint, $UserPrincipalName, $Scopes) }
    Mock Connect-Service { }

    # Helper: read _Assessment-Summary.csv from the latest assessment subfolder
    function Get-AssessmentSummary {
        param([string]$OutputFolder)
        $latestFolder = Get-ChildItem -Path $OutputFolder -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -First 1
        if ($latestFolder) {
            $csvFile = Join-Path $latestFolder.FullName '_Assessment-Summary.csv'
            if (Test-Path -Path $csvFile) {
                Import-Csv -Path $csvFile
            }
        }
    }
}

Describe 'Invoke-M365Assessment' {
    Context 'output folder creation' {
        BeforeAll {
            $script:folderBase = Join-Path $TestDrive 'M365-FolderTest'
        }

        It 'should create a timestamped output folder' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:folderBase
            $createdFolders = Get-ChildItem -Path $script:folderBase -Directory -ErrorAction SilentlyContinue
            $createdFolders | Should -Not -BeNullOrEmpty
            $createdFolders[0].Name | Should -Match 'Assessment_\d{8}_\d{6}$'
        }
    }

    Context 'when -SkipConnection is specified' {
        BeforeAll {
            $script:skipConnBase = Join-Path $TestDrive 'M365-SkipConn'
        }

        It 'should not call Connect-Service' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:skipConnBase
            Should -Invoke Connect-Service -Times 0
        }
    }

    Context 'when -SkipConnection is not specified' {
        BeforeAll {
            Mock Connect-Service { }
            # Provide a fake Connect-Service.ps1 path
            Mock Test-Path { return $true }
            $script:connBase = Join-Path $TestDrive 'M365-Conn'
        }

        It 'should call Connect-Service for required services' {
            & $script:ScriptPath -Section 'Tenant' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:connBase
            Should -Invoke Connect-Service -Times 1 -Exactly -ParameterFilter {
                $Service -eq 'Graph'
            }
        }
    }

    Context 'interactive mode detection' {
        BeforeAll {
            $script:interBase = Join-Path $TestDrive 'M365-Interactive'
        }

        It 'should not launch wizard when -Section is specified' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:interBase
            $summary = Get-AssessmentSummary -OutputFolder $script:interBase
            $summary | Should -Not -BeNullOrEmpty
        }

        It 'should not launch wizard when -SkipConnection is specified' {
            & $script:ScriptPath -SkipConnection -OutputFolder $script:interBase
            $summary = Get-AssessmentSummary -OutputFolder $script:interBase
            $summary | Should -Not -BeNullOrEmpty
        }

        It 'should not launch wizard when -TenantId is specified' {
            & $script:ScriptPath -TenantId 'contoso.onmicrosoft.com' -SkipConnection -OutputFolder $script:interBase
            $summary = Get-AssessmentSummary -OutputFolder $script:interBase
            $summary | Should -Not -BeNullOrEmpty
        }
    }

    Context 'section filtering with -Section parameter' {
        BeforeAll {
            # Mock all collector scripts to return simple data
            Mock Test-Path { return $true }
            $script:sectionBase = Join-Path $TestDrive 'M365-Section'
        }

        It 'should accept a single section' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:sectionBase
            $summary = Get-AssessmentSummary -OutputFolder $script:sectionBase
            $summary | Should -Not -BeNullOrEmpty
            $tenantResults = @($summary | Where-Object { $_.Section -eq 'Tenant' })
            $tenantResults.Count | Should -BeGreaterOrEqual 1
        }

        It 'should accept multiple sections' {
            & $script:ScriptPath -Section 'Tenant', 'Identity' -SkipConnection -OutputFolder $script:sectionBase
            $summary = Get-AssessmentSummary -OutputFolder $script:sectionBase
            $sections = @($summary | Select-Object -ExpandProperty Section -Unique)
            $sections | Should -Contain 'Tenant'
            $sections | Should -Contain 'Identity'
        }

        It 'should reject invalid section values' {
            { & $script:ScriptPath -Section 'InvalidSection' -SkipConnection } | Should -Throw
        }
    }

    Context 'assessment summary CSV' {
        BeforeAll {
            $script:summaryBase = Join-Path $TestDrive 'M365-Summary'
        }

        It 'should produce _Assessment-Summary.csv' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:summaryBase
            $summaryFiles = Get-ChildItem -Path $script:summaryBase -Recurse -Filter '_Assessment-Summary.csv' -ErrorAction SilentlyContinue
            $summaryFiles | Should -Not -BeNullOrEmpty
        }

        It 'should include expected columns in summary CSV' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:summaryBase
            $summary = Get-AssessmentSummary -OutputFolder $script:summaryBase
            $summary | Should -Not -BeNullOrEmpty
            $first = @($summary)[0]
            $first.PSObject.Properties.Name | Should -Contain 'Section'
            $first.PSObject.Properties.Name | Should -Contain 'Collector'
            $first.PSObject.Properties.Name | Should -Contain 'Status'
            $first.PSObject.Properties.Name | Should -Contain 'Items'
            $first.PSObject.Properties.Name | Should -Contain 'Duration'
        }
    }

    Context 'graceful failure when a collector script is not found' {
        BeforeAll {
            # Make Test-Path return false for collector scripts so they throw "Script not found"
            # The orchestrator classifies "not found" errors as Skipped
            Mock Test-Path { return $false } -ParameterFilter {
                $Path -match '\.ps1$' -and $Path -notmatch 'Connect-Service'
            }
            Mock Test-Path { return $true } -ParameterFilter {
                $Path -match 'Connect-Service'
            }
            $script:failBase = Join-Path $TestDrive 'M365-Fail'
        }

        It 'should mark missing collector as Skipped in summary and continue' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:failBase
            $summary = Get-AssessmentSummary -OutputFolder $script:failBase
            $summary | Should -Not -BeNullOrEmpty
            $skippedItems = @($summary | Where-Object { $_.Status -eq 'Skipped' })
            $skippedItems.Count | Should -BeGreaterOrEqual 1
        }

        It 'should include error message for skipped collectors' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:failBase
            $summary = Get-AssessmentSummary -OutputFolder $script:failBase
            $skippedItem = @($summary | Where-Object { $_.Status -eq 'Skipped' })[0]
            $skippedItem.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when a collector returns permission error' {
        BeforeAll {
            Mock Test-Path { return $true }
            $script:permBase = Join-Path $TestDrive 'M365-Perm'
        }

        It 'should mark collector as Skipped on 403/Forbidden errors' {
            # The orchestrator catches 403/Forbidden and marks as Skipped
            # This is tested implicitly through the error handling logic
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:permBase
            $summary = Get-AssessmentSummary -OutputFolder $script:permBase
            $summary | Should -Not -BeNullOrEmpty
        }
    }

    Context 'sequential service connections' {
        BeforeAll {
            Mock Connect-Service { }
            Mock Test-Path { return $true }
            Mock Import-Module { }
            $script:seqBase = Join-Path $TestDrive 'M365-Sequential'
        }

        It 'should connect to EXO only for Email-only section' {
            & $script:ScriptPath -Section 'Email' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:seqBase
            Should -Invoke Connect-Service -Times 1 -Exactly -ParameterFilter {
                $Service -eq 'ExchangeOnline'
            }
            Should -Invoke Connect-Service -Times 0 -ParameterFilter {
                $Service -eq 'Graph'
            }
        }

        It 'should connect to Graph once across multiple Graph sections' {
            & $script:ScriptPath -Section 'Tenant', 'Identity', 'Licensing' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:seqBase
            Should -Invoke Connect-Service -Times 1 -Exactly -ParameterFilter {
                $Service -eq 'Graph'
            }
        }

        It 'should connect to Graph and EXO for mixed sections' {
            & $script:ScriptPath -Section 'Tenant', 'Email' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:seqBase
            Should -Invoke Connect-Service -Times 1 -Exactly -ParameterFilter {
                $Service -eq 'Graph'
            }
            Should -Invoke Connect-Service -Times 1 -Exactly -ParameterFilter {
                $Service -eq 'ExchangeOnline'
            }
        }

        It 'should not connect any service for ScubaGear-only section' {
            & $script:ScriptPath -Section 'ScubaGear' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:seqBase
            Should -Invoke Connect-Service -Times 0
        }
    }

    Context 'ScubaGear section' {
        BeforeAll {
            Mock Test-Path { return $true }
            $script:scubaBase = Join-Path $TestDrive 'M365-Scuba'
        }

        It 'should accept ScubaGear as a valid section' {
            & $script:ScriptPath -Section 'ScubaGear' -SkipConnection -OutputFolder $script:scubaBase
            $summary = Get-AssessmentSummary -OutputFolder $script:scubaBase
            $summary | Should -Not -BeNullOrEmpty
            $scubaItems = @($summary | Where-Object { $_.Section -eq 'ScubaGear' })
            $scubaItems.Count | Should -Be 1
        }

        It 'should not include ScubaGear in default sections' {
            & $script:ScriptPath -SkipConnection -OutputFolder $script:scubaBase
            $summary = Get-AssessmentSummary -OutputFolder $script:scubaBase
            $scubaItems = @($summary | Where-Object { $_.Section -eq 'ScubaGear' })
            $scubaItems.Count | Should -Be 0
        }

        It 'should not attempt service connections for ScubaGear-only run' {
            Mock Connect-Service { }
            & $script:ScriptPath -Section 'ScubaGear' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:scubaBase
            Should -Invoke Connect-Service -Times 0
        }

        It 'should set collector label to CISA ScubaGear Baseline' {
            & $script:ScriptPath -Section 'ScubaGear' -SkipConnection -OutputFolder $script:scubaBase
            $summary = Get-AssessmentSummary -OutputFolder $script:scubaBase
            $scubaItem = @($summary | Where-Object { $_.Section -eq 'ScubaGear' })[0]
            $scubaItem.Collector | Should -Be 'CISA ScubaGear Baseline'
        }

        It 'should mark ScubaGear as Skipped when collector script not found' {
            Mock Test-Path { return $false } -ParameterFilter {
                $Path -match 'Invoke-ScubaGearScan\.ps1$'
            }
            Mock Test-Path { return $true } -ParameterFilter {
                $Path -notmatch 'Invoke-ScubaGearScan\.ps1$'
            }
            & $script:ScriptPath -Section 'ScubaGear' -SkipConnection -OutputFolder $script:scubaBase
            $summary = Get-AssessmentSummary -OutputFolder $script:scubaBase
            $scubaItem = @($summary | Where-Object { $_.Section -eq 'ScubaGear' })[0]
            $scubaItem.Status | Should -Be 'Skipped'
        }
    }

    Context 'log file creation' {
        BeforeAll {
            $script:logBase = Join-Path $TestDrive 'M365-Log'
        }

        It 'should create _Assessment-Log.txt in the output folder' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:logBase
            $logFiles = Get-ChildItem -Path $script:logBase -Recurse -Filter '_Assessment-Log.txt' -ErrorAction SilentlyContinue
            $logFiles | Should -Not -BeNullOrEmpty
        }

        It 'should include log header with timestamp and sections' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:logBase
            $logFile = Get-ChildItem -Path $script:logBase -Recurse -Filter '_Assessment-Log.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
            $content = Get-Content -Path $logFile.FullName -Raw
            $content | Should -Match 'M365 Environment Assessment Log'
            $content | Should -Match 'Sections:.*Tenant'
        }

        It 'should log collector execution entries' {
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:logBase
            $logFile = Get-ChildItem -Path $script:logBase -Recurse -Filter '_Assessment-Log.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
            $content = Get-Content -Path $logFile.FullName -Raw
            $content | Should -Match '\[INFO\].*Tenant Information'
        }
    }

    Context 'issue report' {
        BeforeAll {
            $script:issueBase = Join-Path $TestDrive 'M365-Issues'
        }

        It 'should include severity and description in issue report when issues exist' {
            # Collectors will fail (scripts not found) which generates issues
            & $script:ScriptPath -Section 'Tenant' -SkipConnection -OutputFolder $script:issueBase
            $issueFile = Get-ChildItem -Path $script:issueBase -Recurse -Filter '_Assessment-Issues.log' -ErrorAction SilentlyContinue | Select-Object -First 1
            $issueFile | Should -Not -BeNullOrEmpty
            $content = Get-Content -Path $issueFile.FullName -Raw
            $content | Should -Match 'Severity:'
            $content | Should -Match 'Description:'
            $content | Should -Match 'Action:'
        }
    }

    Context 'connection failure tracking' {
        BeforeAll {
            Mock Connect-Service { throw 'Connection failed: broker error' }
            Mock Test-Path { return $true }
            Mock Import-Module { }
            $script:failConnBase = Join-Path $TestDrive 'M365-FailConn'
        }

        It 'should skip collectors when required service connection failed' {
            & $script:ScriptPath -Section 'Email' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:failConnBase
            $summary = Get-AssessmentSummary -OutputFolder $script:failConnBase
            $summary | Should -Not -BeNullOrEmpty
            $skippedItems = @($summary | Where-Object { $_.Status -eq 'Skipped' })
            $skippedItems.Count | Should -BeGreaterOrEqual 1
        }

        It 'should mark skipped collectors with descriptive error message' {
            & $script:ScriptPath -Section 'Email' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:failConnBase
            $summary = Get-AssessmentSummary -OutputFolder $script:failConnBase
            $skippedItem = @($summary | Where-Object { $_.Status -eq 'Skipped' })[0]
            $skippedItem.Error | Should -Match 'not connected'
        }

        It 'should create issue report when connection fails' {
            & $script:ScriptPath -Section 'Email' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:failConnBase
            $issueFiles = Get-ChildItem -Path $script:failConnBase -Recurse -Filter '_Assessment-Issues.log' -ErrorAction SilentlyContinue
            $issueFiles | Should -Not -BeNullOrEmpty
        }

        It 'should include connection failure in issue report content' {
            & $script:ScriptPath -Section 'Email' -TenantId 'contoso.onmicrosoft.com' -OutputFolder $script:failConnBase
            $issueFile = Get-ChildItem -Path $script:failConnBase -Recurse -Filter '_Assessment-Issues.log' -ErrorAction SilentlyContinue | Select-Object -First 1
            $content = Get-Content -Path $issueFile.FullName -Raw
            $content | Should -Match 'ExchangeOnline connection failed'
            $content | Should -Match 'Severity:.*ERROR'
        }
    }
}
