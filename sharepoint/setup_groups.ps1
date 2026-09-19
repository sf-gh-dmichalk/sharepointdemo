# Creates site groups and assigns folder-level permissions for the
# store ops Openflow demo. Run AFTER seed documents are uploaded.
#   pwsh -File sharepoint/setup_groups.ps1
#
# Opens a browser for interactive sign-in. Sign in as an SPO-tenant admin.
# Re-runnable: existing groups are reused, permissions reasserted.

$ErrorActionPreference = 'Stop'

$SiteUrl     = 'https://oceancloudtech.sharepoint.com/sites/openflowdemo'
$PnPClientId = '6868ac5b-6e83-4918-8ca8-1cecbf42ceaa'
$List        = 'Documents'
$LibraryPath = 'Shared Documents'

# Group -> members. Retail store ops roles.
$Groups = [ordered]@{
    'StoreOps-Management'  = @('storemgr@oceancloudtech.com')
    'StoreOps-Facilities'  = @('facilities@oceancloudtech.com')
    'StoreOps-Safety'      = @('safety@oceancloudtech.com')
    'StoreOps-Merchandising' = @('merch@oceancloudtech.com')
}

# Folder -> groups. First group breaks inheritance; rest are added on top.
# Management is on every folder so it remains reachable after inheritance breaks.
$FolderAccess = [ordered]@{
    'Inspections' = @('StoreOps-Management', 'StoreOps-Safety')
    'Maintenance' = @('StoreOps-Management', 'StoreOps-Facilities')
    'Incidents'   = @('StoreOps-Management', 'StoreOps-Safety')
    # Planograms is deliberately left inheriting — the unrestricted baseline
    # that makes the restricted folders legible by contrast.
}

Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $PnPClientId

# --- 1. Groups and membership -------------------------------------------------
foreach ($name in $Groups.Keys) {
    $existing = Get-PnPGroup -Identity $name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "group exists   $name" -ForegroundColor DarkGray
    } else {
        New-PnPGroup -Title $name | Out-Null
        Write-Host "group created  $name" -ForegroundColor Green
    }

    foreach ($member in $Groups[$name]) {
        try {
            Add-PnPGroupMember -Group $name -LoginName $member -ErrorAction Stop | Out-Null
            Write-Host "    + $member" -ForegroundColor Green
        } catch {
            Write-Host "    ! $member -- $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# --- 2. Library-level grant ---------------------------------------------------
$list = Get-PnPList -Identity $List -Includes HasUniqueRoleAssignments
if (-not $list.HasUniqueRoleAssignments) {
    Set-PnPList -Identity $List -BreakRoleInheritance -CopyRoleAssignments
    Write-Host "`nlibrary inheritance broken (existing assignments copied)" -ForegroundColor Green
} else {
    Write-Host "`nlibrary already has unique permissions" -ForegroundColor DarkGray
}

Set-PnPListPermission -Identity $List -Group 'StoreOps-Management' -AddRole 'Read'
Write-Host "library grant  StoreOps-Management -> Read on $List" -ForegroundColor Green

# --- 3. Folder-level permissions ---------------------------------------------
foreach ($folder in $FolderAccess.Keys) {
    $groupList  = $FolderAccess[$folder]
    $folderPath = "$LibraryPath/$folder"
    Write-Host "`nfolder $folderPath" -ForegroundColor Cyan

    if (-not (Get-PnPFolder -Url $folderPath -ErrorAction SilentlyContinue)) {
        Write-Host "    ! not found. Folders actually present:" -ForegroundColor Yellow
        Get-PnPFolderItem -FolderSiteRelativeUrl $LibraryPath -ItemType Folder |
            ForEach-Object { Write-Host "        $($_.Name)" -ForegroundColor Yellow }
        continue
    }

    for ($i = 0; $i -lt $groupList.Count; $i++) {
        $g = $groupList[$i]
        if ($i -eq 0) {
            Set-PnPFolderPermission -List $List -Identity $folderPath -Group $g `
                -AddRole 'Read' -ClearExisting
            Write-Host "    inheritance broken; $g -> Read" -ForegroundColor Green
        } else {
            Set-PnPFolderPermission -List $List -Identity $folderPath -Group $g -AddRole 'Read'
            Write-Host "    $g -> Read" -ForegroundColor Green
        }
    }
}

# --- 4. Verify ----------------------------------------------------------------
Write-Host "`n--- Verification ---" -ForegroundColor Cyan
foreach ($name in $Groups.Keys) {
    Write-Host $name -ForegroundColor White
    $members = Get-PnPGroupMember -Group $name -ErrorAction SilentlyContinue
    if (-not $members) {
        Write-Host "    (no members)" -ForegroundColor Yellow
        continue
    }
    foreach ($m in $members) {
        $mail = if ($m.Email) { $m.Email } else { '<no mail attribute>' }
        Write-Host ("    {0,-34} {1}" -f $m.LoginName, $mail)
    }
}

Write-Host "`n--- Folder permissions ---" -ForegroundColor Cyan
foreach ($folder in @('Inspections', 'Maintenance', 'Incidents', 'Planograms')) {
    $f = Get-PnPFolder -Url "$LibraryPath/$folder" -Includes ListItemAllFields -ErrorAction SilentlyContinue
    if (-not $f) { continue }
    $unique = (Get-PnPProperty -ClientObject $f.ListItemAllFields -Property HasUniqueRoleAssignments)
    $state  = if ($unique) { 'unique' } else { 'inherited' }
    Write-Host ("    {0,-14} {1}" -f $folder, $state)
}
