# Changelog

All notable changes to XPLedger are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-10-03

### Fixed

- The game froze with "script ran too long" when opening the main window while a
  level progress graph was flat.
- A renamed character, or a WoW: Forever character whose surname was read late,
  started a new empty record instead of keeping its history. Characters are now also
  matched by their GUID, and a record saved without a surname can no longer be
  claimed by another character with the same first name.
- The *Stats* tab ignored the running session until the next login, did not update
  after a death and did not refresh while no experience was gained.

## [0.1.0] - 2026-10-03

First release.

### Added

- Experience tracking with a rolling XP/hour rate, session rate and time-to-level
  estimate, plus the kills, quests and runs left to level up.
- Source attribution of every gain (monsters, quests, exploration, pet battles, other)
  and of the activity (open world, dungeons, raids, battlegrounds, scenarios, delves).
- Per-level history with played time, real time, XP and main source of every level.
- Movable, lockable launcher bar with level, time to level, XP bar with rested overlay
  and the experience of completed quests waiting to be turned in.
- Main window with the *Overview*, *Levels*, *Characters*, *Sources*, *Runs* and
  *Stats* tabs:
  - *Levels*: cumulative played time line, optional comparison with another
    character, per-level table and pace tiles.
  - *Characters*: every tracked character with an estimate of the rested experience
    earned while offline.
  - *Runs*: dungeon, delve and scenario runs with their duration, XP and XP/hour, and a
    *Records* mode with the level goal and the account records.
  - *Stats*: over forty statistics of a character or of the whole account, split in
    *Summary*, *When*, *Where* and *Prey*.
- Level goal with an optional deadline and an experience goal per session.
- Alerts for reached goals, beaten records, an empty rested pool and every 10 levels.
- Session summaries: the last session is printed at login and `/xpl session` compares
  the current one with the previous.
- CSV export of a character's levels and runs.
- Passive mode at the level cap.
- Native Blizzard and minimal interface styles.
- Options panel, LibDataBroker feed and addon compartment entry.
- English and Spanish localization.
- Support for Retail (Midnight), WoW: Forever, Classic Era / Anniversary and the
  Classic progression realms from a single package.

[0.1.1]: https://github.com/enylrad/XPLedger/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/enylrad/XPLedger/releases/tag/v0.1.0
