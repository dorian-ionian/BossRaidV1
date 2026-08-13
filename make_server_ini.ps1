#=============================================================================
# make_server_ini.ps1 - builds System\UT2004BossRaid.ini from the proven
# UT2004MFC.ini server template and swaps the MFC gametype for BossRaidV1.
#
# Usage: powershell -ExecutionPolicy Bypass -File .\make_server_ini.ps1
#
# Outputs:
#   System\UT2004BossRaid.ini - server ini for RunServerBossRaid.bat
#=============================================================================
$ErrorActionPreference = "Stop"
$g = "C:\Program Files (x86)\Steam\steamapps\common\Unreal Tournament 2004"
$src = "$g\System\UT2004MFC.ini"
$dst = "$g\System\UT2004BossRaid.ini"
$projIni = "$g\BossRaidV1\BossRaidV1.ini"

if (-not (Test-Path $src)) { Write-Error "Template missing: $src"; exit 1 }
if (-not (Test-Path $projIni)) { Write-Error "Project ini missing: $projIni"; exit 1 }

$lines = [System.Collections.Generic.List[string]](Get-Content $src)

#--- 1. swap gametype references -------------------------------------------
for ($i = 0; $i -lt $lines.Count; $i++)
{
    $l = $lines[$i]
    if ($l -eq "ServerPackages=MonsterFightClubV1")
        { $lines[$i] = "ServerPackages=BossRaidV1" }
    elseif ($l -eq "EditPackages=MonsterFightClubV1")
        { $lines[$i] = "EditPackages=BossRaidV1" }
    elseif ($l -match '^Games=\(GameType="MonsterFightClubV1')
        { $lines[$i] = 'Games=(GameType="BossRaidV1.BossRaidGame",ActiveMaplist="Default BRS")' }
    elseif ($l -match '^GameConfig=\(GameClass="MonsterFightClubV1')
        { $lines[$i] = 'GameConfig=(GameClass="BossRaidV1.BossRaidGame",Prefix="DM",Acronym="BRS",GameName="Boss Raid",Mutators=,Options=)' }
}

#--- 2. replace the MFC map list + maplist record blocks -------------------
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -match '^\[MonsterFightClubV1\.MapListMonsterFightClub\]') { $start = $i; break }
}
if ($start -ge 0)
{
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^\[MonsterFightClubV1\.MonsterFightClubGame\]')
        { $end++ }

    $maps = @('DM-1on1-Albatross','DM-1on1-Crash','DM-1on1-Desolation','DM-1on1-Idoma',
              'DM-1on1-Irondust','DM-1on1-Mixer','DM-1on1-Roughinery','DM-1on1-Serpentine',
              'DM-1on1-Spirit','DM-1on1-Squader','DM-1on1-Trite','DM-Antalus',
              'DM-Asbestos','DM-BP2-Calandras','DM-DesertIsle','DM-Rankin')
    $block = [System.Collections.Generic.List[string]]@('[BossRaidV1.MapListBossRaid]', 'MapNum=0')
    foreach ($m in $maps) { $block.Add("Maps=$m") }
    $block.Add('[Default BRS MaplistRecord]')
    $block.Add('DefaultTitle=Default BRS')
    $block.Add('DefaultGameType=BossRaidV1.BossRaidGame')
    $block.Add('DefaultActive=0')
    foreach ($m in $maps) { $block.Add("DefaultMaps=$m") }

    $lines.RemoveRange($start, $end - $start)
    $lines.InsertRange($start, $block)
}

#--- 3. replace the game config sections ------------------------------------
$cfgStart = -1
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -match '^\[MonsterFightClubV1\.MonsterFightClubGame\]') { $cfgStart = $i; break }
}
if ($cfgStart -ge 0)
{
    $lines.RemoveRange($cfgStart, $lines.Count - $cfgStart)

    $cfg = Get-Content $projIni
    $cfgLines = [System.Collections.Generic.List[string]]@('[BossRaidV1.BossRaidGame]')
    for ($i = 1; $i -lt $cfg.Count; $i++)
    {
        if ($cfg[$i] -match '^\[') { break }
        $cfgLines.Add($cfg[$i])
    }
    $lines.InsertRange($cfgStart, $cfgLines)
}

#--- 4. [Engine.GameInfo] - endless (TimeLimit=0) ---------------------------
$inGameInfo = -1
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -eq "[Engine.GameInfo]") { $inGameInfo = $i; break }
}
if ($inGameInfo -ge 0)
{
    for ($i = $inGameInfo + 1; $i -lt $lines.Count -and $lines[$i] -notmatch '^\['; $i++)
    {
        if ($lines[$i] -match '^TimeLimit=')  { $lines[$i] = "TimeLimit=0"; continue }
        if ($lines[$i] -match '^MaxPlayers=') { $lines[$i] = "MaxPlayers=32"; continue }
        if ($lines[$i] -match '^MaxSpectators=') { $lines[$i] = "MaxSpectators=32"; continue }
    }
}

#--- 5. Server name + redact secrets -----------------------------------------
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -match '^ServerName=')
        { $lines[$i] = "ServerName=Boss Raid (Test)" }
    elseif ($lines[$i] -match '^AdminPassword=')
        { $lines[$i] = "AdminPassword=CHANGE_ME" }
    elseif ($lines[$i] -match '^GamePassword=')
        { $lines[$i] = "GamePassword=CHANGE_ME" }
    elseif ($lines[$i] -match '^SavedPasswords=')
        { $lines[$i] = "SavedPasswords=" }
}

Set-Content -Path $dst -Value $lines -Encoding ASCII
Write-Host "Wrote $dst ($($lines.Count) lines)"
