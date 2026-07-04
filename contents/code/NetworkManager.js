/**
 * NetworkManager.js — módulo auxiliar para Wi-Fi y Bluetooth
 *
 * Módulo de ayuda en JavaScript para controlar Wi-Fi y Bluetooth desde
 * QuickSettings.qml. Envuelve comandos de shell como nmcli, rfkill y
 * bluetoothctl.
 *
 * IMPORTANTE: los módulos .js puros (.pragma library) no pueden crear objetos
 * QML, así que este módulo no puede poseer un DataSource directamente. En su
 * lugar, el llamador debe ejecutar init(execFn) una vez y pasar una función con
 * esta firma:
 *
 *   execFn(command: string, callback: function(stdout: string): void): void
 *
 * Un adaptador mínimo en QML se vería así:
 *
 *   PlasmaCore.DataSource {
 *       id: nmExec
 *       engine: "executable"
 *       connectedSources: []
 *       property var _callbacks: ({})
 *
 *       onNewData: function(sourceName, data) {
 *           var out = (data["stdout"] || "").trim()
 *           disconnectSource(sourceName)
 *           if (_callbacks[sourceName]) {
 *               _callbacks[sourceName](out)
 *               delete _callbacks[sourceName]
 *           }
 *       }
 *   }
 *
 *   function nmExecFn(cmd, cb) {
 *       nmExec._callbacks[cmd] = cb
 *       nmExec.connectSource(cmd)
 *   }
 *
 *   Component.onCompleted: NetworkManager.init(nmExecFn)
 *
 * Uso:
 *   import "../code/NetworkManager.js" as NetworkManager
 *
 * Destino: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 */

// Marca este archivo como biblioteca compartida: una sola instancia se reutiliza
// en todos los archivos QML que lo importan (el estado es global al módulo).
.pragma library

// ---------------------------------------------------------------------------
//  ESTADO DEL MÓDULO
// ---------------------------------------------------------------------------

/**
 * La función execFn inyectada por el llamador mediante init().
 * Firma: execFn(cmd: string, callback: function(stdout: string))
 * @type {function|null}
 */
var _execFn = null

// ---------------------------------------------------------------------------
//  INICIALIZACIÓN
// ---------------------------------------------------------------------------

/**
 * Debe llamarse una vez antes de cualquier otra función.
 *
 * @param {function} execFn - Shell execution helper provided by the QML caller.
 *                            See module header for the required signature.
 */
function init(execFn) {
    _execFn = execFn
}

// ---------------------------------------------------------------------------
//  INTERNAL HELPERS
// ---------------------------------------------------------------------------

/**
 * Protección que registra una advertencia y llama al callback con un valor
 * seguro cuando init() todavía no se ha ejecutado.
 *
 * @param {string}   fnName   - Calling function name, used in the warning.
 * @param {function} callback - Callback to invoke with the default value.
 * @param {*}        defVal   - Default value to pass to callback.
 * @returns {boolean} true if _execFn is missing (caller should return early).
 */
function _notReady(fnName, callback, defVal) {
    if (_execFn === null) {
        console.warn("NetworkManager." + fnName + "(): init() aún no fue llamada.")
        if (typeof callback === "function") callback(defVal)
        return true
    }
    return false
}

// ---------------------------------------------------------------------------
//  WIFI — CONSULTA DE ESTADO
// ---------------------------------------------------------------------------

/**
 * Consulta si la radio Wi-Fi está habilitada.
 *
 * Shell: nmcli radio wifi
 * Output when enabled:  "enabled"
 * Output when disabled: "disabled"
 *
 * @param {function(boolean)} callback - Called with true if WiFi is enabled.
 */
function getWifiEnabled(callback) {
    if (_notReady("getWifiEnabled", callback, false)) return

    _execFn("nmcli radio wifi", function(output) {
        callback(output.toLowerCase() === "enabled")
    })
}

// ---------------------------------------------------------------------------
//  WIFI — INTERRUPTOR
// ---------------------------------------------------------------------------

/**
 * Activa o desactiva la radio Wi-Fi.
 *
 * Shell: nmcli radio wifi on   (enabled = true)
 *        nmcli radio wifi off  (enabled = false)
 *
 * @param {boolean} enabled - Pass true to turn WiFi on, false to turn it off.
 */
function setWifiEnabled(enabled) {
    if (_notReady("setWifiEnabled", null, null)) return

    var state = enabled ? "on" : "off"
    // No hace falta callback; se lanza y se olvida. Si hace falta confirmar
    // el cambio, el llamador debe volver a consultar getWifiEnabled() luego.
    _execFn("nmcli radio wifi " + state, function(_output) {})
}

// ---------------------------------------------------------------------------
//  WIFI — ESTADO (SSID + SEÑAL)
// ---------------------------------------------------------------------------

/**
 * Obtiene el SSID y la intensidad de señal de la conexión Wi-Fi activa.
 *
 * Shell: nmcli -t -f active,ssid,signal dev wifi | grep '^yes:'
 *
 * Output format (one matching line):  "yes:MyNetwork:85"
 * When not connected the grep produces no output.
 *
 * @param {function(string, number)} callback
 *   Called with (ssid, signal) where:
 *     ssid   - Network name string, or "" when disconnected.
 *     signal - Integer 0-100, or -1 when disconnected.
 */
function getWifiStatus(callback) {
    if (_notReady("getWifiStatus", callback, ["", -1])) return

    _execFn("nmcli -t -f active,ssid,signal dev wifi | grep '^yes:'", function(output) {
        if (!output || output.length === 0) {
            // No hay conexión activa.
            callback("", -1)
            return
        }

        // Separa por ":"; nmcli -t usa ":" como separador de campos.
        // Un split simple funciona para el caso común. Si se quiere más
        // robustez, habría que limpiar los caracteres escapados antes.
        var parts = output.split(":")

        // parts[0] = "yes" (coincidencia del filtro activo)
        // parts[1] = SSID
        // parts[2] = signal strength (integer string)
        if (parts.length >= 3) {
            var ssid   = parts[1] || ""
            var signal = parseInt(parts[2], 10)
            if (isNaN(signal)) signal = 0
            callback(ssid, signal)
        } else if (parts.length === 2) {
            // Caso especial: SSID vacío, señal en parts[1].
            var signal2 = parseInt(parts[1], 10)
            if (isNaN(signal2)) signal2 = 0
            callback("", signal2)
        } else {
            callback("", 0)
        }
    })
}

// ---------------------------------------------------------------------------
//  BLUETOOTH — CONSULTA DE ESTADO
// ---------------------------------------------------------------------------

/**
 * Consulta si Bluetooth está habilitado actualmente (sin bloqueo blando).
 *
 * Shell: rfkill list bluetooth | grep -i 'soft blocked: no'
 *
 * grep devuelve una línea no vacía cuando Bluetooth NO está bloqueado
 * (= habilitado). Un resultado vacío significa que está bloqueado o ausente.
 *
 * @param {function(boolean)} callback - Called with true if Bluetooth is on.
 */
function getBluetoothEnabled(callback) {
    if (_notReady("getBluetoothEnabled", callback, false)) return

    _execFn("rfkill list bluetooth | grep -i 'soft blocked: no'", function(output) {
        // Cualquier salida no vacía significa que al menos un adaptador BT está libre.
        callback(output.trim().length > 0)
    })
}

// ---------------------------------------------------------------------------
//  BLUETOOTH — INTERRUPTOR
// ---------------------------------------------------------------------------

/**
 * Habilita o deshabilita todos los adaptadores Bluetooth mediante rfkill.
 *
 * Shell: rfkill unblock bluetooth  (enabled = true)
 *        rfkill block   bluetooth  (enabled = false)
 *
 * Nota: rfkill solo maneja el interruptor RF del kernel. Si BlueZ no está en
 * ejecución, el adaptador puede seguir pareciendo ausente. bluetoothctl se usa
 * para gestionar el daemon.
 *
 * @param {boolean} enabled - Pass true to unblock, false to block.
 */
function setBluetoothEnabled(enabled) {
    if (_notReady("setBluetoothEnabled", null, null)) return

    var action = enabled ? "unblock" : "block"
    _execFn("rfkill " + action + " bluetooth", function(_output) {})
}

// ---------------------------------------------------------------------------
//  BLUETOOTH — CONTEO DE DISPOSITIVOS CONECTADOS
// ---------------------------------------------------------------------------

/**
 * Obtiene el número de dispositivos Bluetooth conectados actualmente.
 *
 * Shell: bluetoothctl devices Connected | wc -l
 *
 * bluetoothctl devices Connected lists one line per connected device;
 * wc -l counts them.  The output is the count as a decimal string (e.g. "2").
 *
 * @param {function(number)} callback - Called with the device count (>= 0).
 */
function getBluetoothDeviceCount(callback) {
    if (_notReady("getBluetoothDeviceCount", callback, 0)) return

    _execFn("bluetoothctl devices Connected | wc -l", function(output) {
        var count = parseInt(output.trim(), 10)
        if (isNaN(count) || count < 0) count = 0
        callback(count)
    })
}
