function New-DeterministicZipArchive {
    <#
    .SYNOPSIS
        Create a repeatable source-layout ZIP without runtime-dependent compression.
    .DESCRIPTION
        Files, including hidden files, are ordered by ordinal relative path. Entry
        names use UTF-8, timestamps use the ZIP epoch, and attributes are fixed.
        Supported PS7 Windows builders use stored entries. Windows PowerShell 5.1
        can read the result; its older ZIP writer is not a canonical producer.
    .PARAMETER SourcePath
        Directory containing the staged package.
    .PARAMETER DestinationPath
        New archive path outside the staged package. Existing files are refused.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]
        $SourcePath,

        [Parameter(Mandatory)]
        [string]
        $DestinationPath
    )

    if (-not $PSCmdlet.ShouldProcess($DestinationPath, 'Create deterministic archive')) {
        return
    }

    if ($PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName 'System.IO.Compression'
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
    }

    $SourcePath = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).ProviderPath
    $Paths = [System.Collections.Generic.List[string]]::new()
    foreach ($File in @(Get-ChildItem -LiteralPath $SourcePath -File -Recurse -Force -ErrorAction Stop)) {
        $Paths.Add($File.FullName.Substring($SourcePath.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/'))
    }
    $Paths.Sort([System.StringComparer]::Ordinal)

    $ArchiveStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $Archive = $null
    try {
        # .NET Framework recognizes the shared UTF8 instance when setting bit 11.
        # Entry names use GetBytes (no preamble), so this does not add a BOM.
        $Encoding = [System.Text.Encoding]::UTF8
        $Archive = [System.IO.Compression.ZipArchive]::new($ArchiveStream, [System.IO.Compression.ZipArchiveMode]::Create, $false, $Encoding)
        $Epoch = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        foreach ($RelativePath in $Paths) {
            # Stored entries avoid changes in the runtime's Deflate implementation.
            $Entry = $Archive.CreateEntry($RelativePath, [System.IO.Compression.CompressionLevel]::NoCompression)
            $Entry.LastWriteTime = $Epoch
            $Entry.ExternalAttributes = 0
            $InputStream = [System.IO.File]::OpenRead((Join-Path -Path $SourcePath -ChildPath $RelativePath))
            $OutputStream = $null
            try {
                $OutputStream = $Entry.Open()
                $InputStream.CopyTo($OutputStream)
            } finally {
                if ($null -ne $OutputStream) {
                    $OutputStream.Dispose()
                }
                $InputStream.Dispose()
            }
        }
    } finally {
        if ($null -ne $Archive) {
            $Archive.Dispose()
        }
        $ArchiveStream.Dispose()
    }
}

