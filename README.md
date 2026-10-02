# XPLedger

Experience and leveling manager for World of Warcraft. XPLedger watches how fast you earn
experience, estimates the time left to level up and keeps a leveling history for every
character on your account.

Supports **Retail (Midnight)**, **WoW: Forever**, **Classic Era / Anniversary** and the
**Classic progression** realms from a single package. Available in **English** and **Spanish**.

## Features

- **Shortcut**: a small, minimalist bar showing your level, the time to level (or progress,
  XP/hour or remaining XP), and a thin XP bar with the rested overlay.
  - Drag it anywhere. **Right-click** to lock or unlock its position.
  - **Left-click** opens the main window. Hover for a detailed summary.
- **Main window**
  - *Overview*: XP/hour, time to level, session XP and time, level progress over time
    (session, 24 hours, 7 days or all) and the XP/hour of the session in time blocks.
  - *Levels*: played time per level, with a side-by-side comparison against another
    character, plus total, average, fastest and slowest level.
  - *Characters*: every tracked character with level, played time, average time per
    level and when it was last seen.
  - *Sources*: experience by source (monsters, quests, exploration, pet battles, other)
    and by activity (open world, dungeons, raids, battlegrounds, scenarios and delves).
- **Level up summary** in chat: played and real time spent on the level and its main source.
- **Options** in the game's AddOns settings: language, rate window, idle threshold,
  shortcut behavior, data reset.
- **Data Broker** feed for Titan Panel, ElvUI, Bazooka and similar, and an entry in the
  Retail/Forever addon compartment.

## Commands

| Command | Action |
| --- | --- |
| `/xpl` | Open or close the main window |
| `/xpl options` | Open the options |
| `/xpl lock` / `/xpl unlock` | Lock or unlock the shortcut |
| `/xpl show` / `/xpl hide` | Show or hide the shortcut |
| `/xpl reset` | Move the shortcut back to the center |
| `/xpl help` | List the commands |

## How it works

- **Rate**: XP/hour over a rolling window (15 minutes by default). Gaps without experience
  longer than the idle threshold only count up to the threshold, so a break does not ruin
  the estimate. The session survives a `/reload` or a quick relog.
- **Time per level**: `/played` reports the time spent on the current level, so the played
  time of a level is exact even if the addon was installed mid-level. The reply is read
  silently (can be turned off in the options).
- **Experience sources**: the game does not say where experience comes from, so each gain is
  matched with what happened around it: the kill message, the quest turn-in, the exploration
  message, or a pet battle. The activity comes from the instance type you are in.
  Message patterns are built from the client's own strings, so it works in any language.

### Known limitations

- Since Midnight, chat payloads can be hidden from addons while in combat or in instances.
  XPLedger never reads them in that case: experience gained in or right after combat is
  counted as monsters, which is correct for nearly every case.
- Levels gained before installing the addon have no history. The level that was in progress
  when tracking started is marked as *partially tracked* (its played time is still exact).

## Development

The repository can be linked into every installed flavor with a directory junction:

```powershell
./tools/link-wow.ps1                                   # all flavors in the default WoW folder
./tools/link-wow.ps1 -WowRoot "D:\World of Warcraft"   # custom installation folder
./tools/link-wow.ps1 -Remove                           # remove the links
```

Then `/reload` in game after each change. Enable Lua errors with `/console scriptErrors 1`.

### Structure

```
Core/     namespace and events, localization, compatibility layer, database,
          tracker (rate engine), source attribution, level history
Locales/  enUS (base) and esES (also used for esMX)
UI/       theme and widgets, launcher, tooltip, graph widget, main panel,
          views (overview, levels, characters, sources), options, data broker
Libs/     LibStub, CallbackHandler-1.0, LibDataBroker-1.1
```

Adding a language: copy `Locales/enUS.lua`, translate the values, register it in the TOC
and add its code to `ns.AVAILABLE_LOCALES` in `Core/Locale.lua`.

## License

MIT
