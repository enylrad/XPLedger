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

## [0.1.1] - 2026-10-03 (Español)

### Corregido

- El juego se bloqueaba con "script ran too long" al abrir la ventana principal si un
  gráfico de progreso de nivel era plano.
- Un personaje renombrado, o un personaje de WoW: Forever cuyo apellido se leía tarde,
  empezaba un registro vacío en lugar de conservar su historial. Ahora los personajes
  también se reconocen por su GUID, y otro personaje con el mismo nombre de pila ya no
  puede quedarse con un registro guardado sin apellido.
- La pestaña *Estadísticas* no tenía en cuenta la sesión en curso hasta el siguiente
  inicio de sesión, no se actualizaba al morir y no se refrescaba sin ganar experiencia.

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

## [0.1.0] - 2026-10-03 (Español)

Primera versión.

### Añadido

- Seguimiento de la experiencia con ritmo de XP/hora reciente, ritmo de la sesión y
  estimación del tiempo para subir de nivel, además de los enemigos, misiones e
  instancias que faltan para subir.
- Origen de cada ganancia (enemigos, misiones, exploración, duelos de mascotas, otros) y
  de la actividad (mundo abierto, mazmorras, bandas, campos de batalla, gestas y
  profundidades).
- Historial por nivel con tiempo jugado, tiempo real, XP y fuente principal de cada nivel.
- Barra de acceso rápido movible y bloqueable con el nivel, el tiempo para subir, la
  barra de XP con la experiencia descansada y la experiencia de las misiones completadas
  pendientes de entregar.
- Ventana principal con las pestañas *Resumen*, *Niveles*, *Personajes*, *Fuentes*,
  *Instancias* y *Estadísticas*:
  - *Niveles*: línea de tiempo jugado acumulado, comparación opcional con otro
    personaje, tabla por nivel y fichas de ritmo.
  - *Personajes*: todos los personajes registrados con una estimación de la experiencia
    descansada acumulada mientras están desconectados.
  - *Instancias*: mazmorras, profundidades y gestas con su duración, XP y XP/hora, y un
    modo *Récords* con el objetivo de nivel y los récords de la cuenta.
  - *Estadísticas*: más de cuarenta estadísticas de un personaje o de toda la cuenta,
    repartidas en *Resumen*, *Cuándo*, *Dónde* y *Presas*.
- Objetivo de nivel con fecha límite opcional y objetivo de experiencia por sesión.
- Avisos al alcanzar un objetivo, batir un récord, agotar la experiencia descansada y
  cada 10 niveles.
- Resúmenes de sesión: la última sesión se muestra al conectar y `/xpl session` compara
  la actual con la anterior.
- Exportación a CSV de los niveles y las instancias de un personaje.
- Modo pasivo al llegar al nivel máximo.
- Estilos de interfaz nativo de Blizzard y minimalista.
- Panel de opciones, fuente de LibDataBroker y entrada en el menú de addons del minimapa.
- Traducción al inglés y al español.
- Soporte para Retail (Midnight), WoW: Forever, Classic Era / Anniversary y los reinos
  de progresión de Classic en un solo paquete.

[0.1.1]: https://github.com/enylrad/XPLedger/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/enylrad/XPLedger/releases/tag/v0.1.0
