# Strays of Seolwon

```
rokit install            # installs pinned tools from rokit.toml
./scripts/check.sh       # or scripts\check.ps1 on Windows: the 4 checks (builds both places)
```

## Two places
| Place | Project file | What it is |
|---|---|---|
| Entry (start place) | `entry.project.json` | Light menu: Play (auto-match), server list. A private server here routes to its own campaign. |
| Campaign | `default.project.json` | The map. Every campaign is a reserved server of this place. |

Place ids go in `src/shared/Config/Servers.luau` (`EntryPlaceId`, `CampaignPlaceId`) and `roblox.json`.
Until then everything runs in Studio on in-memory stores.

## Layout
- `src/shared/Config/` tunable numbers: `Progression` (marks, classes, guns, items, vehicles, rank patch, mark sources), `Servers` (matchmaking, lifecycle, saving), `Guide`.
- `src/shared/Rules/` pure logic, tested in Lune (`tests/*.spec.luau`): `Unlocks`, `PlayerSave`, `SessionLock`, `Campaign`, `Matchmaker`, `FarmGuard`, `MemoryBackend`.
- `src/serverlib/` server code both places share: `Stores` (DataStore / MemoryStore or in-memory), `Campaigns` (server list, campaign records, private campaigns, teleports, auto-match).
- `src/server/` campaign server: `PlayerData` (session-locked saves, marks API), `CampaignHost` (day clock, freeze, end, heartbeat).
- `src/client/`, `src/entry/client/` plain debug UI only (no styled UI yet).
- Client/server messages: `src/shared/Net.luau` only.

## Studio test hooks
- Debug panel buttons: +10 / +100 marks, open guide, pick class, server list.
- On `ServerScriptService.Server`, set the attribute `FreezeForSeconds` (e.g. 3600, then 90000) to fake an empty server waking up or ending.
- Set the workspace attribute `LiveStores = true` to use real stores (published place with Studio API access).

Large binaries use Git LFS. Log every asset in `ASSETS_LICENSES.md`.
