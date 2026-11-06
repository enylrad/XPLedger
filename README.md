# XPLedger

Experience and leveling manager for World of Warcraft. XPLedger watches how fast you earn
experience, estimates the time left to level up and keeps a leveling history for every
character on your account.

Supports **Retail (Midnight)**, **WoW: Forever**, **Classic Era / Anniversary** and the
**Classic progression** realms from a single package. Available in **English** and **Spanish**.

## Features

- **Shortcut**: a small, minimalist bar showing your level, the time to level (or progress,
  XP/hour or remaining XP), and a thin XP bar with the rested overlay and, in gold, the
  experience of the completed quests waiting to be turned in.
  - Drag it anywhere. **Right-click** to lock or unlock its position.
  - **Left-click** opens the main window. Hover for a detailed summary: rate, time to
    level, kills / quests / runs left, quest log experience and when the rested pool is full.
- **Main window**
  - *Overview*: XP/hour, time to level, session XP and time, level progress over time
    (session, 24 hours, 7 days or all), the XP/hour of the session in time blocks and the
    kills, quests and runs left to level up.
  - *Levels*: cumulative played time line (optionally compared against another
    character), a per-level table (played, real time, XP, main source, difference)
    and tiles for total, current level, recent pace and comparison. Hover a tile for details.
  - *Characters*: every tracked character with level, played time, average time per
    level, estimated rested experience (it keeps growing while offline) and when it was
    last seen. Export a character's levels as CSV.
  - *Sources*: experience by source (monsters, quests, exploration, pet battles, other)
    and by activity (open world, dungeons, raids, battlegrounds, scenarios and delves).
  - *Runs*: every dungeon, delve and scenario run with its duration, XP and XP/hour, and
    a *Records* mode with the level goal and the account records (fastest time of every
    level, best session, best hour, biggest gain, best run).
  - *Stats*: over forty statistics of the selected character or of the whole account.
    *Summary* (fastest and slowest level, best and longest session, deaths, rested share,
    most repeated instance...), *When* (XP per weekday and per hour, best day, streaks),
    *Where* (XP, kills, quests and XP/hour per zone) and *Prey* (most killed creatures and
    best rewarded quests). Account-wide bests name the character that holds them.
    *Friends* ranks your characters, and your friends' if you share, by deaths.
- **Friends ranking** (experimental for now; optional, off by default): Battle.net friends who use XPLedger and
  share a group code see each other's deaths in *Stats > Friends*, and can be told when one
  of them dies ("Luis just died"). The data travels hidden over Battle.net: nothing is
  written in the chat. Only your characters, levels and deaths are shared.
- **Goals and alerts**: a level goal with an optional deadline (projected from your recent
  pace) and an experience goal per session. Alerts when a goal is reached, a record is
  beaten or the rested pool runs out, plus a milestone every 10 levels.
- **Session summary**: the last session is summarized at login, and `/xpl session` compares
  the current one with the previous.
- **Level up summary** in chat: played and real time spent on the level and its main source.
- **Pet** (optional, asked on the first login): a pixel art companion that levels up with
  you. Pick a murloc hatchling or Nihil, a little Void hatchling.
  - It can cheer you on now and then (off by default, every 20 seconds to 30 minutes) with
    text in its speech bubble that fits what you are doing: fighting, low on health,
    questing, in a dungeon, swimming, fishing, flying, dancing, resting, dead, about to level
    up... Over 200 lines per pet, and none comes back until it has said the rest of its
    kind. Click it and it talks too; keep clicking and it gets
    annoyed in its own way (push Nihil too far and it turns into a Void horror for a few
    seconds). The murloc talks mostly in murloc; Nihil is a sweet pessimist, with an optional
    unfiltered voice that mocks how you play. Their language can differ from the addon's.
  - It keeps count of your deaths and tells you on each one (optional), with special lines
    on the 5th, 10th, 20th... and 100th death. With the friends ranking on, it also tells you
    when a friend of your group dies.
  - It reacts to what you do: cheers on a level up, parties on an achievement, fights in
    combat (and panics at low health where the game shows it), celebrates a win or wipes its
    brow when you run away, is knocked out when you die and floats as a ghost until you are
    back, swims, fishes and eats the catch, sleeps while you are away, rests with a mug in
    inns, jumps when you jump and copies emotes like `/dance`, `/wave` or `/roar`.
  - When nothing happens it yawns, juggles fish or scratches its head, and it gets nervous
    when the level bar is almost full.
  - It can show your experience: a bar, a text (time to level, progress, XP/hour or
    remaining XP) and a level badge. It can also open the main window on click and show the
    experience summary in its tooltip, so it can replace the shortcut. Unlike the shortcut it
    stays at the level cap (optional).
  - Drag it anywhere (or move it from Edit Mode on Retail). It has its own page in the
    options with an animated preview.
- **Options** in the game's AddOns settings: language, interface style, rate window, idle
  threshold, shortcut behavior, alerts, data reset, friends ranking.
- **Two interface styles**
  - *Blizzard* (default): built from the game's own templates, fonts and art, so the addon
    looks native in every client: Retail frames on Retail, Forever's art on Forever, the
    classic dialogs on older clients. Missing templates fall back to classic Blizzard art.
  - *Minimal*: a flat, compact look. Changing the style reloads the interface.
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
| `/xpl goal <level> [days]` | Set a level goal, optionally with a deadline |
| `/xpl goal session <xp>` | Set an experience goal per session (`0` turns it off) |
| `/xpl goal` / `/xpl goal clear` | Show or remove the level goal |
| `/xpl session` | Summary of the current session |
| `/xpl export [runs]` | Copy your levels (or runs) as CSV |
| `/xpl pet` | Show or hide the pet |
| `/xpl pet reset` / `/xpl pet demo` | Move the pet back to its place, or play every animation |
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
- **Rested experience of alts**: the pool is saved at logout and grows offline with the game
  rules: 5% of the level bar every 8 hours in an inn or city (a quarter of that elsewhere),
  up to 150%.
- **Runs**: entering a party or scenario instance starts a run; it ends when you leave.
  Coming back to the same instance within 10 minutes (a corpse run) continues it.
- **Level cap**: at the maximum level the addon goes passive. Nothing new is recorded and the
  shortcut and the Data Broker feed are hidden, but `/xpl` still opens the panel with the
  leveling history of the character and the rested experience of the alts.

### Known limitations

- Since Midnight, chat payloads can be hidden from addons while in combat or in instances.
  XPLedger never reads them in that case: experience gained in or right after combat is
  counted as monsters, which is correct for nearly every case.
- Since Midnight the kill message is often hidden in combat and in instances, so the
  creature ranking of the *Stats* tab misses those kills on Retail. The when/where/prey
  statistics start counting with the version that introduced them.
- On WoW: Forever a character is identified by first name and surname, so two characters
  with the same first name are kept apart. Characters tracked by older versions are
  matched to the first one that logs in with that first name.
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

The pets' sprite sheets (`Media/Pet/Murloc.tga` and `Media/Pet/Void.tga`) are generated from
code. Edit the drawing in `tools/pet/murloc-art.js` (the poses, shared by both) or
`tools/pet/void-art.js` and rebuild them with Node (no dependencies); the script also writes
`tools/pet/preview.png` to review the result:

```powershell
node tools/pet/build-pets.js
```

What the pets say lives in `Locales/PetPhrases_<locale>.lua`.

To share a build, package it into `XPLedger-<version>.zip` (version read from the TOC,
development files left out):

```powershell
./tools/package.ps1
```

### Structure

```
Core/     namespace and events, localization, compatibility layer, database,
          tracker (rate engine), source attribution, level history, rested estimate,
          quest log experience, instance runs, records, goals and alerts, session
          summaries, CSV export
Locales/  enUS (base) and esES (also used for esMX)
UI/       theme facade, skins (Blizzard, Minimal), launcher, tooltip, graph widget,
          main panel, views (overview, levels, characters, sources, runs, stats), murloc pet,
          options, data broker
Media/    pet sprite sheets (generated by tools/pet)
Libs/     LibStub, CallbackHandler-1.0, LibDataBroker-1.1
```

Adding a language: copy `Locales/enUS.lua`, translate the values, register it in the TOC
and add its code to `ns.AVAILABLE_LOCALES` in `Core/Locale.lua`.

## License

GNU Lesser General Public License v3.0 (LGPL-3.0). See [LICENSE](LICENSE) for the LGPL terms and [COPYING](COPYING) for the GNU GPL v3 they build on.
