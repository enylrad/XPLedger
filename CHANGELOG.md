# Changelog

All notable changes to XPLedger are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-11-04

### Added

- A second pet to choose from: Nihil, a little Void hatchling.
- Optional cheers (off by default): every so often (from 20 seconds to 30 minutes, 5 minutes
  by default) the pet says something in its speech bubble that fits what you are doing, with
  over 100 lines per pet. Clicking the pet makes it talk too, and if you keep clicking it gets
  annoyed in its own way. The murloc talks mostly in murloc; Nihil is a sweet pessimist. The
  pet's language can be set apart from the addon's.
- Unfiltered Nihil (off by default): the same Nihil with harsher lines that mock how you
  play, without swearing.
- Push Nihil past its last annoyed line and it collapses into a ball of Void that bursts
  into a hulking Void horror twice its size for a few seconds, then shrinks back.
- WoW: Forever: a level up summary in the middle of the screen with your portrait, the stats
  gained, the new abilities at your trainer and the recommended zones for your faction.
  `/xpl levelup demo` shows it with sample data.
- Scroll bars on the options pages.

### Changed

- The murloc stays a hatchling: the grown and veteran stages are gone.
- Long speech bubbles wrap onto several lines.
- The pet's tooltip opens below it (beside it near the bottom of the screen), so it no
  longer covers the speech bubble.
- `/xpl pet demo` no longer takes a stage.

### Fixed

- The pet's effects no longer create garbage on every frame.

## [0.3.0] - 2026-11-04 (Español)

### Añadido

- Una segunda mascota a elegir: Nihil, una pequeña cría del Vacío.
- Ánimos opcionales (desactivados por defecto): cada cierto tiempo (de 20 segundos a
  30 minutos, 5 minutos por defecto) la mascota dice en su bocadillo algo acorde con lo que
  estás haciendo, con más de 100 frases por mascota. Si haces clic en ella, también te
  habla, y si no paras de hacer clic se enfada a su manera. El múrloc habla casi todo en
  múrloc; Nihil es un pesimista entrañable. El idioma de la mascota puede ser distinto del del addon.
- Nihil sin filtro (desactivado por defecto): el mismo Nihil con frases más duras que se
  burlan de cómo juegas, sin palabrotas.
- Si sigues haciendo clic después de la última frase de enfado de Nihil, se comprime en una
  bola de Vacío que estalla en un horror del Vacío del doble de tamaño durante unos
  segundos, y luego vuelve a encogerse.
- WoW: Forever: un resumen de la subida de nivel en el centro de la pantalla con tu retrato,
  las estadísticas ganadas, las nuevas habilidades del instructor y las zonas recomendadas
  para tu facción. `/xpl levelup demo` lo muestra con datos de ejemplo.
- Barras de desplazamiento en las páginas de opciones.

### Cambiado

- El múrloc se queda en cría: desaparecen las fases de adulto y veterano.
- Los bocadillos largos se reparten en varias líneas.
- El tooltip de la mascota se abre debajo (al lado si está pegada al borde inferior de la
  pantalla), así que ya no tapa el bocadillo.
- `/xpl pet demo` ya no admite una fase.

### Corregido

- Los efectos de la mascota ya no generan basura en cada fotograma.

## [0.2.0] - 2026-10-11

### Added

- An optional murloc pet in pixel art that levels up with you. On the first login XPLedger
  asks whether you want it. It grows in three stages (hatchling, grown and, at the level
  cap, a veteran with a helmet).
  - It cheers when you level up, parties when you earn an achievement, fights in combat
    and panics at low health (where the game lets addons read it), celebrates a win or
    wipes its brow when you get away, is knocked out when you die and floats as a ghost
    until you are back on your feet.
  - It swims, fishes with you and eats the catch, sleeps while you are away, rests with a
    mug in inns and cities, jumps when you jump, copies emotes such as `/dance`, `/wave`,
    `/cheer`, `/roar` or `/kiss`, fidgets when nothing happens and gets nervous when the
    level bar is almost full.
  - It can show an experience bar, a text and a level badge, open the main window on
    click and show the experience summary in its tooltip, so it can replace the shortcut.
    Unlike the shortcut it stays at the level cap, unless you turn that off.
  - Drag it anywhere, or move it from Edit Mode on Retail. It has its own page in the
    options with an animated preview, and the `/xpl pet`, `/xpl pet reset` and
    `/xpl pet demo [1-3]` commands. The sprites add about 1.5 MB to the addon.

## [0.2.0] - 2026-10-11 (Español)

### Añadido

- Una mascota múrloc opcional en pixel art que sube de nivel contigo. La primera vez que
  entras, XPLedger te pregunta si la quieres. Crece en tres fases (cría, adulto y, al llegar
  al nivel máximo, veterano con casco).
  - Se alegra cuando subes de nivel, hace fiesta cuando ganas un logro, lucha en combate y
    entra en pánico con poca vida (donde el juego deja leerla), celebra la victoria o se
    seca el sudor si escapas, queda K.O. cuando mueres y flota como fantasma hasta que
    vuelves a estar en pie.
  - Bucea, pesca contigo y se come lo que sacas, duerme cuando estás ausente, descansa con
    una jarra en posadas y ciudades, salta cuando saltas, imita emotes como `/bailar`,
    `/saludar`, `/animar`, `/rugir` o `/besar`, se entretiene cuando no pasa nada y se
    pone nervioso cuando la barra de nivel está casi llena.
  - Puede mostrar una barra de experiencia, un texto y una insignia de nivel, abrir la
    ventana principal con un clic y mostrar el resumen de experiencia en su tooltip, así
    que puede sustituir al acceso directo. A diferencia de este, sigue visible a nivel
    máximo, salvo que lo desactives.
  - Puedes arrastrarla a donde quieras o moverla desde el Modo edición en Retail. Tiene su
    propia página en las opciones con una vista previa animada, y los comandos `/xpl pet`,
    `/xpl pet reset` y `/xpl pet demo [1-3]`. Los sprites añaden unos 1,5 MB al addon.

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
