# BossRaidV1 — co-op boss raid for UT2004

Everyone shares one team and fights an endless series of giant WarLord
titans. Each titan is tougher than the last.

## The titan

- **Scaling**: titan #N has `BossBaseHealth + (N-1) x BossHealthPerKill`
  health and is drawn at `BossScale` (2.6x).
- **Phases**: at 66% health it enrages (AoE cadence up, damage x1.5);
  at 33% it enters a fury (AoE damage x2, four adds spawn, faster adds).
- **Telegraphed AoE**: every `AoEInterval` seconds the titan winds up
  (Strike anim) and 1.4s later blasts everything in `AoERadius` for
  `AoEDamage`. Get clear!
- **Adds**: Skaarj, Krall, Elite Krall and Brutes spawn up to `MaxAdds`
  at a time and hunt players with grudge AI.
- **Fights are endless**: kill a titan, wait `BossRespawnDelay` seconds,
  and the next one (bigger) spawns. Players always respawn.

## Running

```
ucc server DM-Rankin?game=BossRaidV1.BossRaidGame -ini=UT2004BossRaid.ini
```

or `RunServerBossRaid.bat` (auto-restarts on crash).

## Configuration (System\BossRaidV1.ini)

`[BossRaidV1.BossRaidGame]` — titan health/scaling, add cadence and cap,
phase thresholds, AoE damage/radius/interval, respawn delay.

URL options: `?BossBaseHealth=`, `?BossHealthPerKill=`, `?AoEDamage=`,
`?MaxAdds=`, `?TimeLimit=`.

## Notes & v1 limitations

- The titan uses stock WarLord attacks (rockets + melee) plus the
  game-driven AoE.
- Bots are not supported yet (they won't attack the titan). Default
  `InitialBots=0`.
- No boss health bar HUD yet — phase announcements via center messages.
