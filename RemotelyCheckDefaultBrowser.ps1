<#
.SYNOPSIS
  Ensures Remote Registry, enumerates interactive sessions and loaded profiles (excluding “_Classes” hives),
  then queries per-user and machine-wide default browser settings.

.DESCRIPTION
  For each computer:
    1. Ensures Remote Registry is set to Automatic and started.
    2. Uses `quser /server:` to list actual console/RDP sessions.
    3. Uses `reg.exe` to list loaded HKU hives (SIDs), excluding any hive ending in “_Classes”.
    4. Translates each SID to DOMAIN\User for reporting.
    5. Queries each user’s HTTP UserChoice\ProgId via `reg.exe`.
    6. If no per-user setting, queries machine default under 
       HKLM\SOFTWARE\Clients\StartMenuInternet via `reg.exe`.
#>

# ——————————————
# Configuration
# ——————————————
$ComputerList = @(
    'PC527','PC416','PC284','PC323','PC873',
    'PC970','PC194','PC142','PC846','PC342'
)


cls

function Ensure-RemoteRegistry {
    param([string]$Computer)
    try {
        Invoke-Command -ComputerName $Computer -ScriptBlock {
            Set-Service -Name RemoteRegistry -StartupType Automatic -ErrorAction Stop
            if ((Get-Service -Name RemoteRegistry).Status -ne 'Running') {
                Start-Service -Name RemoteRegistry -ErrorAction Stop
            }
        } -ErrorAction Stop
        Write-Host "[$Computer] Remote Registry OK" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "[$Computer] Cannot enable/start Remote Registry: $_"
        return $false
    }
}

function Get-InteractiveUsers {
    param([string]$Computer)
    $raw = & quser "/server:$Computer" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        Write-Host "[$Computer] No interactive sessions detected (or quser failed)." -ForegroundColor Yellow
        return @()
    }
    # Skip header; first column is username
    return $raw |
        Select-Object -Skip 1 |
        ForEach-Object { ($_ -split '\s+')[0] } |
        Select-Object -Unique
}

function Get-LoadedUserSids {
    param([string]$Computer)
    $output = & reg.exe query "\\$Computer\HKU" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "[$Computer] Failed to list HKU: $output"
        return @()
    }
    return $output |
        Where-Object { 
            $_ -match '^HKEY_USERS\\S-1-5-21-' -and 
            $_ -notmatch '_Classes$'
        } |
        ForEach-Object { ($_ -split '\\')[-1].Trim() }
}

function Query-ProgId {
    param(
        [string]$Computer,
        [string]$Sid
    )
    $regPath = "HKU\$Sid\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice"
    $args = @('query', "\\$Computer\$regPath", '/v', 'ProgId')
    $output = & reg.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    foreach ($line in $output) {
        if ($line -match '^\s*ProgId\s+REG_SZ\s+(\S+)\s*$') {
            return $matches[1]
        }
    }
    return $null
}

function Query-MachineDefault {
    param([string]$Computer)
    $regPath = 'HKLM\SOFTWARE\Clients\StartMenuInternet'
    $args = @('query', "\\$Computer\$regPath", '/ve')
    $output = & reg.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    foreach ($line in $output) {
        if ($line -match '^\s*\(Default\)\s+REG_SZ\s+(.+)\s*$') {
            return $matches[1]
        }
    }
    return $null
}

# ——————————————
# Main Loop
# ——————————————
foreach ($c in $ComputerList) {
    Write-Host "`n=== $c ===" -ForegroundColor Cyan

    # 1) Ensure Remote Registry
    if (-not (Ensure-RemoteRegistry -Computer $c)) {
        Write-Host "  Skipping $c" -ForegroundColor Yellow
        continue
    }

    # 2) List interactive users
    $interactive = Get-InteractiveUsers -Computer $c
    if ($interactive.Count) {
        Write-Host "  Interactive session(s): $($interactive -join ', ')"
    }

    # 3) Enumerate loaded HKU hives (excluding _Classes)
    $sids = Get-LoadedUserSids -Computer $c
    if (-not $sids) {
        Write-Warning "  No loaded user hives on $c."
    }

    $foundAny = $false

    foreach ($sid in $sids) {
        # 4) Translate SID to DOMAIN\User
        try {
            $ntObj    = New-Object System.Security.Principal.SecurityIdentifier($sid)
            $userName = $ntObj.Translate([System.Security.Principal.NTAccount]).Value
        }
        catch {
            $userName = $sid
        }

        # 5) Query per-user ProgId
        $progId = Query-ProgId -Computer $c -Sid $sid
        if ($progId) {
            $foundAny = $true
            switch ($progId) {
                'ChromeHTML'    { $name = 'Google Chrome'; break }
                'MSEdgeHTM'     { $name = 'Microsoft Edge'; break }
                'FirefoxURL'    { $name = 'Mozilla Firefox'; break }
                default         { $name = $progId }
            }
            Write-Host "  [$userName] ProgId = $progId ($name)"
        }
        else {
            Write-Host "  [$userName] No explicit per-user default browser set."
        }
    }

    # 6) Fallback to machine-wide setting if no per-user found
    if (-not $foundAny) {
        $machine = Query-MachineDefault -Computer $c
        if ($machine) {
            Write-Host "  → Machine-wide default browser client: $machine"
        }
        else {
            Write-Host "  → No machine-wide default browser found."
        }
    }
}
