# Uploads the seed documents to SharePoint, creating the folder
# structure as it goes. Run from the sharepoint/ directory:
#   pwsh -File sharepoint/upload_seed.ps1
#
# Opens a browser for interactive sign-in. Sign in as an SPO-tenant admin.
# Re-runnable: existing files are overwritten, existing folders reused.

$ErrorActionPreference = 'Stop'

$SiteUrl     = 'https://oceancloudtech.sharepoint.com/sites/openflowdemo'
$PnPClientId = '6868ac5b-6e83-4918-8ca8-1cecbf42ceaa'   # PnP login app, not the connector's
$Library     = 'Shared Documents'                        # server-relative name of the "Documents" library
$SeedRoot    = Join-Path $PSScriptRoot 'seed-docs'

if (-not (Test-Path $SeedRoot)) { throw "Seed directory not found: $SeedRoot" }

Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $PnPClientId

$files = Get-ChildItem -Path $SeedRoot -Recurse -File |
         Where-Object { $_.Extension -in '.pdf', '.xlsx' }

Write-Host "Found $($files.Count) file(s) to upload." -ForegroundColor Cyan

foreach ($f in $files) {
    # Folder name relative to data/seed, e.g. "Agreements"
    $seedRootFull = (Get-Item $SeedRoot).FullName.TrimEnd('/', '\')
    $relative     = $f.FullName.Substring($seedRootFull.Length).TrimStart('/', '\')
    $subFolder    = (Split-Path $relative -Parent) -replace '\\', '/'
    $targetPath   = if ($subFolder) { "$Library/$subFolder" } else { $Library }

    Resolve-PnPFolder -SiteRelativePath $targetPath | Out-Null
    Add-PnPFile -Path $f.FullName -Folder $targetPath | Out-Null
    Write-Host "  uploaded  $targetPath/$($f.Name)" -ForegroundColor Green
}

Write-Host "`nDone. Verifying library contents:" -ForegroundColor Cyan
Get-PnPListItem -List 'Documents' -PageSize 100 |
    ForEach-Object { $_.FieldValues.FileRef } |
    Where-Object { $_ } |
    Sort-Object |
    ForEach-Object { Write-Host "  $_" }
