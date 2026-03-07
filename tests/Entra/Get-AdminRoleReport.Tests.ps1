BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Entra/Get-AdminRoleReport.ps1'

    # Define stub functions so Pester can mock cmdlets not present in the session
    function Get-MgContext { }
    function Get-MgDirectoryRole { }
    function Get-MgDirectoryRoleMember { }
}

Describe 'Get-AdminRoleReport' {
    BeforeAll {
        Mock Import-Module { }
    }

    Context 'happy path — returns role-member pairs' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgDirectoryRole {
                @(
                    [PSCustomObject]@{
                        Id          = 'role-1'
                        DisplayName = 'Global Administrator'
                    }
                    [PSCustomObject]@{
                        Id          = 'role-2'
                        DisplayName = 'User Administrator'
                    }
                )
            }

            Mock Get-MgDirectoryRoleMember {
                param($DirectoryRoleId)
                switch ($DirectoryRoleId) {
                    'role-1' {
                        @(
                            [PSCustomObject]@{
                                Id = 'user-1'
                                AdditionalProperties = @{
                                    'displayName'        = 'Alice Admin'
                                    'userPrincipalName'  = 'alice@contoso.com'
                                    '@odata.type'        = '#microsoft.graph.user'
                                }
                            }
                            [PSCustomObject]@{
                                Id = 'sp-1'
                                AdditionalProperties = @{
                                    'displayName'        = 'Service App'
                                    'userPrincipalName'  = $null
                                    '@odata.type'        = '#microsoft.graph.servicePrincipal'
                                }
                            }
                        )
                    }
                    'role-2' {
                        @(
                            [PSCustomObject]@{
                                Id = 'user-2'
                                AdditionalProperties = @{
                                    'displayName'        = 'Bob User'
                                    'userPrincipalName'  = 'bob@contoso.com'
                                    '@odata.type'        = '#microsoft.graph.user'
                                }
                            }
                        )
                    }
                }
            }
        }

        It 'should return one row per role-member pair' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 3
        }

        It 'should include RoleName property' {
            $result = & $script:ScriptPath
            $roleNames = @($result | Select-Object -ExpandProperty RoleName -Unique)
            $roleNames | Should -Contain 'Global Administrator'
            $roleNames | Should -Contain 'User Administrator'
        }

        It 'should include MemberDisplayName property' {
            $result = & $script:ScriptPath
            $names = @($result | Select-Object -ExpandProperty MemberDisplayName)
            $names | Should -Contain 'Alice Admin'
            $names | Should -Contain 'Bob User'
        }

        It 'should include MemberUPN property for user members' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.MemberDisplayName -eq 'Alice Admin' })[0]
            $alice.MemberUPN | Should -Be 'alice@contoso.com'
        }

        It 'should translate OData type to friendly MemberType' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.MemberDisplayName -eq 'Alice Admin' })[0]
            $alice.MemberType | Should -Be 'User'

            $sp = @($result | Where-Object { $_.MemberDisplayName -eq 'Service App' })[0]
            $sp.MemberType | Should -Be 'ServicePrincipal'
        }

        It 'should include RoleId and MemberId properties' {
            $result = & $script:ScriptPath
            $alice = @($result | Where-Object { $_.MemberDisplayName -eq 'Alice Admin' })[0]
            $alice.RoleId | Should -Be 'role-1'
            $alice.MemberId | Should -Be 'user-1'
        }

        It 'should have all expected properties on each row' {
            $result = & $script:ScriptPath
            $properties = $result[0].PSObject.Properties.Name
            $properties | Should -Contain 'RoleName'
            $properties | Should -Contain 'RoleId'
            $properties | Should -Contain 'MemberDisplayName'
            $properties | Should -Contain 'MemberUPN'
            $properties | Should -Contain 'MemberType'
            $properties | Should -Contain 'MemberId'
        }

        It 'should sort results by RoleName then MemberDisplayName' {
            $result = & $script:ScriptPath
            $result[0].RoleName | Should -Be 'Global Administrator'
            $result[-1].RoleName | Should -Be 'User Administrator'
        }
    }

    Context 'when roles have no members' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgDirectoryRole {
                @(
                    [PSCustomObject]@{
                        Id          = 'role-empty'
                        DisplayName = 'Compliance Administrator'
                    }
                )
            }

            Mock Get-MgDirectoryRoleMember {
                return @()
            }
        }

        It 'should return empty results when all roles have no members' {
            $result = & $script:ScriptPath
            @($result | Where-Object { $null -ne $_ }).Count | Should -Be 0
        }
    }

    Context 'when Get-MgDirectoryRoleMember fails for one role' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }

            Mock Get-MgDirectoryRole {
                @(
                    [PSCustomObject]@{
                        Id          = 'role-ok'
                        DisplayName = 'Global Reader'
                    }
                    [PSCustomObject]@{
                        Id          = 'role-fail'
                        DisplayName = 'Broken Role'
                    }
                )
            }

            Mock Get-MgDirectoryRoleMember {
                param($DirectoryRoleId)
                switch ($DirectoryRoleId) {
                    'role-ok' {
                        @([PSCustomObject]@{
                            Id = 'user-ok'
                            AdditionalProperties = @{
                                'displayName'       = 'Good User'
                                'userPrincipalName' = 'good@contoso.com'
                                '@odata.type'       = '#microsoft.graph.user'
                            }
                        })
                    }
                    'role-fail' {
                        throw 'Access denied'
                    }
                }
            }

            Mock Write-Warning { }
        }

        It 'should still return members from successful roles' {
            $result = & $script:ScriptPath
            @($result).Count | Should -Be 1
            $result[0].MemberDisplayName | Should -Be 'Good User'
        }

        It 'should write a warning for the failed role' {
            $null = & $script:ScriptPath
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
                $Message -match 'Broken Role'
            }
        }
    }

    Context 'when no directory roles exist' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDirectoryRole { return @() }
        }

        It 'should return empty results' {
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

    Context 'when Get-MgDirectoryRole fails' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDirectoryRole { throw 'Insufficient privileges' }
        }

        It 'should write an error about role retrieval failure' {
            { & $script:ScriptPath } | Should -Throw '*Failed to retrieve directory roles*'
        }
    }

    Context 'when -OutputPath is specified' {
        BeforeAll {
            Mock Get-MgContext {
                [PSCustomObject]@{ TenantId = '00000000-0000-0000-0000-000000000000' }
            }
            Mock Get-MgDirectoryRole {
                @([PSCustomObject]@{ Id = 'role-1'; DisplayName = 'Global Admin' })
            }
            Mock Get-MgDirectoryRoleMember {
                @([PSCustomObject]@{
                    Id = 'user-1'
                    AdditionalProperties = @{
                        'displayName'       = 'Test User'
                        'userPrincipalName' = 'test@contoso.com'
                        '@odata.type'       = '#microsoft.graph.user'
                    }
                })
            }
            $script:csvOutputPath = Join-Path $TestDrive 'admin-roles.csv'
        }

        It 'should export results to a CSV file' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            Test-Path $script:csvOutputPath | Should -BeTrue
        }

        It 'should output a confirmation message' {
            $result = & $script:ScriptPath -OutputPath $script:csvOutputPath
            $result | Should -Match 'Exported admin role report'
        }
    }
}
