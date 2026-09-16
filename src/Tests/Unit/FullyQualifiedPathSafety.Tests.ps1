BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners/Private/Resolve-TheCleanersFileSystemPath.ps1')
}

Describe 'Fully qualified filesystem path safety' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) -Tag Unit {
    It 'rejects unsafe path syntax before Get-Item resolution' {
        $UnsafePaths = @(
            'C:Temp'
            'C:.'
            '\Temp'
            '/Temp'
            'Temp'
            '.\Temp'
            '..\Temp'
            'HKLM:\Software'
            'FileSystem::C:\Temp'
        )
        Mock Get-Item { throw 'Get-Item must not run for unsafe path syntax.' }

        foreach ($UnsafePath in $UnsafePaths) {
            { Resolve-TheCleanersFileSystemPath -LiteralPath $UnsafePath } | Should -Throw
        }
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

    It 'uses the OS-backed Windows root when the process environment is spoofed' {
        $WindowsRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        if ([string]::IsNullOrWhiteSpace($WindowsRoot)) {
            Set-ItResult -Skipped -Because 'The test host did not expose an OS Windows root.'
            return
        }

        $PreviousSystemRoot = $env:SystemRoot
        try {
            $env:SystemRoot = Join-Path -Path $TestDrive -ChildPath 'SpoofedSystemRoot'
            { Resolve-TheCleanersFileSystemPath -LiteralPath $WindowsRoot } | Should -Throw '*broad cleanup root*'
        } finally {
            $env:SystemRoot = $PreviousSystemRoot
        }
    }

    It 'accepts UNC syntax only when server and share components exist' {
        Test-TheCleanersFullyQualifiedPath -Path '\\server\share\folder' | Should -BeTrue
        Test-TheCleanersFullyQualifiedPath -Path '//server/share/folder' | Should -BeTrue
        Test-TheCleanersFullyQualifiedPath -Path '\\server' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\server\' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\\share' | Should -BeFalse
    }

    It 'accepts supported extended-length drive and UNC syntax for long paths' {
        Test-TheCleanersFullyQualifiedPath -Path '\\?\C:\Temp' | Should -BeTrue
        Test-TheCleanersFullyQualifiedPath -Path '\\?\UNC\server\share\folder' | Should -BeTrue
    }

    It 'rejects unsupported device namespace syntax' {
        Test-TheCleanersFullyQualifiedPath -Path '\\.\C:\Temp' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\./C:\Temp' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1' | Should -BeFalse
        Test-TheCleanersFullyQualifiedPath -Path '\\?/GLOBALROOT\Device\HarddiskVolumeShadowCopy1' | Should -BeFalse
    }
}
