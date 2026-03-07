BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../Common/Connect-Service.ps1'
}

Describe 'Connect-Service' {
    Context 'when connecting to Graph interactively' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
                $Name -eq 'Microsoft.Graph.Authentication' -and $ListAvailable
            }
            Mock Connect-MgGraph { }
        }

        It 'should call Connect-MgGraph with Scopes' {
            & $script:ScriptPath -Service Graph -Scopes 'User.Read.All'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
        }

        It 'should use default scopes when none specified' {
            & $script:ScriptPath -Service Graph
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $Scopes -contains 'User.Read.All'
            }
        }
    }

    Context 'when connecting to Graph with certificate auth' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
                $Name -eq 'Microsoft.Graph.Authentication' -and $ListAvailable
            }
            Mock Connect-MgGraph { }
        }

        It 'should pass ClientId and CertificateThumbprint' {
            & $script:ScriptPath -Service Graph -TenantId 'contoso.onmicrosoft.com' -ClientId '00000000-0000-0000-0000-000000000000' -CertificateThumbprint 'ABC123'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $ClientId -eq '00000000-0000-0000-0000-000000000000' -and
                $CertificateThumbprint -eq 'ABC123' -and
                $TenantId -eq 'contoso.onmicrosoft.com'
            }
        }
    }

    Context 'when connecting to Graph with client secret' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
                $Name -eq 'Microsoft.Graph.Authentication' -and $ListAvailable
            }
            Mock Connect-MgGraph { }
        }

        It 'should pass ClientSecretCredential' {
            & $script:ScriptPath -Service Graph -TenantId 'contoso.onmicrosoft.com' -ClientId '00000000-0000-0000-0000-000000000000' -ClientSecret 'secret123'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $ClientSecretCredential -is [PSCredential]
            }
        }
    }

    Context 'when connecting to Exchange Online' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'ExchangeOnlineManagement' } } -ParameterFilter {
                $Name -eq 'ExchangeOnlineManagement' -and $ListAvailable
            }
            Mock Connect-ExchangeOnline { }
        }

        It 'should call Connect-ExchangeOnline with ShowBanner disabled' {
            & $script:ScriptPath -Service ExchangeOnline
            Should -Invoke Connect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
                $ShowBanner -eq $false
            }
        }

        It 'should pass Organization when TenantId is specified' {
            & $script:ScriptPath -Service ExchangeOnline -TenantId 'contoso.onmicrosoft.com'
            Should -Invoke Connect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
                $Organization -eq 'contoso.onmicrosoft.com'
            }
        }
    }

    Context 'when connecting to Purview' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'ExchangeOnlineManagement' } } -ParameterFilter {
                $Name -eq 'ExchangeOnlineManagement' -and $ListAvailable
            }
            Mock Connect-IPPSSession { }
        }

        It 'should call Connect-IPPSSession' {
            & $script:ScriptPath -Service Purview
            Should -Invoke Connect-IPPSSession -Times 1 -Exactly
        }
    }

    Context 'when required module is not installed' {
        BeforeAll {
            Mock Get-Module { return $null } -ParameterFilter {
                $ListAvailable
            }
        }

        It 'should throw an error for Graph' {
            { & $script:ScriptPath -Service Graph } | Should -Throw '*not installed*'
        }

        It 'should throw an error for ExchangeOnline' {
            { & $script:ScriptPath -Service ExchangeOnline } | Should -Throw '*not installed*'
        }
    }

    Context 'when connection fails' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
                $Name -eq 'Microsoft.Graph.Authentication' -and $ListAvailable
            }
            Mock Connect-MgGraph { throw 'Authentication failed' }
        }

        It 'should throw an error with service name' {
            { & $script:ScriptPath -Service Graph } | Should -Throw '*Failed to connect to Graph*'
        }
    }

    Context 'Graph NoWelcome suppression' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'Microsoft.Graph.Authentication' } } -ParameterFilter {
                $Name -eq 'Microsoft.Graph.Authentication' -and $ListAvailable
            }
            Mock Connect-MgGraph { }
            # Simulate Connect-MgGraph having NoWelcome parameter
            Mock Get-Command {
                return [PSCustomObject]@{
                    Parameters = @{ 'NoWelcome' = @{ Name = 'NoWelcome' } }
                }
            } -ParameterFilter { $Name -eq 'Connect-MgGraph' }
        }

        It 'should include NoWelcome when parameter is available' {
            & $script:ScriptPath -Service Graph -Scopes 'User.Read.All'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $NoWelcome -eq $true
            }
        }
    }

    Context 'UserPrincipalName for Exchange Online' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'ExchangeOnlineManagement' } } -ParameterFilter {
                $Name -eq 'ExchangeOnlineManagement' -and $ListAvailable
            }
            Mock Connect-ExchangeOnline { }
        }

        It 'should pass UserPrincipalName to Connect-ExchangeOnline' {
            & $script:ScriptPath -Service ExchangeOnline -UserPrincipalName 'admin@contoso.onmicrosoft.com'
            Should -Invoke Connect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
                $UserPrincipalName -eq 'admin@contoso.onmicrosoft.com'
            }
        }
    }

    Context 'UserPrincipalName for Purview' {
        BeforeAll {
            Mock Get-Module { return @{ Name = 'ExchangeOnlineManagement' } } -ParameterFilter {
                $Name -eq 'ExchangeOnlineManagement' -and $ListAvailable
            }
            Mock Connect-IPPSSession { }
        }

        It 'should pass UserPrincipalName to Connect-IPPSSession' {
            & $script:ScriptPath -Service Purview -UserPrincipalName 'admin@contoso.onmicrosoft.com'
            Should -Invoke Connect-IPPSSession -Times 1 -Exactly -ParameterFilter {
                $UserPrincipalName -eq 'admin@contoso.onmicrosoft.com'
            }
        }
    }

    Context 'parameter validation' {
        It 'should reject invalid Service values' {
            { & $script:ScriptPath -Service 'InvalidService' } | Should -Throw
        }
    }
}
