@echo off
:10
ucc server DM-Rankin?game=BossRaidV1.BossRaidGame?Mutator=ServerBrowserGametypeOverrideV1.MutServerBrowserGametypeOverride -ini=UT2004BossRaid.ini -log=BossRaid_server.log
copy BossRaid_server.log BossRaid_servercrash.log
goto 10
