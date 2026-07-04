/**
 * AppLauncher.js — analizador de archivos .desktop para el lanzador de apps
 *
 * Parte de com.github.yahir.systempanel (plasmoide de Plasma 6)
 * Destino: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 *
 * .pragma library convierte este módulo en un singleton compartido: todas las
 * instancias QML que lo importan usan el mismo heap JS, así que el estado
 * global es seguro para nuestra única instancia de ApplicationLauncher.
 *
 * ── Protocolo de carga en dos pasos ──────────────────────────────────────────
 *
 *   La parte QML (ApplicationLauncher.qml) se encarga del Paso 1 porque no es
 *   posible listar directorios desde un módulo .pragma library con
 *   XMLHttpRequest (XHR puede leer archivos individuales, pero no enumerar
 *   el contenido de carpetas).
 *
 *   Paso 1 — QML ejecuta un comando de shell mediante un DataSource ejecutable:
 *
 *       find /usr/share/applications /usr/local/share/applications
 *            $HOME/.local/share/applications -maxdepth 1 -name '*.desktop'
 *            2>/dev/null | head -400
 *
 *   Paso 2 — QML pasa el arreglo de rutas resultante a este módulo:
 *
 *       AppLauncher.processDesktopFiles(appModel, paths, doneCallback)
 *
 *   Este módulo abre un XMLHttpRequest asíncrono por cada ruta, analiza la
 *   sección [Desktop Entry] de cada archivo, valida la entrada y la agrega al
 *   ListModel recibido. doneCallback() se invoca cuando todas las solicitudes
 *   XHR pendientes ya terminaron, con éxito o con error.
 *
 * ── Forma de cada entrada del modelo ─────────────────────────────────────────
 *
 *   {
 *     name:        string   — nombre visible (por ejemplo, "Firefox Web Browser")
 *     icon:        string   — nombre de icono del tema o ruta absoluta
 *     exec:        string   — comando de shell sin códigos de campo
 *     description: string   — valor de Comment= (puede estar vacío)
 *     categories:  string   — valor de Categories= separado por punto y coma
 *   }
 */

.pragma library

// ── Estado a nivel de módulo ─────────────────────────────────────────────────
//
// These variables are intentionally module-global.  They are safe because:
//   • The plasmoid has exactly one ApplicationLauncher instance.
//   • processDesktopFiles() is called once per session (on Component.onCompleted).
//   • The variables are reset at the start of each call, so a reload works too.

/// Referencia al ListModel de QML que se está llenando.
var _model = null

/// Número de lecturas XMLHttpRequest todavía activas.
var _pending = 0

/// Callback opcional que se invoca cuando _pending llega a 0.
var _doneCallback = null

/// Mapa de deduplicación: cleanExec → true.
/// Evita que la misma aplicación aparezca dos veces cuando existe tanto en una
/// ubicación del sistema (/usr/share/applications) como en una variante del
/// usuario ($HOME/.local/share/applications).
var _seen = {}


// ══════════════════════════════════════════════════════════════════════════════
//  API pública
// ══════════════════════════════════════════════════════════════════════════════

/**
 * processDesktopFiles(model, filePaths, doneCallback)
 *
 * Punto de entrada llamado por ApplicationLauncher.qml después de que el
 * comando `find` devuelve una lista de rutas absolutas de archivos *.desktop.
 *
 * @param {ListModel} model          — QML ListModel to populate
 * @param {string[]}  filePaths      — absolute paths from the find command
 * @param {function}  [doneCallback] — called (once) when all reads settle
 */
function processDesktopFiles(model, filePaths, doneCallback) {
    // Reinicia todo el estado del módulo para esta sesión.
    _model        = model
    _doneCallback = doneCallback || null
    _seen         = {}

    // Elimina las cadenas vacías que String.split() puede producir en los bordes.
    var validPaths = filePaths.filter(function(p) {
        return p.trim() !== ""
    })

    if (validPaths.length === 0) {
        if (_doneCallback) _doneCallback()
        return
    }

    // Fija el contador antes de emitir peticiones para evitar una carrera en
    // la que el primer XHR termine antes de tiempo y dispare el callback.
    _pending = validPaths.length

    for (var i = 0; i < validPaths.length; i++) {
        _readDesktopFile(validPaths[i].trim())
    }
}


// ══════════════════════════════════════════════════════════════════════════════
//  Ayudantes privados
// ══════════════════════════════════════════════════════════════════════════════

/**
 * _readDesktopFile(filePath)
 *
 * Realiza un GET asíncrono para `file://<filePath>`.
 * Si funciona, pasa el texto recibido a _parseDesktopFile().
 * Disminuye _pending tanto en éxito como en error y dispara _doneCallback
 * cuando la última solicitud pendiente termina.
 *
 * Nota sobre los códigos de estado para URLs file:// en el motor QML de Qt:
 *   una lectura exitosa devuelve estado 0 (no 200), así que aceptamos ambos.
 *
 * @param {string} filePath — ruta POSIX absoluta (sin prefijo file://)
 */
function _readDesktopFile(filePath) {
    if (!filePath) {
        _decrementPending()
        return
    }

    var xhr = new XMLHttpRequest()

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return

        // status 0 = éxito con file:// en XHR de Qt; status 200 = éxito HTTP.
        if (xhr.status === 0 || xhr.status === 200) {
            _parseDesktopFile(xhr.responseText)
        }
        // Omite en silencio los archivos que no se pueden leer
        // (permisos, enlaces rotos, etc.).

        _decrementPending()
    }

    // Asíncrono: retorna de inmediato; el callback corre en el event loop de Qt.
    xhr.open("GET", "file://" + filePath, true)
    xhr.send()
}

/**
 * _decrementPending()
 *
 * Disminuye el contador de peticiones activas y dispara _doneCallback si esta
 * era la última solicitud pendiente. Se separa en un ayudante para mantener la
 * lógica en un solo lugar sin importar si la lectura tuvo éxito o falló.
 */
function _decrementPending() {
    _pending--
    if (_pending <= 0 && _doneCallback) {
        // Protección: nunca se dispara más de una vez aunque el contador baje.
        var cb = _doneCallback
        _doneCallback = null
        cb()
    }
}

/**
 * _parseDesktopFile(content)
 *
 * Analiza el texto bruto de un archivo .desktop y agrega una entrada válida
 * de Application a _model.
 *
 * Reglas de análisis:
 *   • Solo lee la sección [Desktop Entry]; se detiene al encontrar la siguiente.
 *   • Omite variantes localizadas (por ejemplo, "Name[de]=") para evitar que
 *     sobrescriban el nombre canónico.
 *   • Rechaza entradas donde Type != Application o donde Type no exista.
 *   • Rechaza entradas con Hidden=true o NoDisplay=true.
 *   • Rechaza entradas sin Name o Exec.
 *   • Elimina códigos de campo XDG (%U, %f, %i, %k, %c, %d, …) del valor Exec
 *     porque el motor ejecutable del DataSource lanza comandos directos y no
 *     entiende URI de documentos ni títulos de ventanas.
 *   • Deduplica por el Exec limpio para que las apps sobrescritas por el
 *     usuario ($HOME/.local/…) no aparezcan dos veces.
 *
 * @param {string} content — texto bruto de un archivo .desktop
 */
function _parseDesktopFile(content) {
    if (!content || content.trim() === "") return

    // ── Estado del parser ────────────────────────────────────────────────────
    var name        = ""
    var icon        = ""
    var exec        = ""
    var description = ""
    var categories  = ""
    var type        = ""
    var hidden      = false
    var noDisplay   = false
    var inSection   = false   // true only while inside [Desktop Entry]

    var lines = content.split("\n")

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]

        // ── Encabezado de sección ─────────────────────────────────────────────
        if (line.charAt(0) === "[") {
            if (line.indexOf("[Desktop Entry]") === 0) {
                inSection = true
            } else if (inSection) {
                // Ya salimos de [Desktop Entry]; no hace falta seguir leyendo.
                break
            }
            continue
        }

        if (!inSection) continue

        // ── Líneas en blanco y comentarios ───────────────────────────────────
        var trimmed = line.trim()
        if (trimmed === "" || trimmed.charAt(0) === "#") continue

        // ── Parseo Key=Value ───────────────────────────────────────────────────
        var eqIdx = line.indexOf("=")
        if (eqIdx < 1) continue

        var key = line.substring(0, eqIdx).trim()
        // El valor conserva espacios por ahora; se recorta al guardar.
        var val = line.substring(eqIdx + 1)

        // Omite variantes localizadas (por ejemplo, "Name[es]", "Comment[fr]");
        // solo queremos la clave canónica sin sufijo para obtener el valor base.
        if (key.indexOf("[") !== -1) continue

        // Asigna cada clave a su variable correspondiente.
        switch (key) {
            case "Name":       name        = val.trim(); break
            case "Icon":       icon        = val.trim(); break
            case "Exec":       exec        = val;        break  // trim later after stripping codes
            case "Comment":    description = val.trim(); break
            case "Categories": categories  = val.trim(); break
            case "Type":       type        = val.trim(); break
            case "Hidden":     hidden      = (val.trim() === "true"); break
            case "NoDisplay":  noDisplay   = (val.trim() === "true"); break
            // TryExec, Path, StartupNotify, etc. se ignoran a propósito.
        }
    }

    // ── Validación ───────────────────────────────────────────────────────────

    // Debe tener un nombre visible y un comando de lanzamiento.
    if (!name || !exec) return

    // Solo muestra entradas Application (se omiten Link, Directory, etc.).
    // Se permite Type vacío porque algunos .desktop antiguos no lo incluyen.
    if (type !== "" && type !== "Application") return

    // Respeta las banderas Hidden / NoDisplay.
    if (hidden || noDisplay) return

    // ── Clean up the Exec string ──────────────────────────────────────────────
    // Remove XDG field codes: %f %F %u %U %i %c %k %d %D %n %N %v %m
    var cleanExec = exec.replace(/ ?%[a-zA-Z]/g, "").trim()
    if (!cleanExec) return

    // ── Deduplication ─────────────────────────────────────────────────────────
    if (_seen[cleanExec]) return
    _seen[cleanExec] = true

    // ── Append to model ───────────────────────────────────────────────────────
    if (_model) {
        _model.append({
            name:        name,
            icon:        icon || "application-x-executable",  // fallback icon
            exec:        cleanExec,
            description: description,
            categories:  categories
        })
    }
}
