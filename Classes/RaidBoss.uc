//=============================================================================
// RaidBoss
// The titan: a giant WarLord with telegraphed AoE blast attacks. The game
// scales its health, calls DoAoE() on a schedule and announces phases.
//=============================================================================
class RaidBoss extends WarLord;

var float AoEDamage;
var float AoERadius;
var bool bTelegraphing;

// Telegraph then blast: the Strike anim plays, and the Timer detonates
// the AoE at the boss's location.
function DoAoE()
{
    if (bTelegraphing || Health <= 0)
        return;
    bTelegraphing = true;
    SetAnimAction('Strike');
    SetTimer(1.4, false);
}

function Timer()
{
    Super.Timer();
    if (bTelegraphing)
    {
        bTelegraphing = false;
        HurtRadius(AoEDamage, AoERadius, class'RaidBossDamage', 70000, Location);
    }
}

defaultproperties
{
     bBoss=True
}
