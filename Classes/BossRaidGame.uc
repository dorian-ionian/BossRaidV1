//=============================================================================
// BossRaidGame
//
// Co-op boss raid for UT2004. All players share team 0 and fight an
// endless series of giant WarLord titans. Each titan has more health
// than the last, enrages at 66% and 33% health (attack cadence up,
// periodic AoE blasts), and summons adds that hunt the players down.
//=============================================================================
class BossRaidGame extends xTeamGame
    config(BossRaidV1);

//------------------------------------------------------------------------------
// Configurable settings (System\BossRaidV1.ini)
//------------------------------------------------------------------------------
var() config int    BossBaseHealth;     // titan #1 health (default 4000)
var() config int    BossHealthPerKill;  // extra health per titan killed (default 1500)
var() config float  BossScale;          // titan draw scale (default 2.6)
var() config float  AddInterval;        // seconds between add spawns (default 20)
var() config int    MaxAdds;            // add cap on the field (default 6)
var() config float  Phase2Pct;          // enrage threshold (default 0.66)
var() config float  Phase3Pct;          // fury threshold (default 0.33)
var() config float  AoEInterval;        // seconds between AoE blasts (default 14)
var() config int    AoEDamage;          // AoE blast damage (default 120)
var() config float  AoERadius;          // AoE blast radius (default 650)
var() config float  BossRespawnDelay;   // seconds between titans (default 8)

const PHASE_IDLE   = 0;
const PHASE_FIGHT  = 1;

var int  Phase;
var int  BossKills;
var float PhaseClock;
var float AddClock;
var float AoEClock;
var float BossRespawnClock;
var bool bShowStarted;
var bool bDriverActive;
var bool bPhase2;
var bool bPhase3;

var RaidBoss Boss;
var array<PlayerStart> StartSpots;

//==============================================================================
// Initialization
//==============================================================================

event InitGame(string Options, out string Error)
{
    Super.InitGame(Options, Error);

    BossBaseHealth    = Max(500, GetIntOption(Options, "BossBaseHealth", default.BossBaseHealth));
    BossHealthPerKill = Max(0, GetIntOption(Options, "BossHealthPerKill", default.BossHealthPerKill));
    AoEDamage         = Max(20, GetIntOption(Options, "AoEDamage", default.AoEDamage));
    MaxAdds           = Max(0, GetIntOption(Options, "MaxAdds", default.MaxAdds));

    TimeLimit = Clamp(GetIntOption(Options, "TimeLimit", TimeLimit), 0, 480);
    RemainingTime = 60 * TimeLimit;
    if (GameReplicationInfo != None)
        GameReplicationInfo.TimeLimit = TimeLimit;

    MaxLives = 0;          // the raid never kicks you out
    bForceRespawn = true;  // respawn right away when the titan drops you
    bWaitForNetPlayers = false;
    MinNetPlayers = 0;

    log("BossRaid: init - titan " $ BossBaseHealth $ "hp (+" $ BossHealthPerKill
        $ "/kill) adds " $ AddInterval $ "s/" $ MaxAdds, 'BossRaidV1');
}

event PreBeginPlay()
{
    Super.PreBeginPlay();
    if (GameReplicationInfo != None)
    {
        GameReplicationInfo.bNoTeamSkins = true;   // co-op: everyone is one team
        GameReplicationInfo.bForceNoPlayerLights = true;
    }
}

function PostBeginPlay()
{
    Super.PostBeginPlay();
    CollectStartSpots();
    if (Role == ROLE_Authority)
    {
        bDriverActive = (Spawn(class'BossRaidDriver') != None);
        if (!bDriverActive)
            log("BossRaid: could not spawn driver", 'BossRaidV1');
    }
}

function CollectStartSpots()
{
    local PlayerStart P;
    StartSpots.Length = 0;
    foreach AllActors(class'PlayerStart', P)
    {
        if (InStr(string(P.Class), "ONSPlayerStart") != -1)
            continue;
        StartSpots[StartSpots.Length] = P;
    }
    if (StartSpots.Length == 0)
        foreach AllActors(class'PlayerStart', P)
            StartSpots[StartSpots.Length] = P;
}

function vector GetLevelCenter()
{
    local int i;
    local vector C;
    if (StartSpots.Length == 0)
        return vect(0, 0, 200);
    for (i = 0; i < StartSpots.Length; i++)
        C += StartSpots[i].Location;
    C /= StartSpots.Length;
    C.Z += 120;
    return C;
}

// Everyone joins as team 0 - the raid is co-op.
function byte PickTeam(byte num, Controller C)
{
    return 0;
}

function UnrealTeamInfo GetBotTeam(optional int TeamBots)
{
    return Teams[0];
}

//==============================================================================
// Show flow
//==============================================================================

function StartMatch()
{
    Super.StartMatch();
    StartShow();
}

function StartShow()
{
    if (bShowStarted)
        return;
    bShowStarted = true;
    Phase = PHASE_IDLE;
    RemainingTime = 60 * TimeLimit;
    if (GameReplicationInfo != None)
        GameReplicationInfo.RemainingTime = RemainingTime;
    Phase = PHASE_FIGHT;
    PhaseClock = 0;
    AddClock = 0;
    AoEClock = 0;
    BossRespawnClock = 0;
    SpawnBoss();
}

//==============================================================================
// Boss & adds
//==============================================================================

function Pawn FindNearestPlayerPawn()
{
    local Pawn Best;
    local float bd, d;
    local Controller C;

    bd = 99999999.0;
    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        if (C.Pawn == None || C.Pawn.Health <= 0 || C.Pawn.bDeleteMe)
            continue;
        if (C.PlayerReplicationInfo == None || C.PlayerReplicationInfo.bOnlySpectator)
            continue;
        d = VSize(C.Pawn.Location - GetLevelCenter());
        if (d < bd)
        {
            bd = d;
            Best = C.Pawn;
        }
    }
    return Best;
}

function SpawnBoss()
{
    local int i, BestI;
    local float bd, d;
    local RaidMonsterController C;
    local Pawn T;

    if (StartSpots.Length > 0)
    {
        bd = -1;
        for (i = 0; i < StartSpots.Length; i++)
        {
            d = VSize(StartSpots[i].Location - GetLevelCenter());
            if (d > bd)
            {
                bd = d;
                BestI = i;
            }
        }
        Boss = Spawn(class'RaidBoss', Self,, StartSpots[BestI].Location + vect(0, 0, 80));
    }
    else
        Boss = Spawn(class'RaidBoss', Self,, GetLevelCenter());

    if (Boss == None)
    {
        log("BossRaid: could not spawn the titan!", 'BossRaidV1');
        return;
    }
    Boss.DeactivateSpawnProtection();
    Boss.HealthMax = BossBaseHealth + BossKills * BossHealthPerKill;
    Boss.Health = Boss.HealthMax;
    Boss.SetDrawScale(BossScale);
    Boss.AoEDamage = AoEDamage;
    Boss.AoERadius = AoERadius;

    if (Boss.Controller != None)
        Boss.Controller.Destroy();
    C = Spawn(class'RaidMonsterController');
    if (C != None)
    {
        C.Possess(Boss);
        C.InitializeSkill(7.0);
        C.bIsAdd = false;
        T = FindNearestPlayerPawn();
        if (T != None)
            C.SetGrudge(T);
    }
    bPhase2 = false;
    bPhase3 = false;
    Broadcast(Self, "A TITAN AWAKENS - TITAN #" $ (BossKills + 1) $ " WITH " $ Boss.HealthMax
        $ " HEALTH! DESTROY IT!", 'CriticalEvent');
    log("BossRaid: titan #" $ (BossKills + 1) $ " spawned at " $ Boss.Location $ " hp=" $ Boss.HealthMax, 'BossRaidV1');
}

function int CountAdds()
{
    local RaidMonsterController C;
    local int n;

    foreach DynamicActors(class'RaidMonsterController', C)
        if (C.bIsAdd && C.Pawn != None && C.Pawn.Health > 0 && !C.Pawn.bDeleteMe)
            n++;
    return n;
}

function SpawnAdd()
{
    local class<Monster> MC;
    local int r;
    local NavigationPoint S;
    local Monster M;
    local RaidMonsterController C;
    local Pawn T;

    r = Rand(4);
    if (r == 0)
        MC = class'SkaarjPack.Skaarj';
    else if (r == 1)
        MC = class'SkaarjPack.Krall';
    else if (r == 2)
        MC = class'SkaarjPack.EliteKrall';
    else
        MC = class'SkaarjPack.Brute';

    S = FindPlayerStart(None, 1);
    if (S == None)
        return;
    M = Spawn(MC,,, S.Location + vect(0, 0, 30), S.Rotation);
    if (M == None)
        return;
    M.DeactivateSpawnProtection();
    M.HealthMax = M.Health;
    if (M.Controller != None)
        M.Controller.Destroy();
    C = Spawn(class'RaidMonsterController');
    if (C != None)
    {
        C.bIsAdd = true;
        C.Possess(M);
        C.InitializeSkill(7.0);
        T = FindNearestPlayerPawn();
        if (T != None)
            C.SetGrudge(T);
    }
    log("BossRaid: add spawned - " $ M.Class $ " (" $ CountAdds() $ " on field)", 'BossRaidV1');
}

function CleanupAdds()
{
    local RaidMonsterController C;

    foreach DynamicActors(class'RaidMonsterController', C)
    {
        if (C.bIsAdd)
        {
            if (C.Pawn != None)
                C.Pawn.Destroy();
            C.Destroy();
        }
    }
}

//==============================================================================
// Per-second supervision (driven by BossRaidDriver)
//==============================================================================

function RoundTick()
{
    local float Pct;

    if (Phase != PHASE_FIGHT)
        return;

    if (Boss == None || Boss.Health <= 0 || Boss.bDeleteMe)
    {
        BossRespawnClock = BossRespawnClock + 1.0;
        if (BossRespawnClock >= BossRespawnDelay)
        {
            BossRespawnClock = 0;
            SpawnBoss();
        }
        return;
    }

    PhaseClock = PhaseClock + 1.0;
    Pct = Boss.Health / Boss.HealthMax;

    // phase 3: fury
    if (!bPhase3 && Pct < Phase3Pct)
    {
        bPhase3 = true;
        Broadcast(Self, "THE TITAN IS IN A FURY - GET CLEAR!", 'CriticalEvent');
        SpawnAdd();
        SpawnAdd();
        SpawnAdd();
        SpawnAdd();
        AddClock = 0;
        AoEClock = 0;
    }
    // phase 2: enrage
    else if (!bPhase2 && Pct < Phase2Pct)
    {
        bPhase2 = true;
        Broadcast(Self, "THE TITAN IS ENRAGED!", 'CriticalEvent');
        AddClock = 0;
        AoEClock = 0;
    }

    // adds trickle in
    AddClock = AddClock + 1.0;
    if (AddClock >= AddInterval && CountAdds() < MaxAdds)
    {
        AddClock = 0;
        SpawnAdd();
    }

    // periodic telegraphed AoE blast
    AoEClock = AoEClock + 1.0;
    if (AoEClock >= AoEInterval)
    {
        AoEClock = 0;
        if (Boss != None && Boss.Health > 0)
        {
            if (bPhase3)
                Boss.AoEDamage = AoEDamage * 2;
            else if (bPhase2)
                Boss.AoEDamage = int(AoEDamage * 1.5);
            else
                Boss.AoEDamage = AoEDamage;
            Broadcast(Self, "TITAN WIND-UP - GET OUT OF THE BLAST ZONE!", 'CriticalEvent');
            log("BossRaid: titan AoE blast - dmg " $ Boss.AoEDamage $ " radius " $ int(Boss.AoERadius), 'BossRaidV1');
            Boss.DoAoE();
        }
    }
}

//==============================================================================
// Combat events
//==============================================================================

function Killed(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> damageType)
{
    if (KilledPawn == Boss)
    {
        BossKills++;
        CleanupAdds();
        Broadcast(Self, "TITAN #" $ BossKills $ " HAS FALLEN! THE NEXT ONE IS ALREADY ON ITS WAY...", 'CriticalEvent');
        TeamScoreEvent(0, 10, "boss_kill");
        Boss = None;
        BossRespawnClock = 0;
        bPhase2 = false;
        bPhase3 = false;
    }
    Super.Killed(Killer, Killed, KilledPawn, damageType);
}

function int ReduceDamage(int Damage, pawn injured, pawn instigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
    local RaidMonsterController CI, CS;

    // the boss and its adds never damage each other
    CI = RaidMonsterController(injured.Controller);
    CS = RaidMonsterController(instigatedBy.Controller);
    if (CI != None && CS != None)
        return 0;
    return Super.ReduceDamage(Damage, injured, instigatedBy, HitLocation, Momentum, DamageType);
}

// Respawn away from the titan if possible.
function NavigationPoint FindPlayerStart(Controller Player, optional byte InTeam, optional string incomingName)
{
    local int i, BestI;
    local float bd, d;

    if (Boss != None && Boss.Health > 0 && StartSpots.Length > 0)
    {
        bd = -1;
        for (i = 0; i < StartSpots.Length; i++)
        {
            d = VSize(StartSpots[i].Location - Boss.Location);
            if (d > bd)
            {
                bd = d;
                BestI = i;
            }
        }
        return StartSpots[BestI];
    }
    return Super.FindPlayerStart(Player, InTeam, incomingName);
}

defaultproperties
{
     GameName="Boss Raid"
     Description="Co-op raid: giant WarLord titans with phases, AoE blasts and adds. Every titan is tougher than the last - how long can your squad survive?"
     Acronym="BRS"
     MapPrefix="DM"
     MapListType="BossRaidV1.MapListBossRaid"
     HUDType="XInterface.HudCTeamDeathMatch"
     InitialBots=0

     BossBaseHealth=4000
     BossHealthPerKill=1500
     BossScale=2.600000
     AddInterval=20.000000
     MaxAdds=6
     Phase2Pct=0.660000
     Phase3Pct=0.330000
     AoEInterval=14.000000
     AoEDamage=120
     AoERadius=650.000000
     BossRespawnDelay=8.000000
     bBalanceTeams=True
     bPlayersBalanceTeams=True
}
