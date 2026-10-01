# Embedded libraries

These are vendored at pinned versions so a plain checkout loads in game without the packager. `Libs/embeds.xml` loads them, and luacheck skips this folder. To update one, replace its files from the pinned source below and update the version here.

| Library | Version | Source | License |
|---|---|---|---|
| Ace3 (LibStub, CallbackHandler-1.0, AceAddon, AceEvent, AceDB, AceConsole, AceGUI, AceConfig, AceComm + ChatThrottleLib, AceSerializer) | `Release-r1403` | https://github.com/WoWUIDev/Ace3 | Limited BSD: `Ace3/LICENSE.txt` |
| LibDeflate | `1.0.2-release` | https://github.com/SafeteeWoW/LibDeflate | zlib: `LibDeflate/LICENSE.txt` |
| LibDataBroker-1.1 | `v1.1.4` | https://github.com/tekkub/libdatabroker-1-1 | No license file upstream (see below) |
| LibDBIcon-1.0 | `v12.0.3` (minor 56) | https://repos.curseforge.com/wow/libdbicon-1-0/tags/v12.0.3 | No license file upstream (see below) |

Only the Ace3 modules the add-on uses are included. AceBucket, AceDBOptions, AceHook, AceLocale, AceTab, and AceTimer are left out (timers use `C_Timer`, hooks use `hooksecurefunc`).

LibDataBroker-1.1 and LibDBIcon-1.0 are published for embedding in other add-ons, but neither upstream source ships a license file. Confirm their stated licenses on their CurseForge project pages before a public release.
