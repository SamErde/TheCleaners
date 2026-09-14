BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners/Private/Resolve-TheCleanersFileSystemPath.ps1')
}

Describe 'Fully qualified filesystem path safety' -Skip:(-not $WindowsHost) -Tag Unit {
    It 'rejects unsafe path syntax before Get-Item resolution' -TestCases @(
        @{ Path = 'C:Temp'; Name = 'drive-relative' }
        @{ Path = 'C:.'; Name = 'drive-relative dot' }
        @{ Path = '\Temp'; Name = 'root-relative backslash' }
        @{ Path = '/Temp'; Name = 'root-relative slash' }
        @{ Path = 'Temp'; Name = 'ordinary relative' }
        @{ Path = '.\Temp'; Name = 'dot-relative' }
        @{ Path = '..\Temp'; Name = 'parent-relative' }
        @{ Path = 'HKLM:\Software'; Name = 'registry provider' }
        @{ Path = 'FileSystem::C:\Temp'; Name = 'qualified provider' }
    ) {
        param ($Path, $Name)

        Mock Get-Item { throw 'Get-Item must not run for unsafe path syntax.' }
        { Resolve-TheCleanersFileSystemPath -LiteralPath $Path } | Should -Throw
        Should -Invoke Get-Item -Exactly 0
    }

    It 'accepts an existing fully qualified drive path' {
        $Fixture = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'DrivePath') -ItemType Directory

        $Result = Resolve-TheCleanersFileSystemPath -LiteralPath $Fixture.FullName

        $Result.FullName | Should -Be $Fixture.FullName
    }

    It 'rejects an invalid RootPath before resolving the literal path' {
        $Fixture = New-Item -Path (Join-Path -Path $TestDrive -ChildPath 'LiteralPath') -ItemType Directory
        Mock Get-Item { throw 'Get-Item must not run for an invalid RootPath.' }

        { Resolve-TheCleanersFileSystemPath -LiteralPath $Fixture.FullName -RootPath 'C:RelativeRoot' } | Should -Throw
        Should -Invoke Get-Item -Exactly 0
    }

    It 'accepts a valid strict descendant' {
        $Root = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType Directory
        $Child = New-Item -Path (Join-Path -Path $Root.FullName -ChildPath 'Child') -ItemType Directory

        $Result = Resolve-TheCleanersFileSystemPath -LiteralPath $Child.FullName -RootPath $Root.FullName

        $Result.FullName | Should -Be $Child.FullName
    }

    It 'rejects the cleanup root as its own descendant' {
        $Root = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType Directory

        { Resolve-TheCleanersFileSystemPath -LiteralPath $Root.FullName -RootPath $Root.FullName } | Should -Throw
    }

    It 'rejects a prefix-confusable sibling' {
        $RootName = [guid]::NewGuid().Guid
        $Root = New-Item -Path (Join-Path -Path $TestDrive -ChildPath $RootName) -ItemType Directory
        $Sibling = New-Item -Path (Join-Path -Path $TestDrive -ChildPath "$RootName-Other") -ItemType Directory

        { Resolve-TheCleanersFileSystemPath -LiteralPath $Sibling.FullName -RootPath $Root.FullName } | Should -Throw
    }

    It 'accepts UNC syntax only when server and share components exist' {
        Test-TheCleanersFullyQualifiedPath -Path '\\server\share\folder' | Should -BeTrue
        Test-TheCleanersFullyQualifiedPath -Path '//server/share/folder' | Should -BeTrue
        Test-TheCleanersFullyQualifiedPath -Path '\\server' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\server\' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\\share' | Should -BeFalse
    }

    It 'rejects unsupported extended-length and device path syntax' {
        Test-TheCleanersFullyQualifiedPath -Path '\\?\C:\Temp' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\?\UNC\server\share' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\.\C:\Temp' | Should -BeFalse
    }
}
