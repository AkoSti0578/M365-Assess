BeforeAll {
    . (Join-Path $PSScriptRoot '../../Entra/Get-InactiveUsers.ps1')
}

Describe 'Get-InactiveUsers' {
    BeforeAll {
        Mock Get-MgContext { return @{ TenantId = '00000000-0000-0000-0000-000000000000' } }
    }

    Context 'when inactive users are found' {
        BeforeAll {
            $mockUsers = @(
                [PSCustomObject]@{
                    Id = '1'
                    DisplayName = 'John Smith'
                    UserPrincipalName = 'jsmith@contoso.com'
                    UserType = 'Member'
                    AccountEnabled = $true
                    CreatedDateTime = (Get-Date).AddYears(-1)
                    SignInActivity = [PSCustomObject]@{
                        LastSignInDateTime = (Get-Date).AddDays(-120)
                        LastNonInteractiveSignInDateTime = (Get-Date).AddDays(-100)
                    }
                }
                [PSCustomObject]@{
                    Id = '2'
                    DisplayName = 'Jane Doe'
                    UserPrincipalName = 'jdoe@contoso.com'
                    UserType = 'Member'
                    AccountEnabled = $true
                    CreatedDateTime = (Get-Date).AddYears(-2)
                    SignInActivity = [PSCustomObject]@{
                        LastSignInDateTime = $null
                        LastNonInteractiveSignInDateTime = $null
                    }
                }
            )
            Mock Get-MgUser { return $mockUsers }
        }

        It 'should return inactive users' {
            $result = Get-InactiveUsers -DaysInactive 90
            $result | Should -Not -BeNullOrEmpty
        }

        It 'should include expected properties' {
            $result = Get-InactiveUsers -DaysInactive 90
            $result[0].PSObject.Properties.Name | Should -Contain 'DisplayName'
            $result[0].PSObject.Properties.Name | Should -Contain 'UserPrincipalName'
            $result[0].PSObject.Properties.Name | Should -Contain 'DaysSinceActivity'
            $result[0].PSObject.Properties.Name | Should -Contain 'LastSignIn'
        }

        It 'should include users who have never signed in' {
            $result = Get-InactiveUsers -DaysInactive 90
            $neverSignedIn = $result | Where-Object { $_.DaysSinceActivity -eq 'Never' }
            $neverSignedIn | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when IncludeGuests is not set' {
        BeforeAll {
            Mock Get-MgUser { return @() }
        }

        It 'should filter to Member users only' {
            $null = Get-InactiveUsers -DaysInactive 90
            Should -Invoke Get-MgUser -Times 1 -Exactly -ParameterFilter {
                $Filter -match "userType eq 'Member'"
            }
        }
    }

    Context 'when IncludeGuests is set' {
        BeforeAll {
            Mock Get-MgUser { return @() }
        }

        It 'should not filter by userType' {
            $null = Get-InactiveUsers -DaysInactive 90 -IncludeGuests
            Should -Invoke Get-MgUser -Times 1 -Exactly -ParameterFilter {
                $Filter -notmatch "userType"
            }
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockUsers = @(
                [PSCustomObject]@{
                    Id = '1'; DisplayName = 'Test User'
                    UserPrincipalName = 'test@contoso.com'
                    UserType = 'Member'; AccountEnabled = $true
                    CreatedDateTime = (Get-Date).AddYears(-1)
                    SignInActivity = [PSCustomObject]@{
                        LastSignInDateTime = (Get-Date).AddDays(-120)
                        LastNonInteractiveSignInDateTime = $null
                    }
                }
            )
            Mock Get-MgUser { return $mockUsers }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Get-InactiveUsers -DaysInactive 90 -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'when not connected to Graph' {
        BeforeAll {
            Mock Get-MgContext { return $null }
        }

        It 'should throw an error' {
            { Get-InactiveUsers -DaysInactive 90 } | Should -Throw '*Not connected to Microsoft Graph*'
        }
    }

    Context 'when Graph query fails' {
        BeforeAll {
            Mock Get-MgUser { throw 'Insufficient privileges' }
        }

        It 'should throw an error' {
            { Get-InactiveUsers -DaysInactive 90 } | Should -Throw '*Failed to query users*'
        }
    }

    Context 'parameter validation' {
        It 'should reject DaysInactive of 0' {
            { Get-InactiveUsers -DaysInactive 0 } | Should -Throw
        }

        It 'should reject DaysInactive over 365' {
            { Get-InactiveUsers -DaysInactive 400 } | Should -Throw
        }
    }
}
