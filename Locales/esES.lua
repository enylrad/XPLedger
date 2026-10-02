--[[----------------------------------------------------------------------------
    XPLedger - Spanish (esES, also used for esMX)
------------------------------------------------------------------------------]]

local _, ns = ...

ns.Locales = ns.Locales or {}
ns.Locales.esES = {
    -- Durations
    DURATION_UNKNOWN = "--",
    DURATION_DAYS_HOURS = "%dd %dh",
    DURATION_HOURS_MINUTES = "%dh %dm",
    DURATION_MINUTES = "%dm",
    DURATION_MINUTES_SECONDS = "%dm %ds",
    DURATION_SECONDS = "%ds",

    -- Slash command help
    HELP_HEADER = "Comandos:",
    HELP_TOGGLE = "/xpl - abre o cierra la ventana principal",
    HELP_OPTIONS = "/xpl options - abre las opciones",
    HELP_LOCK = "/xpl lock - bloquea la posición del acceso directo",
    HELP_UNLOCK = "/xpl unlock - desbloquea la posición del acceso directo",
    HELP_SHOW = "/xpl show - muestra el acceso directo",
    HELP_HIDE = "/xpl hide - oculta el acceso directo",
    HELP_RESET = "/xpl reset - devuelve el acceso directo al centro",
    HELP_HELP = "/xpl help - muestra esta ayuda",

    -- Languages
    LANGUAGE_auto = "Automático (idioma del juego)",
    LANGUAGE_enUS = "English",
    LANGUAGE_esES = "Español",

    -- Experience sources
    SOURCE_mob = "Enemigos",
    SOURCE_quest = "Misiones",
    SOURCE_exploration = "Exploración",
    SOURCE_petbattle = "Duelos de mascotas",
    SOURCE_other = "Otros",

    -- Activities (where the experience was earned)
    CONTEXT_world = "Mundo abierto",
    CONTEXT_dungeon = "Mazmorras",
    CONTEXT_raid = "Bandas",
    CONTEXT_battleground = "Campos de batalla",
    CONTEXT_scenario = "Gestas y profundidades",

    -- Shortcut button
    LEVEL_SHORT = "Nv %d",
    LAUNCHER_MAX_LEVEL = "Nivel máximo",
    LAUNCHER_IDLE = "Inactivo",
    LAUNCHER_LOCKED = "Acceso directo bloqueado. Haz clic derecho otra vez para desbloquearlo.",
    LAUNCHER_UNLOCKED = "Acceso directo desbloqueado. Arrástralo para moverlo.",
    LAUNCHER_HIDDEN = "Acceso directo oculto. Escribe /xpl show para volver a mostrarlo.",
    LAUNCHER_POSITION_RESET = "Posición del acceso directo restablecida.",

    -- Summary tooltip
    TOOLTIP_LEVEL = "Nivel %d",
    TOOLTIP_XP = "Experiencia",
    TOOLTIP_REMAINING = "Restante",
    TOOLTIP_RESTED = "Descansado",
    TOOLTIP_RATE = "XP por hora (%s)",
    TOOLTIP_RATE_SESSION = "XP por hora (sesión)",
    TOOLTIP_ETA = "Tiempo para subir",
    TOOLTIP_KILLS_TO_LEVEL = "Muertes para subir",
    TOOLTIP_QUESTS_TO_LEVEL = "Misiones para subir",
    TOOLTIP_SESSION_XP = "Experiencia de la sesión",
    TOOLTIP_SESSION_TIME = "Tiempo de sesión",
    TOOLTIP_LEVEL_TIME = "Jugado en este nivel",
    TOOLTIP_NO_DATA = "Gana algo de experiencia para obtener una estimación.",
    TOOLTIP_IDLE = "Sin experiencia reciente: estimación en pausa.",
    TOOLTIP_MAX_LEVEL = "Has alcanzado el nivel máximo.",
    TOOLTIP_XP_DISABLED = "La ganancia de experiencia está desactivada.",
    TOOLTIP_HINT_CLICK = "Clic izquierdo: ver detalles",
    TOOLTIP_HINT_LOCK = "Clic derecho: bloquear posición",
    TOOLTIP_HINT_UNLOCK = "Clic derecho: desbloquear posición",
    TOOLTIP_HINT_DRAG = "Arrastrar: mover",
    WINDOW_LAST_MINUTES = "últimos %d min",

    -- Main window
    TAB_OVERVIEW = "Resumen",
    TAB_LEVELS = "Niveles",
    TAB_CHARACTERS = "Personajes",
    TAB_SOURCES = "Fuentes",
    STAT_RATE = "XP / hora",
    STAT_ETA = "Tiempo para subir",
    STAT_SESSION_XP = "XP de la sesión",
    STAT_SESSION_TIME = "Tiempo de sesión",
    RANGE_SESSION = "Sesión",
    RANGE_DAY = "24 horas",
    RANGE_WEEK = "7 días",
    RANGE_ALL = "Todo",
    GRAPH_PROGRESS_TITLE = "Progreso de nivel",
    GRAPH_RATE_TITLE = "XP por hora en esta sesión (bloques de 5 min)",
    GRAPH_NO_DATA = "Aún no hay datos suficientes",
    GRAPH_POINT_LEVEL = "Nivel %.2f",
    VIEWING_CHARACTER = "Personaje: %s",

    -- Levels tab
    LEVELS_TITLE = "Tiempo jugado por nivel",
    LEVELS_COMPARE = "Comparar con",
    LEVELS_COMPARE_NONE = "Nadie",
    LEVELS_PARTIAL = "Registrado parcialmente",
    LEVELS_IN_PROGRESS = "En curso",
    LEVELS_TOTAL = "Total jugado",
    LEVELS_AVERAGE = "Media por nivel",
    LEVELS_FASTEST = "Nivel más rápido",
    LEVELS_SLOWEST = "Nivel más lento",
    LEVELS_EMPTY = "Todavía no hay niveles registrados para este personaje.",
    LEVEL_PLAYED = "Tiempo jugado",
    LEVEL_REAL = "Tiempo real",
    LEVEL_XP = "Experiencia registrada",

    -- Characters tab
    CHAR_COL_NAME = "Personaje",
    CHAR_COL_LEVEL = "Nivel",
    CHAR_COL_PLAYED = "Jugado",
    CHAR_COL_AVG = "Media / nivel",
    CHAR_COL_SEEN = "Última vez",
    CHAR_HINT = "Haz clic en un personaje para ver sus niveles y fuentes.",
    CHAR_CURRENT = "este personaje",
    CHAR_DELETE = "Borrar",
    CHAR_DELETE_CONFIRM = "¿Borrar todos los datos de XPLedger de %s?",
    CHAR_SEEN_NOW = "Ahora",
    CHAR_SEEN_AGO = "hace %s",

    -- Sources tab
    SOURCES_BY_SOURCE = "Por fuente",
    SOURCES_BY_CONTEXT = "Por actividad",
    SCOPE_LEVEL = "Nivel actual",
    SCOPE_ALL = "Todo lo registrado",
    SOURCES_EMPTY = "Todavía no hay experiencia registrada.",

    -- Level up summary
    DING_SUMMARY = "¡Nivel %d alcanzado en %s jugado (%s de tiempo real)!",
    DING_MAIN_SOURCE = "Fuente principal: %s (%d%%), sobre todo en %s.",

    -- Options
    OPTIONS_SUBTITLE = "Ritmo de experiencia, tiempo para subir de nivel e historial de subida.",
    OPT_SECTION_GENERAL = "General",
    OPT_LANGUAGE = "Idioma",
    OPT_RATE_WINDOW = "Ventana de cálculo",
    OPT_RATE_WINDOW_DESC = "Cuántos minutos recientes se usan para calcular tu XP por hora.",
    OPT_AFK = "Umbral de inactividad",
    OPT_AFK_DESC = "Los periodos más largos que esto sin ganar experiencia no cuentan como tiempo de juego.",
    OPT_DING_SUMMARY = "Mostrar un resumen en el chat al subir de nivel",
    OPT_PLAYED_SILENT = "Leer /played automáticamente sin mostrarlo en el chat",
    OPT_SECTION_LAUNCHER = "Acceso directo",
    OPT_LAUNCHER_SHOW = "Mostrar acceso directo",
    OPT_LAUNCHER_LOCK = "Bloquear posición",
    OPT_LAUNCHER_HIDE_MAX = "Ocultar al nivel máximo",
    OPT_LAUNCHER_PER_CHAR = "Guardar la posición por personaje",
    OPT_LAUNCHER_SCALE = "Escala",
    OPT_LAUNCHER_ALPHA = "Opacidad",
    OPT_LAUNCHER_TEXT = "Texto principal",
    OPT_RESET_POSITION = "Restablecer posición",
    TEXT_MODE_eta = "Tiempo para subir",
    TEXT_MODE_percent = "Progreso del nivel",
    TEXT_MODE_rate = "XP por hora",
    TEXT_MODE_remaining = "XP restante",
    OPT_SECTION_DATA = "Datos",
    OPT_DATA_INFO = "Personajes registrados: %d",
    OPT_RESET_CHAR = "Reiniciar este personaje",
    OPT_RESET_CHAR_CONFIRM = "¿Borrar el historial de subida de este personaje?",
    OPT_RESET_ALL = "Reiniciar todos los datos",
    OPT_RESET_ALL_CONFIRM = "¿Borrar el historial de subida de TODOS los personajes?",
    MINUTES_VALUE = "%d min",
}
