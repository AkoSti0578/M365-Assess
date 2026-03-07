BeforeAll {
    . (Join-Path $PSScriptRoot '../../Networking/Test-PortConnectivity.ps1')
}

Describe 'Test-PortConnectivity' {
    Context 'when port is open' {
        BeforeAll {
            $mockTask = [PSCustomObject]@{}
            $mockTask | Add-Member -MemberType ScriptMethod -Name Wait -Value { param($ms) return $true }

            $mockClient = [PSCustomObject]@{ Connected = $true }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { param($h, $p) return $mockTask }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
        }

        It 'should report the port as Open' {
            $result = Test-PortConnectivity -ComputerName 'server01' -Port 443
            $result.Status | Should -Be 'Open'
        }

        It 'should include ComputerName and Port' {
            $result = Test-PortConnectivity -ComputerName 'server01' -Port 443
            $result.ComputerName | Should -Be 'server01'
            $result.Port | Should -Be 443
        }
    }

    Context 'when port is closed' {
        BeforeAll {
            $mockTask = [PSCustomObject]@{}
            $mockTask | Add-Member -MemberType ScriptMethod -Name Wait -Value { param($ms) return $false }

            $mockClient = [PSCustomObject]@{ Connected = $false }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { param($h, $p) return $mockTask }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
        }

        It 'should report the port as Closed' {
            $result = Test-PortConnectivity -ComputerName 'server01' -Port 9999
            $result.Status | Should -Be 'Closed'
        }
    }

    Context 'when testing multiple ports' {
        BeforeAll {
            $mockTask = [PSCustomObject]@{}
            $mockTask | Add-Member -MemberType ScriptMethod -Name Wait -Value { param($ms) return $true }

            $mockClient = [PSCustomObject]@{ Connected = $true }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { param($h, $p) return $mockTask }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
        }

        It 'should return one result per port' {
            $result = Test-PortConnectivity -ComputerName 'server01' -Port 80, 443, 3389
            $result.Count | Should -Be 3
        }
    }

    Context 'when testing multiple hosts' {
        BeforeAll {
            $mockTask = [PSCustomObject]@{}
            $mockTask | Add-Member -MemberType ScriptMethod -Name Wait -Value { param($ms) return $true }

            $mockClient = [PSCustomObject]@{ Connected = $true }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { param($h, $p) return $mockTask }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
        }

        It 'should return results for each host-port combination' {
            $result = Test-PortConnectivity -ComputerName 'server01', 'server02' -Port 443
            $result.Count | Should -Be 2
            $result[0].ComputerName | Should -Be 'server01'
            $result[1].ComputerName | Should -Be 'server02'
        }
    }

    Context 'when connection throws an exception' {
        BeforeAll {
            $mockClient = [PSCustomObject]@{ Connected = $false }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { throw 'Host not found' }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
        }

        It 'should report as Closed without throwing' {
            $result = Test-PortConnectivity -ComputerName 'badhost' -Port 443
            $result.Status | Should -Be 'Closed'
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockTask = [PSCustomObject]@{}
            $mockTask | Add-Member -MemberType ScriptMethod -Name Wait -Value { param($ms) return $true }

            $mockClient = [PSCustomObject]@{ Connected = $true }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { param($h, $p) return $mockTask }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Test-PortConnectivity -ComputerName 'server01' -Port 443 -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'pipeline input' {
        BeforeAll {
            $mockTask = [PSCustomObject]@{}
            $mockTask | Add-Member -MemberType ScriptMethod -Name Wait -Value { param($ms) return $true }

            $mockClient = [PSCustomObject]@{ Connected = $true }
            $mockClient | Add-Member -MemberType ScriptMethod -Name ConnectAsync -Value { param($h, $p) return $mockTask }
            $mockClient | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

            Mock New-Object { return $mockClient } -ParameterFilter {
                $TypeName -eq 'System.Net.Sockets.TcpClient'
            }
        }

        It 'should accept pipeline input for ComputerName' {
            $result = @('host1', 'host2') | Test-PortConnectivity -Port 443
            $result.Count | Should -Be 2
        }
    }

    Context 'parameter validation' {
        It 'should reject port 0' {
            { Test-PortConnectivity -ComputerName 'host' -Port 0 } | Should -Throw
        }

        It 'should reject port above 65535' {
            { Test-PortConnectivity -ComputerName 'host' -Port 70000 } | Should -Throw
        }

        It 'should reject timeout below 100' {
            { Test-PortConnectivity -ComputerName 'host' -Port 443 -Timeout 50 } | Should -Throw
        }
    }
}
