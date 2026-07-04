/**
 * StatusBar.qml — barra de estado del System Panel Plasmoid
 *
 * Barra horizontal autocontenida que muestra, de izquierda a derecha:
 *   1. Avatar del usuario + nombre de usuario
 *   2. Nivel de batería y estado de carga (consulta /sys/class/power_supply/BAT0/)
 *   3. SSID y fuerza de señal de Wi-Fi (consulta vía nmcli)
 *   4. Reloj en vivo (se actualiza cada segundo, con Qt puro y sin shell)
 *   5. Hostname (consulta hostname -s)
 *
 * Todos los datos se obtienen internamente; el padre solo necesita definir el tamaño.
 *
 * Destino: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 */

import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: statusBar

    // ── Sugerencia de tamaño (el padre puede sobrescribirla con Layout.preferredHeight) ──────────
    implicitHeight: Kirigami.Units.gridUnit * 3.5
    implicitWidth:  parent ? parent.width : Kirigami.Units.gridUnit * 40

    // =========================================================================
    //  ESTADO INTERNO
    // =========================================================================

    // Usuario
    property string userName: ""

    // Batería (-1 significa que no hay batería o que todavía no se leyó)
    property int    batteryLevel:    -1
    property bool   batteryCharging: false
    property bool   batteryPresent:  false

    // Wi-Fi (-1 en la señal significa desconectado o desconocido)
    property string wifiSsid:   ""
    property int    wifiSignal: -1

    // Hostname
    property string hostName: ""

    // Reloj (lo actualiza clockTimer, no hace falta shell)
    property string clockText: Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm:ss")

    // =========================================================================
    //  EJECUTOR DE COMANDOS DE SHELL (QtCore.Process)
    // =========================================================================
    /**
     * Pool de procesos que reutiliza instancias de Process para ejecutar comandos.
     * Cada comando se encola y se ejecuta de forma secuencial.
     */
    property var commandQueue: []
    property bool isProcessing: false

    /**
     * Crea una nueva instancia de Process y ejecuta un comando.
     * El Process se destruye al terminar para evitar fugas de recursos.
     */
    function exec(cmd) {
        // Agrega el comando a la cola.
        commandQueue.push(cmd)

        // Si no se está procesando nada, arranca el siguiente comando.
        if (!isProcessing) {
            processNextCommand()
        }
    }

    /**
     * Procesa el siguiente comando de la cola.
     */
    function processNextCommand() {
        if (commandQueue.length === 0) {
            isProcessing = false
            return
        }

        isProcessing = true
        var cmd = commandQueue.shift()

        var proc = Qt.createQmlObject(
            'import QtCore; Process { }',
            statusBar
        )

        proc.finished.connect(function() {
            var output = proc.readAllStandardOutput().toString().trim()
            dispatchOutput(cmd, output)
            proc.destroy()

            // Procesa el siguiente comando de la cola.
            processNextCommand()
        })

        proc.command = "/bin/sh"
        proc.arguments = ["-c", cmd]
        proc.start()
    }

    /**
     * Redirige el stdout de un comando terminado a la variable de estado correcta.
     * Cada comando se identifica por su cadena exacta.
     */
    function dispatchOutput(cmd, out) {
        // ── Usuario (whoami) ─────────────────────────────────────────────
        if (cmd === "whoami") {
            if (out.length > 0) {
                statusBar.userName = out
            }
            return
        }

        // ── Capacidad de batería ─────────────────────────────────────────
        if (cmd === "cat /sys/class/power_supply/BAT0/capacity") {
            var cap = parseInt(out, 10)
            if (!isNaN(cap)) {
                statusBar.batteryLevel   = cap
                statusBar.batteryPresent = true
            }
            return
        }

        // ── Estado de carga de batería ───────────────────────────────────
        if (cmd === "cat /sys/class/power_supply/BAT0/status") {
            // Possible values: Charging, Discharging, Full, Unknown, Not charging
            statusBar.batteryCharging = (out === "Charging" || out === "Full")
            return
        }

        // ── SSID y señal de Wi-Fi (salida nmcli -t: yes:SSID:signal) ─────
        if (cmd === "nmcli -t -f active,ssid,signal dev wifi | grep '^yes'") {
            if (out.length > 0) {
                // Formato: "yes:MyNetwork:85"
                var parts = out.split(":")
                if (parts.length >= 3) {
                    statusBar.wifiSsid   = parts[1]
                    statusBar.wifiSignal = parseInt(parts[2], 10) || 0
                } else if (parts.length === 2) {
                    // SSID might be empty
                    statusBar.wifiSsid   = ""
                    statusBar.wifiSignal = parseInt(parts[1], 10) || 0
                }
            } else {
                // No hay conexión activa.
                statusBar.wifiSsid   = ""
                statusBar.wifiSignal = -1
            }
            return
        }

        // ── Hostname ────────────────────────────────────────────────────
        if (cmd === "hostname -s") {
            if (out.length > 0) {
                statusBar.hostName = out
            }
            return
        }
    }

    // =========================================================================
    //  TEMPORIZADORES
    // =========================================================================

    /**
     * Temporizador maestro de refresco: consulta batería y Wi-Fi cada 5 segundos.
     * El usuario y el hostname se obtienen una vez en Component.onCompleted y se
     * vuelven a consultar aquí por si cambiaron.
     */
    Timer {
        id: refreshTimer
        interval: 5000
        running:  true
        repeat:   true
        triggeredOnStart: true   // fire immediately on first run

        onTriggered: {
            // Battery
            exec("cat /sys/class/power_supply/BAT0/capacity")
            exec("cat /sys/class/power_supply/BAT0/status")
            // WiFi
            exec("nmcli -t -f active,ssid,signal dev wifi | grep '^yes'")
            // Hostname (cheap, re-poll is fine)
            exec("hostname -s")
        }
    }

    /**
     * Temporizador del reloj: actualiza el texto cada segundo usando el formateo
     * de fecha de Qt, sin necesidad de un proceso de shell.
     */
    Timer {
        id: clockTimer
        interval: 1000
        running:  true
        repeat:   true

        onTriggered: {
            statusBar.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm:ss")
        }
    }

    // Obtiene el usuario una vez al iniciar (refreshTimer también lo vuelve a leer,
    // pero esto asegura que esté disponible antes del primer tick de 5 segundos).
    Component.onCompleted: {
        exec("whoami")
    }

    // =========================================================================
    //  FUNCIONES AUXILIARES
    // =========================================================================

    /**
     * Mapea un nivel de batería (0-100) y una bandera de carga a un nombre de icono.
     * Usa la nomenclatura estándar de iconos de batería de freedesktop/KDE.
     */
    function batteryIconName(level, charging) {
        if (charging) return "battery-charging"
        if (level >= 90) return "battery-full"
        if (level >= 60) return "battery-good"
        if (level >= 35) return "battery-medium"
        if (level >= 10) return "battery-low"
        return "battery-empty"
    }

    /**
     * Mapea la intensidad de señal Wi-Fi (0-100) a un nombre de icono.
     * Devuelve el icono de desconectado cuando la señal es -1.
     */
    function wifiIconName(signal) {
        if (signal < 0)  return "network-wireless-disconnected"
        if (signal >= 80) return "network-wireless-signal-excellent"
        if (signal >= 55) return "network-wireless-signal-good"
        if (signal >= 30) return "network-wireless-signal-ok"
        if (signal >= 5)  return "network-wireless-signal-weak"
        return "network-wireless-disconnected"
    }

    // =========================================================================
    //  DISTRIBUCIÓN
    // =========================================================================
    RowLayout {
        id: mainRow
        anchors.fill:    parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing:         Kirigami.Units.largeSpacing

        // ── 1. USUARIO ───────────────────────────────────────────────────
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            Kirigami.Icon {
                source: "user-identity"
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                text:  statusBar.userName.length > 0
                           ? statusBar.userName
                           : i18n("user")
                color: Kirigami.Theme.textColor
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── Separador ────────────────────────────────────────────────────
        Kirigami.Separator {
            // orientation: Qt.Vertical
            Layout.fillHeight: true
        }

        // ── 2. BATERÍA ───────────────────────────────────────────────────
        // Se oculta por completo cuando no se detecta una batería.
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            visible: statusBar.batteryPresent
            Layout.alignment: Qt.AlignVCenter

            Kirigami.Icon {
                source: batteryIconName(statusBar.batteryLevel, statusBar.batteryCharging)
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                text: {
                    if (statusBar.batteryLevel < 0) return ""
                    var pct = statusBar.batteryLevel + "%"
                    return statusBar.batteryCharging ? pct + "  " + i18n("Charging") : pct
                }
                color: {
                    // Código de color: rojo por debajo de 15%, naranja por debajo de 30%, normal en otro caso.
                    if (statusBar.batteryLevel >= 0 && statusBar.batteryLevel < 15)
                        return Kirigami.Theme.negativeTextColor
                    if (statusBar.batteryLevel >= 0 && statusBar.batteryLevel < 30)
                        return Kirigami.Theme.neutralTextColor
                    return Kirigami.Theme.textColor
                }
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Separador después de la batería: solo se muestra cuando hay batería.
        Kirigami.Separator {
            // orientation: Qt.Vertical
            Layout.fillHeight: true
            visible: statusBar.batteryPresent
        }

        // ── 3. WI-FI ────────────────────────────────────────────────────
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            Kirigami.Icon {
                source: wifiIconName(statusBar.wifiSignal)
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                text: {
                    if (statusBar.wifiSignal < 0) return i18n("Disconnected")
                    var label = statusBar.wifiSsid.length > 0
                                    ? statusBar.wifiSsid
                                    : i18n("Connected")
                    return label + "  " + statusBar.wifiSignal + "%"
                }
                color: statusBar.wifiSignal < 0
                           ? Kirigami.Theme.disabledTextColor
                           : Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
                // Trunca los SSID largos de forma elegante.
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        // ── Separador ────────────────────────────────────────────────────
        Kirigami.Separator {
            // orientation: Qt.Vertical
            Layout.fillHeight: true
        }

        // ── 4. RELOJ ─────────────────────────────────────────────────────
        // El espaciador empuja el reloj hacia el centro de la barra.
        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            Kirigami.Icon {
                source: "clock"
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                text:  statusBar.clockText
                color: Kirigami.Theme.textColor
                font.family:    "monospace"
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Item { Layout.fillWidth: true }

        // ── Separador ────────────────────────────────────────────────────
        Kirigami.Separator {
            // orientation: Qt.Vertical
            Layout.fillHeight: true
        }

        // ── 5. HOSTNAME ─────────────────────────────────────────────────
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            Kirigami.Icon {
                source: "computer-laptop"
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents3.Label {
                text:  statusBar.hostName.length > 0
                           ? statusBar.hostName
                           : i18n("localhost")
                color: Kirigami.Theme.textColor
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }  // RowLayout
}  // Item
