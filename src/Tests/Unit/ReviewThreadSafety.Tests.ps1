BeforeDiscovery {
    $WindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $TempCases = @(
        @{ CommandName = 'Clear-CurrentUserTemp' }
        @{ CommandName = 'Clear-WindowsTemp' }
    )
}

BeforeAll {
    $ModuleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../../TheCleaners')).Path
    foreach ($RelativePath in @(
        'Private/Resolve-TheCleanersFileSystemPath.ps1'
        'Private/Remove-OldFiles.ps1'
        'Public/Clear-CurrentUserTemp.ps1'
        'Public/Clear-WindowsTemp.ps1'
        'Public/Clear-OldIISLog.ps1'
        'Public/Clear-OldExchangeLog.ps1'
    )) {
        . (Join-Path -Path $ModuleRoot -ChildPath $RelativePath)
    }
}

Describe 'Temp candidate type-swap protection: <CommandName>' -ForEach $TempCases -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousTemp = $env:TEMP
        $PreviousTmp = $env:TMP
        $PreviousSystemRoot = $env:SystemRoot
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $FakeWindows = Join-Path -Path $FixtureRoot -ChildPath 'Windows'
        $TempRoot = Join-Path -Path $FakeWindows -ChildPath 'Temp'
        $null = New-Item -Path $TempRoot -ItemType Directory -Force
        $Candidate = New-Item -Path (Join-Path -Path $TempRoot -ChildPath 'candidate.tmp') -ItemType File
        $Now = [DateTime]::UtcNow
        $Candidate.LastWriteTimeUtc = $Now.AddDays(-31)
        $env:TEMP = $TempRoot
        $env:TMP = $TempRoot
        $env:SystemRoot = $FakeWindows
        Mock Get-Date { $Now }
    }

    AfterEach {
        $env:TEMP = $PreviousTemp
        $env:TMP = $PreviousTmp
        $env:SystemRoot = $PreviousSystemRoot
    }

    It 'does not delete or count a directory that replaces a discovered file' {
        $OriginalResolver = (Get-Command -Name Resolve-TheCleanersFileSystemPath -CommandType Function).ScriptBlock
        $State = @{ Changed = $false }
        Mock Resolve-TheCleanersFileSystemPath {
            param($LiteralPath, $RootPath)
            $ResolveParameters = @{ LiteralPath = $LiteralPath }
            if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
                $ResolveParameters.RootPath = $RootPath
            }
            $ResolvedItem = & $OriginalResolver @ResolveParameters
            if (-not $State.Changed -and $LiteralPath -eq $Candidate.FullName -and -not [string]::IsNullOrWhiteSpace($RootPath)) {
                [System.IO.File]::Delete($Candidate.FullName)
                $null = New-Item -Path $Candidate.FullName -ItemType Directory
                $State.Changed = $true
            }
            $ResolvedItem
        }

        $Result = & $CommandName -Days 30 -Confirm:$false -PassThru

        [System.IO.Directory]::Exists($Candidate.FullName) | Should -BeTrue
        $Result.FilesRemoved | Should -Be 0
        $Result.FilesSkipped | Should -Be 1
        $Result.BytesReclaimed | Should -Be 0
        $Result.Status | Should -Be 'CompletedWithSkips'
    }

    It 'converts a local Get-Date result to a UTC retention cutoff' {
        Mock Get-Date { $Now.ToLocalTime() }

        $Result = & $CommandName -Days 30 -WhatIf -PassThru

        $Result.CutoffUtc | Should -Be $Now.AddDays(-30)
        $Result.CutoffUtc.Kind | Should -Be ([DateTimeKind]::Utc)
    }

    It 'uses a file-bound DeleteOnClose handle instead of provider removal' {
        $Tokens = $null
        $ParseErrors = $null
        $FunctionPath = Join-Path -Path $ModuleRoot -ChildPath ("Public/{0}.ps1" -f $CommandName)
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($FunctionPath, [ref]$Tokens, [ref]$ParseErrors)
        $ParseErrors | Should -BeNullOrEmpty
        @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Remove-Item'
                }, $true)) | Should -HaveCount 0
        $FunctionText = [System.IO.File]::ReadAllText($FunctionPath)
        $FunctionText | Should -Match '\[System\.IO\.FileOptions\]::DeleteOnClose'
    }
}

Describe 'Exchange preview root validation' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $ExchangeRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $LogRoot = Join-Path -Path $ExchangeRoot -ChildPath 'Logging'
        $null = New-Item -Path $LogRoot -ItemType Directory -Force
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $ExchangeRoot } }
    }

    It 'skips an expected log root occupied by a file' {
        [System.IO.Directory]::Delete($LogRoot)
        $RootFile = New-Item -Path $LogRoot -ItemType File

        $Result = @(Clear-OldExchangeLog -WhatIf -PassThru -WarningAction SilentlyContinue)

        $Result | Should -HaveCount 0
        $RootFile.FullName | Should -Exist
    }

    It 'rejects an installation path that is not a directory' {
        $InstallFile = New-Item -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)) -ItemType File
        Mock Get-ItemProperty { [pscustomobject]@{ MsiInstallPath = $InstallFile.FullName } }

        { Clear-OldExchangeLog -WhatIf -WarningAction SilentlyContinue } | Should -Throw '*not a directory*'
    }

    It 'does not expose a removal-bypass parameter' {
        $CommandParameters = (Get-Command -Name Clear-OldExchangeLog -CommandType Function).Parameters
        foreach ($ParameterName in @('Force', 'AllowRemoval', 'EnableRemoval')) {
            $CommandParameters.ContainsKey($ParameterName) | Should -BeFalse
        }
    }
}

Describe 'IIS structural preview lock' -Skip:(-not $WindowsHost) -Tag Unit {
    BeforeEach {
        $PreviousSystemDrive = $env:SystemDrive
        $FixtureRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $IISRoot = Join-Path -Path $FixtureRoot -ChildPath 'inetpub/logs/LogFiles'
        $null = New-Item -Path $IISRoot -ItemType Directory -Force
        $OldLog = New-Item -Path (Join-Path -Path $IISRoot -ChildPath 'old.log') -ItemType File
        $OldLog.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-61)
        $env:SystemDrive = $FixtureRoot
        Mock Get-Module { $null } -ParameterFilter { $Name -eq 'WebAdministration' -and $ListAvailable }
        Mock Get-ItemProperty { throw 'Fixture registry pav\È[˜]˜Z[X›K‰ÈBˆ[ØÚÈ™[[İ™KSÛš[\ÈÈ›İÈ	ÒRTÈ™]šY]È]\İ›İ[›ÚÙHHYØXŞH™[[İ˜[[\‹‰ÈBˆB‚ˆY\‘XXÚÂˆ	[”Ş\İ[Qš]™HH	™]š[İ\ÔŞ\İ[Qš]™BˆB‚ˆ]	Ü™Z™XİÈÛZ\ÜÚ[ÛˆÙˆÚ]Yˆ™Y›Ü™H\ØÛİ™\IÈÂˆÈÛX\‹SÛRTÓÙÈPÛÛ™š\›N‰˜[ÙHHÚİ[U›İÈ	Êœ™]šY]Ë[Û›J‰ÂˆÚİ[R[›ÚÙHÙ]S[Ù[HQ^XİHT\˜[Y]\‘š[\ˆÈ	˜[YHY\H	ÕÙXYZ[š\İ˜][Û‰ÈX[™	\İ]˜Z[X›HBˆÚİ[R[›ÚÙHÙ]R][T›Ü\HQ^XİHˆÚİ[R[›ÚÙH™[[İ™KSÛš[\ÈQ^XİHˆB‚ˆ]	Ü™]šY]ÜÈØ[™Y]\ÈÚ]İ][›ÚÚ[™ÈH™[[İ˜[[\‰ÈÂˆ	™\İ[HÛX\‹SÛRTÓÙÈQ^\ÈŒUÚ]YˆT\ÜÕHUØ\›š[™ĞXİ[ÛˆÚ[[PÛÛ[YB‚ˆ	™\İ[Úİ[R]™PÛİ[Bˆ	™\İ[‘š[PØ[™Y]PÛİ[Úİ[P™HBˆ	™\İ[Ø[™Y]T]ÈÚİ[PÛÛZ[ˆ	ÛÙË‘[˜[YBˆ	™\İ[‘š[\Ô™[[İ™YÚİ[P™Hˆ	ÛÙË‘[˜[YHÚİ[Q^\İˆÚİ[R[›ÚÙH™[[İ™KSÛš[\ÈQ^XİHˆB‚ˆ]	ØÛÛZ[œÈ›È[][ÛˆÛÛ[X[™ÜˆÙ[™\šXÈ™[[İ˜[Z[\ˆØ[	ÈÂˆ	ÚÙ[œÈH	[ˆ	\œÙQ\œ›ÜœÈH	[ˆ	[˜İ[Û”]H›Ú[‹T]T]	[Ù[T›ÛİPÚ[]	ÔX›XËĞÛX\‹SÛRTÓÙËœÌIÂˆ	\İHÔŞ\İ[K“X[˜YÙ[Y[]]ÛX][Û‹“[™İXYÙK”\œÙ\—N”\œÙQš[J	[˜İ[Û”]Ü™Y—IÚÙ[œËÜ™Y—I\œÙQ\œ›ÜœÊBˆ	\œÙQ\œ›ÜœÈÚİ[P™S[Ü‘[\Bˆ	›Ü˜šY[ˆH	\İ‘š[™[
Âˆ\˜[J	›ÙJBˆ
	›ÙHZ\ÈÔŞ\İ[K“X[˜YÙ[Y[]]ÛX][Û‹“[™İXYÙKÛÛ[X[™\İHX[™	›ÙK‘Ù]ÛÛ[X[™˜[YJ
HZ[ˆ
	Ô™[[İ™KR][IË	Ô™[[İ™KSÛš[\ÉË	Ò[›ÚÙKQ^™\ÜÚ[Û‰Ë	Ôİ\T›ØÙ\ÜÉÊJH[Ü‚ˆ
	›ÙHZ\ÈÔŞ\İ[K“X[˜YÙ[Y[]]ÛX][Û‹“[™İXYÙK’[›ÚÙSY[X™\‘^™\ÜÚ[Û\İHX[™	›ÙK“Y[X™\‹•˜[YHY\H	Ñ[]IÊBˆK	YJBˆ
	›Ü˜šY[ŠHÚİ[R]™PÛİ[ˆBŸB