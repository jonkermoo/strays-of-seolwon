# Decision log

One entry per decision: date, decision, reason.

- Code lives in files and syncs to Studio with Rojo. Studio is a viewer only.
- 2026-11-17: Two places. A light entry place routes players; every campaign is a reserved server of the campaign place, so an empty campaign can freeze and be re-entered later (public servers can't be re-entered).
- 2026-11-17: Marks save in one DataStore record per player with a session lock (UpdateAsync; lock refreshed by every autosave, stale after 150 s). Saves merge with what is stored, so marks never go down. A separate ordered store keeps each player's highest marks and is re-applied on load.
- 2026-11-17: The 100-mark release code is granted once when the player finishes the menu guide. The guide opens on first join and can be closed and reopened. No tutorial place.
- 2026-11-17: One marks gate per item: unlocked = equippable = craftable (with the right bench, class and server condition).
- 2026-11-17: Auto-match: friends first, then fill the fullest server to ~20, then the emptiest under ~45, then wake the newest frozen campaign; a new Day 0 only when nothing is frozen.
- 2026-11-17: Public campaigns end after 24 h frozen. Private servers' campaigns freeze but never end; the owner can reset to Day 0.
