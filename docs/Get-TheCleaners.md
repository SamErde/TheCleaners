# Get-TheCleaners

## Synopsis

Get the available commands and their current maturity without running cleanup.

## Syntax

```powershell
Get-TheCleaners [-Dedication] [-NoLogo] [<CommonParameters>]
```

Returns one `TheCleaners.CommandInfo` object per exported function, with `Name`, `Maturity`, `RemovalEnabled`, and `SupportsWhatIf`. IIS and Exchange are `PreviewOnly`; other commands remain `Prerelease` until their acceptance gates pass. Aliases are not duplicated as inventory entries.

```powershell
Get-TheCleaners
Get-TheCleaners -NoLogo | Where-Object Maturity -EQ 'PreviewOnly'
```

`-NoLogo` omits interactive branding for pipelines. `-Dedication` explicitly shows the dedication. The function never performs maintenance. `Start-Cleaning` remains a deprecated alias with the same parameters and behavior through 1.x.

Canonical page: <https://day3bits.com/thecleaners/Get-TheCleaners/>.
