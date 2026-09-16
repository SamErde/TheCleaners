BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../New-DeterministicZipArchive.ps1')
    if ($PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
}

Describe 'Archive reproducibility' -Tag Unit {
    It 'preserves hidden, Unicode, empty and nested files with stable metadata and ordinal ordering' {
        $Root = Join-Path -Path $TestDrive -ChildPath 'package'
        $null = New-Item -Path (Join-Path -Path $Root -ChildPath 'nested') -ItemType Directory -Force
        $Names = @('z.txt', 'A.txt', ('nested/' + [char]0x00e9 + '.txt'), '.hidden', 'empty', ([char]0xe000 + '.txt'), ([char]::ConvertFromUtf32(0x1f600) + '.txt'))
        foreach ($Name in $Names) {
            $Content = if ($Name -eq 'empty') { '' } else { "content:$Name" }
            [System.IO.File]::WriteAllText((Join-Path -Path $Root -ChildPath $Name), $Content)
        }
        $HiddenPath = Join-Path -Path $Root -ChildPath '.hidden'
        [System.IO.File]::SetAttributes($HiddenPath, [System.IO.FileAttributes]::Hidden)
        $First = Join-Path -Path $TestDrive -ChildPath 'first.zip'
        $Second = Join-Path -Path $TestDrive -ChildPath 'second.zip'
        # Preserve a resolved source's trailing separator, as on a drive root.
        Mock Resolve-Path { [pscustomobject]@{ ProviderPath = $Root + [System.IO.Path]::DirectorySeparatorChar } }
        New-DeterministicZipArchive -SourcePath $Root -DestinationPath $First
        foreach ($File in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force)) {
            $File.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-20)
        }
        $PreviousCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            New-DeterministicZipArchive -SourcePath $Root -DestinationPath $Second
        } finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $PreviousCulture
        }
        (Get-FileHash -LiteralPath $First).Hash | Should -Be (Get-FileHash -LiteralPath $Second).Hash
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($First)
        try {
            $ExpectedNames = [System.Collections.Generic.List[string]]::new()
            foreach ($Name in $Names) { $ExpectedNames.Add($Name) }
            $ExpectedNames.Sort([System.StringComparer]::Ordinal)
            @($Archive.Entries).Count | Should -Be $Names.Count
            (@($Archive.Entries.FullName) -join '|') | Should -Be ($ExpectedNames -join '|')
            foreach ($Entry in $Archive.Entries) {
                $Entry.LastWriteTime.DateTime | Should -Be ([DateTime]::new(1980, 1, 1))
                $Entry.ExternalAttributes | Should -Be 0
                $Reader = [System.IO.StreamReader]::new($Entry.Open())
                try {
                    $Reader.ReadToEnd() | Should -Be ([System.IO.File]::ReadAllText((Join-Path -Path $Root -ChildPath $Entry.FullName)))
                } finally { $Reader.Dispose() }
            }
        } finally { $Archive.Dispose() }
    }

    It 'honors WhatIf and refuses to overwrite an existing archive' {
        $Root = Join-Path -Path $TestDrive -ChildPath 'guard'
        $null = New-Item -Path $Root -ItemType Directory
        $Zip = Join-Path -Path $TestDrive -ChildPath 'guard.zip'
        New-DeterministicZipArchive -SourcePath $Root -DestinationPath $Zip -WhatIf
        $Zip | Should -Not -Exist
        [System.IO.File]::WriteAllText($Zip, 'preserve me')
        { New-DeterministicZipArchive -SourcePath $Root -DestinationPath $Zip -ErrorAction Stop } | Should -Throw
        [System.IO.File]::ReadAllText($Zip) | Should -Be 'preserve me'
    }
}

