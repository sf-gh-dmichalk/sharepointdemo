# Creates the four site groups and assigns folder-level permissions.
# Run AFTER the seed documents are uploaded (the folders must exist).
#   pwsh -File setup_groups.ps1
#
# Opens a browser for interactive sign-in. Sign in as an SPO-tenant admin.
# Re-runnable: existing groups are reused, permissions reasserted.

$ErrorActionPreference = 'Stop'

$SiteUrl     = 'https://oceancloudtech.sharepoint.com/sites/openflowdemo'
$PnPClientId = '6868ac5b-6e83-4918-8ca8-1cecbf42ceaa'
$List        = 'Documents'
$LibraryPath = 'Shared Documents'   # site-relative path; folder identities are built from this
$ItemLevelFile = 'trade_promotion_agreement_Q3FY26_MidwestGrocers.pdf'

# Group -> members. Empty array is allowed; the group is still created.
$Groups = [ordered]@{
    'SPDemo-TradeTeam'  = @('trade@oceancloudtech.com')
    'SPDemo-FieldSales' = @('fieldsales@oceancloudtech.com')
    'SPDemo-Finance'    = @('finance@oceancloudtech.com')
    'SPDemo-Legal'      = @('legal@oceancloudtech.com')
}

# Folder -> groups, in order. The FIRST group listed breaks inheritance via
# -ClearExisting; the rest are added on top. TradeTeam is repeated on every
# folder on purpose: once a folder has unique permissions, the library-level
# grant no longer flows into it.
$FolderAccess = [ordered]@{
    'Agreements' = @('SPDemo-TradeTeam', 'SPDemo-Finance', 'SPDemo-Legal')
    'Audits'     = @('SPDemo-TradeTeam', 'SPDemo-FieldSales')
    'PriceLists' = @('SPDemo-TradeTeam', 'SPDemo-Finance')
    # Specs is deliberately left inheriting - it is the unrestricted baseline
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
            # Already a member, or the user does not exist in this tenant.
            Write-Host "    ! $member -- $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# --- 2. Library-level grant so the inheriting folder (Specs) is reachable -----
# The library inherits from the site by default, and you cannot add a role
# assignment to an inheriting object. Break inheritance first, copying the
# existing assignments so site owners and admins keep their access.
$list = Get-PnPList -Identity $List -Includes HasUniqueRoleAssignments
if (-not $list.HasUniqueRoleAssignments) {
    Set-PnPList -Identity $List -BreakRoleInheritance -CopyRoleAssignments
    Write-Host "`nlibrary inheritance broken (existing assignments copied)" -ForegroundColor Green
} else {
    Write-Host "`nlibrary already has unique permissions" -ForegroundColor DarkGray
}

Set-PnPListPermission -Identity $List -Group 'SPDemo-TradeTeam' -AddRole 'Read'
Write-Host "library grant  SPDemo-TradeTeam -> Read on $List" -ForegroundColor Green

# --- 3. Folder-level permissions ---------------------------------------------
foreach ($folder in $FolderAccess.Keys) {
    $groupList  = $FolderAccess[$folder]
    $folderPath = "$LibraryPath/$folder"
    Write-Host "`nfolder $folderPath" -ForegroundColor Cyan

    # Fail loudly and usefully if the path is wrong, rather than "File Not Found".
    if (-not (Get-PnPFolder -Url $folderPath -ErrorAction SilentlyContinue)) {
        Write-Host "    ! not found. Folders actually present:" -ForegroundColor Yellow
        Get-PnPFolderItem -FolderSiteRelativeUrl $LibraryPath -ItemType Folder |
            ForEach-Object { Write-Host "        $($_.Name)" -ForegroundColor Yellow }
        continue
    }

    for ($i = 0; $i -lt $groupList.Count; $i++) {
        $g = $groupList[$i]
        if ($i -eq 0) {
            # Breaks inheritance and removes inherited grants.
            Set-PnPFolderPermission -List $List -Identity $folderPath -Group $g `
                -AddRole 'Read' -ClearExisting
            Write-Host "    inheritance broken; $g -> Read" -ForegroundColor Green
        } else {
            Set-PnPFolderPermission -List $List -Identity $folderPath -Group $g -AddRole 'Read'
            Write-Host "    $g -> Read" -ForegroundColor Green
        }
    }
}

# --- 4. Item-level unique permission on one Agreements file -------------------
$item = Get-PnPListItem -List $List -PageSize 500 |
        Where-Object { $_.FieldValues.FileLeafRef -eq $ItemLevelFile } |
        Select-Object -First 1

if (-not $item) {
    Write-Host "`n! Could not find $ItemLevelFile - skipping item-level permission." -ForegroundColor Yellow
} else {
    Set-PnPListItemPermission -List $List -Identity $item.Id `
        -Group 'SPDemo-Legal' -AddRole 'Read' -ClearExisting
    Write-Host "`nitem-level     $ItemLevelFile -> SPDemo-Legal only (unique)" -ForegroundColor Green
}

# --- 5. Verify ----------------------------------------------------------------
# Report LoginName as well as Email. These demo users are unlicensed, so their
# Entra `mail` attribute is empty unless it has been set explicitly via Graph --
# and an empty Email here means the connector's user_emails array will also be
# empty, even though group membership is correct.
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
foreach ($folder in @('Agreements', 'Audits', 'PriceLists', 'Specs')) {
    $f = Get-PnPFolder -Url "$LibraryPath/$folder" -Includes ListItemAllFields -ErrorAction SilentlyContinue
    if (-not $f) { continue }
    $unique = (Get-PnPProperty -ClientObject $f.ListItemAllFields -Property HasUniqueRoleAssignments)
    $state  = if ($unique) { 'unique' } else { 'inherited' }
    Write-Host ("    {0,-14} {1}" -f $folder, $state)
}
