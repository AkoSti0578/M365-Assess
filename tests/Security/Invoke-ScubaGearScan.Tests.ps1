BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Security/Invoke-ScubaGearScan.ps1'

    # Define stub for the PS5 invocation function so the script uses our mock
    function Invoke-PS5Command {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string]$ScriptContent,

            [Parameter()]
            [string]$Description = 'PS5 command'
        )
    }
}

Describe 'Invoke-ScubaGearScan' {
    BeforeAll {
        Mock Write-Host { }
        Mock Invoke-PS5Command { }
    }

    Context 'happy path — parses ScubaGear CSV results' {
        BeforeAll {
            # Create mock ScubaGear output structure in TestDrive
            $script:scubaOutDir = Join-Path $TestDrive 'ScubaOut'
            $script:conformanceDir = Join-Path $script:scubaOutDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:conformanceDir -ItemType Directory -Force

            # Create a fixture ScubaResults CSV
            $csvContent = @(
                [PSCustomObject]@{
                    'Control ID'  = 'MS.AAD.1.1v1'
                    Requirement   = 'Legacy authentication SHALL be blocked'
                    Result        = 'Pass'
                    Criticality   = 'Shall'
                    Details       = 'All legacy auth blocked'
                }
                [PSCustomObject]@{
                    'Control ID'  = 'MS.AAD.2.1v1'
                    Requirement   = 'MFA SHALL be required for all users'
                    Result        = 'Fail'
                    Criticality   = 'Shall'
                    Details       = 'MFA not enforced for 3 users'
                }
                [PSCustomObject]@{
                    'Control ID'  = 'MS.EXO.1.1v1'
                    Requirement   = 'Auto-forwarding SHALL be disabled'
                    Result        = 'Pass'
                    Criticality   = 'Shall'
                    Details       = 'Auto-forwarding disabled'
                }
            )
            $csvContent | Export-Csv -Path (Join-Path $script:conformanceDir 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should return parsed PSCustomObjects from ScubaResults CSV' {
            $result = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:scubaOutDir
            @($result).Count | Should -Be 3
        }

        It 'should preserve CSV column names as object properties' {
            $result = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:scubaOutDir
            $result[0].PSObject.Properties.Name | Should -Contain 'Control ID'
            $result[0].PSObject.Properties.Name | Should -Contain 'Requirement'
            $result[0].PSObject.Properties.Name | Should -Contain 'Result'
            $result[0].PSObject.Properties.Name | Should -Contain 'Criticality'
            $result[0].PSObject.Properties.Name | Should -Contain 'Details'
        }

        It 'should include correct Result values' {
            $result = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:scubaOutDir
            $passCount = @($result | Where-Object { $_.Result -eq 'Pass' }).Count
            $failCount = @($result | Where-Object { $_.Result -eq 'Fail' }).Count
            $passCount | Should -Be 2
            $failCount | Should -Be 1
        }
    }

    Context 'when ScubaGear output folder is not found' {
        BeforeAll {
            # Create an empty output folder with no conformance subfolder
            $script:emptyOutDir = Join-Path $TestDrive 'EmptyOut'
            $null = New-Item -Path $script:emptyOutDir -ItemType Directory -Force
        }

        It 'should throw an error about missing output folder' {
            { & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:emptyOutDir } |
                Should -Throw '*output folder not found*'
        }
    }

    Context 'when ScubaResults CSV is missing from output' {
        BeforeAll {
            $script:noCsvDir = Join-Path $TestDrive 'NoCsvOut'
            $script:noCsvConformance = Join-Path $script:noCsvDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:noCsvConformance -ItemType Directory -Force
            # Create the folder but no CSV file inside
        }

        It 'should throw an error about missing CSV' {
            { & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:noCsvDir } |
                Should -Throw '*ScubaResults CSV not found*'
        }
    }

    Context 'when ScubaResults CSV is empty (no data rows)' {
        BeforeAll {
            $script:emptyDataDir = Join-Path $TestDrive 'EmptyDataOut'
            $script:emptyDataConformance = Join-Path $script:emptyDataDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:emptyDataConformance -ItemType Directory -Force

            # Create CSV with only headers
            Set-Content -Path (Join-Path $script:emptyDataConformance 'ScubaResults.csv') -Value '"Control ID","Requirement","Result","Criticality","Details"'
        }

        It 'should return an empty array' {
            $result = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:emptyDataDir
            @($result).Count | Should -Be 0
        }
    }

    Context 'when SkipModuleCheck is not specified' {
        BeforeAll {
            $script:moduleCheckDir = Join-Path $TestDrive 'ModuleCheckOut'
            $script:moduleCheckConformance = Join-Path $script:moduleCheckDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:moduleCheckConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:moduleCheckConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should call Invoke-PS5Command for module setup' {
            $null = & $script:ScriptPath -ScubaOutputPath $script:moduleCheckDir
            Should -Invoke Invoke-PS5Command -Times 2 -Exactly
        }

        It 'should call Invoke-PS5Command with module setup description first' {
            $null = & $script:ScriptPath -ScubaOutputPath $script:moduleCheckDir
            Should -Invoke Invoke-PS5Command -ParameterFilter { $Description -eq 'module setup' } -Times 1
        }
    }

    Context 'when SkipModuleCheck is specified' {
        BeforeAll {
            $script:skipCheckDir = Join-Path $TestDrive 'SkipCheckOut'
            $script:skipCheckConformance = Join-Path $script:skipCheckDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:skipCheckConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:skipCheckConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should call Invoke-PS5Command only once (scan only, no module setup)' {
            $null = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:skipCheckDir
            Should -Invoke Invoke-PS5Command -Times 1 -Exactly
        }

        It 'should call Invoke-PS5Command with scan description' {
            $null = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:skipCheckDir
            Should -Invoke Invoke-PS5Command -ParameterFilter { $Description -eq 'ScubaGear scan' } -Times 1
        }
    }

    Context 'product selection passthrough' {
        BeforeAll {
            $script:productDir = Join-Path $TestDrive 'ProductOut'
            $script:productConformance = Join-Path $script:productDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:productConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:productConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should include selected products in the ScubaGear invocation script' {
            $null = & $script:ScriptPath -SkipModuleCheck -ProductNames aad,exo -ScubaOutputPath $script:productDir
            Should -Invoke Invoke-PS5Command -ParameterFilter { $ScriptContent -match "'aad','exo'" }
        }

        It 'should include all products by default' {
            $null = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:productDir
            Should -Invoke Invoke-PS5Command -ParameterFilter {
                $ScriptContent -match "'aad'" -and
                $ScriptContent -match "'defender'" -and
                $ScriptContent -match "'exo'" -and
                $ScriptContent -match "'powerplatform'" -and
                $ScriptContent -match "'powerbi'" -and
                $ScriptContent -match "'sharepoint'" -and
                $ScriptContent -match "'teams'"
            }
        }
    }

    Context 'certificate auth passthrough' {
        BeforeAll {
            $script:certDir = Join-Path $TestDrive 'CertOut'
            $script:certConformance = Join-Path $script:certDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:certConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:certConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should pass AppID and CertificateThumbprint and disable LogIn' {
            $null = & $script:ScriptPath -SkipModuleCheck -AppId 'test-app-id' -CertificateThumbprint 'ABCDEF123' -ScubaOutputPath $script:certDir
            Should -Invoke Invoke-PS5Command -ParameterFilter {
                $ScriptContent -match 'test-app-id' -and
                $ScriptContent -match 'ABCDEF123' -and
                $ScriptContent -match 'LogIn.*False'
            }
        }
    }

    Context 'M365Environment passthrough' {
        BeforeAll {
            $script:envDir = Join-Path $TestDrive 'EnvOut'
            $script:envConformance = Join-Path $script:envDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:envConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:envConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should pass gcc environment to ScubaGear' {
            $null = & $script:ScriptPath -SkipModuleCheck -M365Environment gcc -ScubaOutputPath $script:envDir
            Should -Invoke Invoke-PS5Command -ParameterFilter { $ScriptContent -match 'gcc' }
        }

        It 'should not include M365Environment when commercial (default)' {
            $null = & $script:ScriptPath -SkipModuleCheck -M365Environment commercial -ScubaOutputPath $script:envDir
            Should -Invoke Invoke-PS5Command -ParameterFilter { $ScriptContent -notmatch 'M365Environment' }
        }
    }

    Context 'Organization passthrough' {
        BeforeAll {
            $script:orgDir = Join-Path $TestDrive 'OrgOut'
            $script:orgConformance = Join-Path $script:orgDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:orgConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:orgConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
        }

        It 'should pass Organization to ScubaGear invocation' {
            $null = & $script:ScriptPath -SkipModuleCheck -Organization 'contoso.onmicrosoft.com' -ScubaOutputPath $script:orgDir
            Should -Invoke Invoke-PS5Command -ParameterFilter { $ScriptContent -match 'contoso\.onmicrosoft\.com' }
        }
    }

    Context 'when Invoke-PS5Command fails during scan' {
        BeforeAll {
            Mock Invoke-PS5Command { throw 'PS5 ScubaGear scan failed (exit code 1): Authentication error' }
        }

        It 'should propagate the error' {
            { & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath (Join-Path $TestDrive 'FailDir') } |
                Should -Throw '*ScubaGear scan failed*'
        }
    }

    Context 'when Invoke-PS5Command fails during module setup' {
        BeforeAll {
            Mock Invoke-PS5Command {
                if ($Description -eq 'module setup') {
                    throw 'PS5 module setup failed (exit code 1): Install-Module failed'
                }
            }
        }

        It 'should propagate the module installation error' {
            { & $script:ScriptPath -ScubaOutputPath (Join-Path $TestDrive 'FailSetupDir') } |
                Should -Throw '*module setup failed*'
        }
    }

    Context 'OutputPath CSV export' {
        BeforeAll {
            $script:csvExportDir = Join-Path $TestDrive 'CsvExportOut'
            $script:csvExportConformance = Join-Path $script:csvExportDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:csvExportConformance -ItemType Directory -Force

            @(
                [PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test1'; Result = 'Pass'; Criticality = 'Shall'; Details = 'OK' }
                [PSCustomObject]@{ 'Control ID' = 'MS.EXO.1.1v1'; Requirement = 'Test2'; Result = 'Fail'; Criticality = 'Should'; Details = 'Issue' }
            ) | Export-Csv -Path (Join-Path $script:csvExportConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8

            Mock Invoke-PS5Command { }

            $script:csvOutputFile = Join-Path $TestDrive 'output.csv'
        }

        It 'should export results to CSV when OutputPath is specified' {
            $null = & $script:ScriptPath -SkipModuleCheck -OutputPath $script:csvOutputFile -ScubaOutputPath $script:csvExportDir
            Test-Path $script:csvOutputFile | Should -BeTrue
        }

        It 'should return a confirmation message' {
            $result = & $script:ScriptPath -SkipModuleCheck -OutputPath $script:csvOutputFile -ScubaOutputPath $script:csvExportDir
            $result | Should -Match 'Exported.*ScubaGear results'
        }
    }

    Context 'parameter validation' {
        It 'should reject invalid product names' {
            { & $script:ScriptPath -SkipModuleCheck -ProductNames 'invalid' -ScubaOutputPath $TestDrive } |
                Should -Throw
        }

        It 'should reject invalid M365Environment values' {
            { & $script:ScriptPath -SkipModuleCheck -M365Environment 'invalid' -ScubaOutputPath $TestDrive } |
                Should -Throw
        }
    }

    Context 'when powershell.exe is not available' {
        BeforeAll {
            Mock Invoke-PS5Command {
                throw "Windows PowerShell 5.1 (powershell.exe) is required for ScubaGear but was not found on this system."
            }
        }

        It 'should throw a clear error about missing powershell.exe' {
            { & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath (Join-Path $TestDrive 'NoPSDir') } |
                Should -Throw '*powershell.exe*required*ScubaGear*'
        }
    }

    Context 'native output copy to separate ScubaOutputPath' {
        BeforeAll {
            # Source: scan produces output in a temp-like folder
            $script:srcDir = Join-Path $TestDrive 'SrcScubaOut'
            $script:srcConformance = Join-Path $script:srcDir 'M365BaselineConformance_2026_03_06'
            $null = New-Item -Path $script:srcConformance -ItemType Directory -Force
            @([PSCustomObject]@{ 'Control ID' = 'MS.AAD.1.1v1'; Requirement = 'Test'; Result = 'Pass'; Criticality = 'Shall'; Details = '' }) |
                Export-Csv -Path (Join-Path $script:srcConformance 'ScubaResults.csv') -NoTypeInformation -Encoding UTF8
            Set-Content -Path (Join-Path $script:srcConformance 'BaselineReports.html') -Value '<html>report</html>'

            Mock Invoke-PS5Command { }
        }

        It 'should preserve native ScubaGear output in the specified folder' {
            $result = & $script:ScriptPath -SkipModuleCheck -ScubaOutputPath $script:srcDir
            Test-Path (Join-Path $script:srcConformance 'BaselineReports.html') | Should -BeTrue
        }
    }
}
