BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-AppRegistrationReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgApplication { }
}

Describe 'Get-AppRegistrationReport' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — counts credentials and detects expired ones' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            # Use fixed dates to ensure deterministic expired/valid detection
            $pastDate = (Get-Date).AddDays(-30)
            $futureDate = (Get-Date).AddDays(180)
            $script:PastDate = $pastDate
            $script:FutureDate = $futureDate

            $mockApplications = @(
                # App with mixed credentials: one expired password, one valid certificate
                [PSCustomObject]@{
                    Id              = 'app-1'
                    DisplayName     = 'App With Mixed Creds'
                    AppId           = '11111111-1111-1111-1111-111111111111'
                    CreatedDateTime = '2023-06-01T00:00:00Z'
                    SignInAudience  = 'AzureADMyOrg'
                    PasswordCredentials = @(
                        [PSCustomObject]@{ EndDateTime = $pastDate }
                    )
                    KeyCredentials = @(
                        [PSCustomObject]@{ EndDateTime = $futureDate }
                    )
                }
                # App with only valid password credentials
                [PSCustomObject]@{
                    Id              = 'app-2'
                    DisplayName     = 'App With Valid Creds'
                    AppId           = '22222222-2222-2222-2222-222222222222'
                    CreatedDateTime = '2024-01-15T00:00:00Z'
                    SignInAudience  = 'AzureADMultipleOrgs'
                    PasswordCredentials = @(
                        [PSCustomObject]@{ EndDateTime = $futureDate }
                        [PSCustomObject]@{ EndDateTime = $futureDate.AddDays(90) }
                    )
                    KeyCredentials = @()
                }
                # App with no credentials at all
                [PSCustomObject]@{
                    Id              = 'app-3'
                    DisplayName     = 'App No Creds'
                    AppId           = '33333333-3333-3333-3333-333333333333'
                    CreatedDateTime = '2024-03-20T00:00:00Z'
                    SignInAudience  = 'AzureADandPersonalMicrosoftAccount'
                    PasswordCredentials = $null
                    KeyCredentials = $null
                }
                # App with all expired credentials
                [PSCustomObject]@{
                    Id              = 'app-4'
                    DisplayName     = 'App All Expired'
                    AppId           = '44444444-4444-4444-4444-444444444444'
                    CreatedDateTime = '2022-11-01T00:00:00Z'
                    SignInAudience  = 'AzureADMyOrg'
                    PasswordCredentials = @(
                        [PSCustomObject]@{ EndDateTime = $pastDate.AddDays(-60) }
                    )
                    KeyCredentials = @(
                        [PSCustomObject]@{ EndDateTime = $pastDate.AddDays(-30) }
                    )
                }
            )

            Mock Get-MgApplication { return $mockApplications }
        }

        It 'should return one row per application' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 4
        }

        It 'should count password credentials correctly' {
            $result = & $script:ScriptPath
            $app1 = @($result | Where-Object { $_.DisplayName -eq 'App With Mixed Creds' })[0]
            $app1.PasswordCredentialCount | Should -Be 1

            $app2 = @($result | Where-Object { $_.DisplayName -eq 'App With Valid Creds' })[0]
            $app2.PasswordCredentialCount | Should -Be 2
        }

        It 'should count key credentials correctly' {
            $result = & $script:ScriptPath
            $app1 = @($result | Where-Object { $_.DisplayName -eq 'App With Mixed Creds' })[0]
            $app1.KeyCredentialCount | Should -Be 1
        }

        It 'should detect expired credentials' {
            $result = & $script:ScriptPath
            $app1 = @($result | Where-Object { $_.DisplayName -eq 'App With Mixed Creds' })[0]
            $app1.ExpiredCredentials | Should -Be 1
        }

        It 'should count all expired when everything is expired' {
            $result = & $script:ScriptPath
            $app4 = @($result | Where-Object { $_.DisplayName -eq 'App All Expired' })[0]
            $app4.ExpiredCredentials | Should -Be 2
        }

        It 'should show zero expired for apps with only valid credentials' {
            $result = & $script:ScriptPath
            $app2 = @($result | Where-Object { $_.DisplayName -eq 'App With Valid Creds' })[0]
            $app2.ExpiredCredentials | Should -Be 0
        }

        It 'should report earliest expiry date' {
            $result = & $script:ScriptPath
            $app1 = @($result | Where-Object { $_.DisplayName -eq 'App With Mixed Creds' })[0]
            $app1.EarliestExpiry | Should -Not -BeNullOrEmpty
        }

        It 'should report empty string for EarliestExpiry when no credentials' {
            $result = & $script:ScriptPath
            $app3 = @($result | Where-Object { $_.DisplayName -eq 'App No Creds' })[0]
            $app3.EarliestExpiry | Should -Be ''
        }

        It 'should report zero counts when app has no credentials' {
            $result = & $script:ScriptPath
            $app3 = @($result | Where-Object { $_.DisplayName -eq 'App No Creds' })[0]
            $app3.PasswordCredentialCount | Should -Be 0
            $app3.KeyCredentialCount | Should -Be 0
            $app3.ExpiredCredentials | Should -Be 0
        }

        It 'should include AppId and SignInAudience properties' {
            $result = & $script:ScriptPath
            $app2 = @($result | Where-Object { $_.DisplayName -eq 'App With Valid Creds' })[0]
            $app2.AppId | Should -Be '22222222-2222-2222-2222-222222222222'
            $app2.SignInAudience | Should -Be 'AzureADMultipleOrgs'
        }

        It 'should have all expected properties on each row' {
            $result = & $script:ScriptPath
            $properties = $result[0].PSObject.Properties.Name
            $properties | Should -Contain 'DisplayName'
            $properties | Should -Contain 'AppId'
            $properties | Should -Contain 'CreatedDateTime'
            $properties | Should -Contain 'SignInAudience'
            $properties | Should -Contain 'PasswordCredentialCount'
            $properties | Should -Contain 'KeyCredentialCount'
            $properties | Should -Contain 'EarliestExpiry'
            $properties | Should -Contain 'ExpiredCredentials'
        }

        It 'should sort results by DisplayName' {
            $result = & $script:ScriptPath
            $names = @($result | Select-Object -ExpandProperty DisplayName)
            $names[0] | Should -Be 'App All Expired'
            $names[1] | Should -Be 'App No Creds'
            $names[2] | Should -Be 'App With Mixed Creds'
            $names[3] | Should -Be 'App With Valid Creds'
        }
    }

    Context 'when no app registrations exist (empty results)' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgApplication { return @() }
        }

        It 'should return an empty collection' {
            $result = & $script:ScriptPath
            @($result | Where-Object { $null -ne $_ }).Count | Should -Be 0
        }
    }

    Context 'when not connected to Microsoft Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should write an error about missing connection' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when Get-MgContext throws' {
        BeforeAll {
            Mock Get-MgContext { throw 'Module not loaded' }
        }

        It 'should write an error about missing connection' {
            { & $script:ScriptPath } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when Get-MgApplication fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgApplication { throw 'Insufficient privileges' }
        }

        It 'should write an error about app retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve app registrations*'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgApplication {
                @([PSCustomObject]@{
                    Id              = 'app-test'
                    DisplayName     = 'Test App'
                    AppId           = '55555555-5555-5555-5555-555555555555'
                    CreatedDateTime = '2024-01-01T00:00:00Z'
                    SignInAudience  = 'AzureADMyOrg'
                    PasswordCredentials = @()
                    KeyCredentials = @()
                })
            }
            $script:csvOutputPath = Join-Path $TestDrive 'app-reg.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported app registration report'
        }
    }
}
