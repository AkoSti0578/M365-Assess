BeforeAll {
    . (Join-Path $PSScriptRoot '../../Purview/Search-AuditLog.ps1')
}

Describe 'Search-AuditLog' {
    BeforeAll {
        Mock Get-Command { return @{ Name = 'Search-UnifiedAuditLog' } } -ParameterFilter {
            $Name -eq 'Search-UnifiedAuditLog'
        }
    }

    Context 'when audit records are found' {
        BeforeAll {
            $mockAuditData = @{ ClientIP = '10.0.0.1'; ObjectId = '/sites/contoso'; ItemType = 'File'; SiteUrl = 'https://contoso.sharepoint.com'; SourceFileName = 'report.docx' } | ConvertTo-Json

            $mockRecords = @(
                [PSCustomObject]@{
                    CreationDate = (Get-Date).AddHours(-1)
                    UserIds      = 'jsmith@contoso.com'
                    Operations   = 'FileAccessed'
                    RecordType   = 'SharePointFileOperation'
                    ResultIndex  = 1
                    ResultCount  = 2
                    AuditData    = $mockAuditData
                }
                [PSCustomObject]@{
                    CreationDate = (Get-Date).AddHours(-2)
                    UserIds      = 'jdoe@contoso.com'
                    Operations   = 'FileDownloaded'
                    RecordType   = 'SharePointFileOperation'
                    ResultIndex  = 2
                    ResultCount  = 2
                    AuditData    = $mockAuditData
                }
            )
            Mock Search-UnifiedAuditLog { return $mockRecords } -ParameterFilter {
                $true
            }
        }

        It 'should return parsed audit records' {
            $result = Search-AuditLog -StartDate (Get-Date).AddDays(-1)
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'should include expected properties' {
            $result = Search-AuditLog -StartDate (Get-Date).AddDays(-1)
            $result[0].PSObject.Properties.Name | Should -Contain 'CreationDate'
            $result[0].PSObject.Properties.Name | Should -Contain 'UserIds'
            $result[0].PSObject.Properties.Name | Should -Contain 'Operations'
            $result[0].PSObject.Properties.Name | Should -Contain 'ClientIP'
        }

        It 'should parse AuditData JSON into properties' {
            $result = Search-AuditLog -StartDate (Get-Date).AddDays(-1)
            $result[0].ClientIP | Should -Be '10.0.0.1'
            $result[0].SourceFileName | Should -Be 'report.docx'
        }
    }

    Context 'when filtering by UserIds' {
        BeforeAll {
            Mock Search-UnifiedAuditLog { return @() }
        }

        It 'should pass UserIds to the search' {
            $null = Search-AuditLog -StartDate (Get-Date).AddDays(-1) -UserIds 'jsmith@contoso.com'
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly -ParameterFilter {
                $UserIds -contains 'jsmith@contoso.com'
            }
        }
    }

    Context 'when filtering by Operations' {
        BeforeAll {
            Mock Search-UnifiedAuditLog { return @() }
        }

        It 'should pass Operations to the search' {
            $null = Search-AuditLog -StartDate (Get-Date).AddDays(-1) -Operations 'FileAccessed'
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly -ParameterFilter {
                $Operations -contains 'FileAccessed'
            }
        }
    }

    Context 'when OutputPath is specified' {
        BeforeAll {
            $mockAuditData = @{ ClientIP = '10.0.0.1'; ObjectId = ''; ItemType = ''; SiteUrl = ''; SourceFileName = '' } | ConvertTo-Json
            Mock Search-UnifiedAuditLog { return @(
                [PSCustomObject]@{
                    CreationDate = (Get-Date); UserIds = 'a@test.com'; Operations = 'Test'
                    RecordType = 'Test'; ResultIndex = 1; ResultCount = 1; AuditData = $mockAuditData
                }
            ) }
            Mock Export-Csv { }
        }

        It 'should export results to CSV' {
            $null = Search-AuditLog -StartDate (Get-Date).AddDays(-1) -OutputPath 'test.csv'
            Should -Invoke Export-Csv -Times 1 -Exactly
        }
    }

    Context 'when no results are found' {
        BeforeAll {
            Mock Search-UnifiedAuditLog { return $null }
        }

        It 'should return empty results' {
            $result = Search-AuditLog -StartDate (Get-Date).AddDays(-1)
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when Search-UnifiedAuditLog is not available' {
        BeforeAll {
            Mock Get-Command { throw 'Command not found' } -ParameterFilter {
                $Name -eq 'Search-UnifiedAuditLog'
            }
        }

        It 'should throw an error' {
            { Search-AuditLog -StartDate (Get-Date).AddDays(-1) } | Should -Throw '*Search-UnifiedAuditLog*'
        }
    }
}
