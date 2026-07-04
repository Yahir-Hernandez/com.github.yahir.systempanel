/**
 * QuickSettings.qml — tira de ajustes rápidos del System Panel Plasmoid
 *
 * Tira autocontenida de controles rápidos. Gestiona su propia altura
 * (estados colapsado / expandido); el padre solo necesita proporcionar el ancho.
 *
 * Fila siempre visible:
 *   Toggle Wi-Fi · Toggle Bluetooth · Slider de volumen · Slider de brillo ·
 *   Toggle de modo presentación · Flecha "Más"
 *
 * Sección expandida (deslizamiento animado, 250 ms):
 *   Toggle de notificaciones · Selector de perfil de energía ·
 *   Botones de Display / Sound / Network / System Settings
 *
 * Todo el estado inicial se carga desde el host mediante QtCore.Process en
 * Component.onCompleted. Los cambios en los sliders usan debounce de 200 ms
 * antes de emitir el comando de shell correspondiente.
 *
 * Switch.onToggled se usa en controles interactivos para que las asignaciones
 * programáticas hechas desde dispatchOutput() NO vuelvan a disparar comandos.
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
    id: quickSettings

    // ── Tamaño ────────────────────────────────────────────────────────────────
    // implicitHeight lo determina mainColumn, que a su vez sigue el
    // implicitHeight animado de expandedSection al expandirse o colapsarse.
    // El ColumnLayout padre en main.qml usa esto para redimensionar la franja.
    implicitWidth:  parent ? parent.width : Kirigami.Units.gridUnit * 40
    implicitHeight: mainColumn.implicitHeight

    // =========================================================================
    //  STATE PROPERTIES
    // =========================================================================

    /** Controla el panel expandido con animación de deslizamiento. */
    property bool settingsExpanded: false

    // ── Red ───────────────────────────────────────────────────────────────────
    property bool wifiEnabled: false
    property bool btEnabled:   false

    // ── Audio / Pantalla ──────────────────────────────────────────────────────
    property int volumeValue:     50   // 0–100
    property int brightnessValue: 50   // 0–100

    // ── Varios ────────────────────────────────────────────────────────────────
    property bool presentationMode:    false   // keepalive timer active
    property bool notificationsPaused: false   // dunst paused

    // ── Perfil de energía: 0 = Performance, 1 = Balanced, 2 = Power Saver ───
    property int powerProfileIndex: 1

    // =========================================================================
    //  CADENAS DE COMANDOS
    //  Se definen como propiedades para compartir exactamente la misma cadena
    //  entre exec() y dispatchOutput(); un error tipográfico fallaría en silencio.
    // =========================================================================

    readonly property string _cmdWifi:    "nmcli radio wifi"
    readonly property string _cmdBt:      "rfkill list bluetooth"
    readonly property string _cmdVolRead: "amixer sget Master | grep 'Left:' | awk -F'[][]' '{print $2}' | tr -d '%'"
    readonly property string _cmdBriRead: "brightnessctl -m | cut -d, -f4 | tr -d '%'"
    readonly property string _cmdPwrRead: "powerprofilesctl get"

    // =========================================================================
    //  EJECUTOR DE COMANDOS DE SHELL (QtCore.Process con cola)
    // =========================================================================

    property var commandQueue: []
    property bool isProcessing: false

    /**
     * Crea una nueva instancia de Process y ejecuta un comando.
     * El Process se destruye al terminar para evitar fugas de recursos.
     */
    function exec(cmd) {
        // Añade el comando a la cola.
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
            quickSettings
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
     * Dirige el stdout de un comando terminado a la propiedad de estado correcta.
     * Los comandos se comparan por la cadena exacta pasada a exec().
     */
    function dispatchOutput(cmd, out) {
        // Wi-Fi ("enabled" | "disabled").
        if (cmd === _cmdWifi) {
            quickSettings.wifiEnabled = (out === "enabled")
            wifiSwitch.checked = quickSettings.wifiEnabled
            return
        }

        // Bluetooth ("Soft blocked: no" significa que la radio está activa).
        if (cmd === _cmdBt) {
            quickSettings.btEnabled = (out.indexOf("Soft blocked: no") !== -1)
            btSwitch.checked = quickSettings.btEnabled
            return
        }

        // Volumen (cadena entera de porcentaje, por ejemplo "75").
        if (cmd === _cmdVolRead) {
            var vol = parseInt(out, 10)
            if (!isNaN(vol)) {
                quickSettings.volumeValue = vol
                volumeSlider.value = vol
            }
            return
        }

        // Brillo (cadena entera de porcentaje, por ejemplo "60").
        if (cmd === _cmdBriRead) {
            var bri = parseInt(out, 10)
            if (!isNaN(bri)) {
                quickSettings.brightnessValue = bri
                brightnessSlider.value = bri
            }
            return
        }

        // Perfil de energía ("performance" | "balanced" | "power-saver").
        if (cmd === _cmdPwrRead) {
            if      (out === "performance") quickSettings.powerProfileIndex = 0
            else if (out === "balanced")    quickSettings.powerProfileIndex = 1
            else if (out === "power-saver") quickSettings.powerProfileIndex = 2
            powerProfileBox.currentIndex = quickSettings.powerProfileIndex
            return
        }
    }

    // =========================================================================
    //  TEMPORIZADORES DE DEBOUNCE
    // =========================================================================

    /**
     * Debounce de volumen: se reinicia en cada movimiento del slider; dispara
     * un único comando amixer 200 ms después del último cambio.
     */
    Timer {
        id:       volumeDebounce
        interval: 200
        repeat:   false
        onTriggered: exec("amixer sset Master " + quickSettings.volumeValue + "%")
    }

    /**
     * Debounce de brillo: mismo patrón que volumen, usando brightnessctl.
     */
    Timer {
        id:       brightnessDebounce
        interval: 200
        repeat:   false
        onTriggered: exec("brightnessctl set " + quickSettings.brightnessValue + "%")
    }

    /**
     * Keepalive del modo presentación.
     * Reinicia el temporizador del salvapantallas cada 30 s para que la pantalla
     * permanezca despierta. El temporizador arranca y se detiene solo mediante
     * el binding running.
     */
    Timer {
        id:       presentationTimer
        interval: 30000
        repeat:   true
        running:  quickSettings.presentationMode
        onTriggered: exec("xdg-screensaver reset")
    }

    // =========================================================================
    //  ESTADO INICIAL
    // =========================================================================
    Component.onCompleted: {
        exec(_cmdWifi)
        exec(_cmdBt)
        exec(_cmdVolRead)
        exec(_cmdBriRead)
        exec(_cmdPwrRead)
    }

    // =========================================================================
    //  DISTRIBUCIÓN
    // =========================================================================

    ColumnLayout {
        id: mainColumn
        anchors {
            left:  parent.left
            right: parent.right
            top:   parent.top
        }
        // El espaciado entre secciones se maneja con padding y separadores internos.
        spacing: 0

        // ─────────────────────────────────────────────────────────────────────
        //  FILA SIEMPRE VISIBLE
        // ─────────────────────────────────────────────────────────────────────
        RowLayout {
            id:               alwaysRow
            Layout.fillWidth: true
            spacing:          Kirigami.Units.smallSpacing

            // ── 1. Toggle Wi-Fi ───────────────────────────────────────────
            // Un Switch cuyo indicador se acompaña con un icono + etiqueta
            // apilados verticalmente dentro de contentItem, reemplazando el
            // área de texto por defecto.
            PlasmaComponents3.Switch {
                id: wifiSwitch
                // Sin binding en vivo: el valor inicial lo inyecta dispatchOutput
                // para que las actualizaciones programáticas no disparen onToggled.

                QQC2.ToolTip.text:    i18n("Toggle Wi-Fi")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                contentItem: ColumnLayout {
                    spacing: 2
                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignHCenter
                        source: wifiSwitch.checked
                                    ? "network-wireless"
                                    : "network-wireless-disconnected"
                        implicitWidth:  Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }
                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text:           i18n("WiFi")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        color:          Kirigami.Theme.textColor
                    }
                }

                // onToggled se dispara SOLO por interacción del usuario; aquí sí
                // es seguro llamar a exec().
                onToggled: exec(checked ? "nmcli radio wifi on" : "nmcli radio wifi off")
            }

            // ── 2. Toggle Bluetooth ──────────────────────────────────────
            PlasmaComponents3.Switch {
                id: btSwitch
                // Sin binding en vivo: el valor inicial lo inyecta dispatchOutput.

                QQC2.ToolTip.text:    i18n("Toggle Bluetooth")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                contentItem: ColumnLayout {
                    spacing: 2
                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignHCenter
                        source: btSwitch.checked
                                    ? "bluetooth-active"
                                    : "bluetooth-disabled"
                        implicitWidth:  Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }
                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text:           i18n("Bluetooth")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        color:          Kirigami.Theme.textColor
                    }
                }

                onToggled: exec(checked ? "rfkill unblock bluetooth" : "rfkill block bluetooth")
            }

            // Divisor vertical fino entre los toggles compactos y los sliders.
            Kirigami.Separator {
                // orientation: Qt.Vertical
                Layout.fillHeight: true
            }

            // ── 3. Slider de volumen ─────────────────────────────────────
            // El icono de altavoz se adapta al nivel actual.
            // Los movimientos del slider usan debounce de 200 ms antes de enviar amixer.
            RowLayout {
                id:               volumeControl
                Layout.fillWidth: true
                spacing:          Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: {
                        if (quickSettings.volumeValue === 0) return "audio-volume-muted"
                        if (quickSettings.volumeValue  <  40) return "audio-volume-low"
                        if (quickSettings.volumeValue  <  75) return "audio-volume-medium"
                        return "audio-volume-high"
                    }
                    implicitWidth:    Kirigami.Units.iconSizes.small
                    implicitHeight:   Kirigami.Units.iconSizes.small
                    Layout.alignment: Qt.AlignVCenter

                    QQC2.ToolTip.text:    i18n("System volume")
                    QQC2.ToolTip.visible: volIconArea.containsMouse
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    MouseArea {
                        id:           volIconArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }

                PlasmaComponents3.Slider {
                    id:               volumeSlider
                    from:             0
                    to:               100
                    value:            quickSettings.volumeValue
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    QQC2.ToolTip.text:    i18n("Volume: %1%").arg(Math.round(value))
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    // onMoved fires only for direct user interaction — safe to debounce.
                    onMoved: {
                        quickSettings.volumeValue = Math.round(value)
                        volumeDebounce.restart()
                    }
                }

                // Live percentage badge — updates in real time as the thumb moves
                PlasmaComponents3.Label {
                    text:                Math.round(volumeSlider.value) + "%"
                    font.pixelSize:      Kirigami.Units.gridUnit * 0.75
                    color:               Kirigami.Theme.disabledTextColor
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
                    Layout.alignment:    Qt.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                }
            }  // volumeControl

            // ── 4. Brightness slider ──────────────────────────────────────
            // Reads current brightness on init via brightnessctl -m.
            // Changes are debounced 200 ms via brightnessDebounce.
            RowLayout {
                id:               brightnessControl
                Layout.fillWidth: true
                spacing:          Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source:           "display-brightness"
                    implicitWidth:    Kirigami.Units.iconSizes.small
                    implicitHeight:   Kirigami.Units.iconSizes.small
                    Layout.alignment: Qt.AlignVCenter

                    QQC2.ToolTip.text:    i18n("Display brightness")
                    QQC2.ToolTip.visible: briIconArea.containsMouse
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    MouseArea {
                        id:           briIconArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }
                }

                PlasmaComponents3.Slider {
                    id:               brightnessSlider
                    from:             0
                    to:               100
                    value:            quickSettings.brightnessValue
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    QQC2.ToolTip.text:    i18n("Brightness: %1%").arg(Math.round(value))
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    onMoved: {
                        quickSettings.brightnessValue = Math.round(value)
                        brightnessDebounce.restart()
                    }
                }

                // Live percentage badge
                PlasmaComponents3.Label {
                    text:                Math.round(brightnessSlider.value) + "%"
                    font.pixelSize:      Kirigami.Units.gridUnit * 0.75
                    color:               Kirigami.Theme.disabledTextColor
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
                    Layout.alignment:    Qt.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                }
            }  // brightnessControl

            // Thin vertical divider before the right-side controls
            Kirigami.Separator {
                // orientation: Qt.Vertical
                Layout.fillHeight: true
            }

            // ── 5. Presentation Mode toggle ───────────────────────────────
            // Keeps the screensaver at bay via periodic xdg-screensaver reset.
            PlasmaComponents3.Switch {
                id: presentationSwitch
                // Starts unchecked — presentation mode is off by default.

                QQC2.ToolTip.text:    i18n("Presentation mode — keeps the display awake")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                contentItem: ColumnLayout {
                    spacing: 2
                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignHCenter
                        source:         "video-display"
                        implicitWidth:  Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }
                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text:           i18n("Present")
                        font.pixelSize: Kirigami.Units.gridUnit * 0.7
                        color:          Kirigami.Theme.textColor
                    }
                }

                onToggled: {
                    quickSettings.presentationMode = checked
                    // Fire an immediate reset so there is no gap before the
                    // 30-second repeating timer first fires.
                    if (checked) exec("xdg-screensaver reset")
                }
            }

            // ── 6. "More" / "Less" chevron button ─────────────────────────
            // Toggles the animated expanded section.
            PlasmaComponents3.ToolButton {
                id:               moreButton
                icon.name:        quickSettings.settingsExpanded ? "arrow-up" : "arrow-down"
                flat:             true
                Layout.alignment: Qt.AlignVCenter

                QQC2.ToolTip.text: quickSettings.settingsExpanded
                                       ? i18n("Collapse settings")
                                       : i18n("Expand settings")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                onClicked: quickSettings.settingsExpanded = !quickSettings.settingsExpanded
            }

        }  // alwaysRow

        // ─────────────────────────────────────────────────────────────────────
        //  EXPANDED SECTION  (animated slide-down / slide-up)
        //
        //  The Item clips the GridLayout content and animates its implicitHeight
        //  between 0 (collapsed) and expandedContent.implicitHeight (expanded).
        //  The parent ColumnLayout responds frame-by-frame to the animated value,
        //  smoothly resizing the full QuickSettings strip and shifting everything
        //  below it (ApplicationLauncher, SystemStats) in sync.
        // ─────────────────────────────────────────────────────────────────────
        Item {
            id:               expandedSection
            Layout.fillWidth: true
            clip:             true   // hide content that overflows during animation

            // Binding selects the target height; Behavior animates transitions.
            implicitHeight: quickSettings.settingsExpanded
                                ? expandedContent.implicitHeight
                                : 0

            Behavior on implicitHeight {
                NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
            }

            // ── Expanded content ──────────────────────────────────────────
            GridLayout {
                id:            expandedContent
                columns:       3
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing:    Kirigami.Units.smallSpacing

                // Fill the wrapper horizontally; top-anchor prevents the grid
                // from being pushed down by the animation clip height.
                anchors {
                    left:  parent.left
                    right: parent.right
                    top:   parent.top
                }

                // ── Row 0: Full-width separator ───────────────────────────
                Kirigami.Separator {
                    Layout.fillWidth:  true
                    Layout.columnSpan: 3
                }

                // ── Row 1, Col 1: Notifications toggle ────────────────────
                // Visual-only; delegates state to dunst via dunstctl.
                RowLayout {
                    spacing:          Kirigami.Units.smallSpacing
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft

                    Kirigami.Icon {
                        source: quickSettings.notificationsPaused
                                    ? "notifications-disabled"
                                    : "notifications"
                        implicitWidth:  Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }

                    PlasmaComponents3.Label {
                        text:  i18n("Notifications")
                        color: Kirigami.Theme.textColor
                    }

                    PlasmaComponents3.Switch {
                        id:      notifSwitch
                        // ON  = notifications are active (not paused).
                        // OFF = notifications are paused.
                        checked: true   // default: notifications are active

                        QQC2.ToolTip.text:    i18n("Pause or resume desktop notifications (dunst)")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                        onToggled: {
                            quickSettings.notificationsPaused = !checked
                            exec(checked ? "dunstctl set-paused false"
                                         : "dunstctl set-paused true")
                        }
                    }
                }

                // ── Row 1, Col 2–3: Power-profile selector ────────────────
                RowLayout {
                    spacing:           Kirigami.Units.smallSpacing
                    Layout.columnSpan: 2   // spans columns 2 and 3
                    Layout.alignment:  Qt.AlignVCenter

                    // Icon reflects the active profile
                    Kirigami.Icon {
                        source: {
                            switch (quickSettings.powerProfileIndex) {
                                case 0:  return "speedometer"      // Performance
                                case 2:  return "battery-low"      // Power Saver
                                default: return "battery-good"     // Balanced
                            }
                        }
                        implicitWidth:  Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                    }

                    PlasmaComponents3.Label {
                        text:  i18n("Power Profile")
                        color: Kirigami.Theme.textColor
                    }

                    PlasmaComponents3.ComboBox {
                        id:               powerProfileBox
                        model:            [i18n("Performance"), i18n("Balanced"), i18n("Power Saver")]
                        currentIndex:     quickSettings.powerProfileIndex
                        Layout.fillWidth: true

                        QQC2.ToolTip.text:    i18n("Select the CPU power-performance profile")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                        // onActivated fires only on user selection — safe to exec().
                        onActivated: function(index) {
                            quickSettings.powerProfileIndex = index
                            var profiles = ["performance", "balanced", "power-saver"]
                            exec("powerprofilesctl set " + profiles[index])
                        }
                    }
                }

                // ── Row 2: Display · Sound · Network ─────────────────────
                PlasmaComponents3.Button {
                    flat:             true
                    display:          QQC2.AbstractButton.TextBelowIcon
                    icon.name:        "preferences-desktop-display"
                    text:             i18n("Display")
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    QQC2.ToolTip.text:    i18n("Open Display Settings (kcm_kscreen)")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    onClicked: exec("kcmshell6 kcm_kscreen")
                }

                PlasmaComponents3.Button {
                    flat:             true
                    display:          QQC2.AbstractButton.TextBelowIcon
                    icon.name:        "preferences-desktop-sound"
                    text:             i18n("Sound")
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    QQC2.ToolTip.text:    i18n("Open Audio Settings (kcm_pulseaudio)")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    onClicked: exec("kcmshell6 kcm_pulseaudio")
                }

                PlasmaComponents3.Button {
                    flat:             true
                    display:          QQC2.AbstractButton.TextBelowIcon
                    icon.name:        "preferences-system-network"
                    text:             i18n("Network")
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter

                    QQC2.ToolTip.text:    i18n("Open Network Settings (kcm_networkmanagement)")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    onClicked: exec("kcmshell6 kcm_networkmanagement")
                }

                // ── Row 3: System Settings (spans all 3 cols) ─────────────
                PlasmaComponents3.Button {
                    flat:              true
                    display:           QQC2.AbstractButton.TextBelowIcon
                    icon.name:         "preferences-system"
                    text:              i18n("System Settings")
                    Layout.columnSpan: 3
                    Layout.fillWidth:  true
                    Layout.alignment:  Qt.AlignHCenter

                    QQC2.ToolTip.text:    i18n("Open KDE System Settings")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay

                    onClicked: exec("systemsettings6")
                }

            }  // GridLayout (expandedContent)
        }  // Item (expandedSection)

    }  // ColumnLayout (mainColumn)

}  // Item (quickSettings)
