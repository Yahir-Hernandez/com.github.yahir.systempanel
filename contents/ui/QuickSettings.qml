/**
 * QuickSettings.qml  —  System Panel Plasmoid (com.github.yahir.systempanel)
 *
 * A self-contained quick-settings control strip.  Manages its own height
 * (collapsed / expanded states); the parent only needs to provide width.
 *
 * Always-visible row:
 *   WiFi toggle · Bluetooth toggle · Volume slider · Brightness slider ·
 *   Presentation Mode toggle · "More" chevron
 *
 * Expanded section (animated slide-down, 250 ms):
 *   Notifications toggle · Power-profile selector ·
 *   Display / Sound / Network / System Settings buttons
 *
 * All initial state is loaded from the host via PlasmaCore.DataSource
 * (engine: "executable") in Component.onCompleted.  Slider changes are
 * debounced 200 ms before issuing the underlying shell command.
 *
 * Switch.onToggled is used for interactive controls so that programmatic
 * assignments made from dispatchOutput() do NOT re-trigger shell commands.
 *
 * Target: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
Item {
    id: quickSettings

    // ── Sizing ─────────────────────────────────────────────────────────────────
    // implicitHeight is driven by mainColumn, which itself follows
    // expandedSection's animated implicitHeight during expand / collapse.
    // The parent ColumnLayout in main.qml reads this to resize the strip.
    implicitWidth:  parent ? parent.width : Kirigami.Units.gridUnit * 40
    implicitHeight: mainColumn.implicitHeight

    // =========================================================================
    //  STATE PROPERTIES
    // =========================================================================

    /** Controls the animated slide-down expanded panel. */
    property bool settingsExpanded: false

    // ── Network ────────────────────────────────────────────────────────────────
    property bool wifiEnabled: false
    property bool btEnabled:   false

    // ── Audio / Display ────────────────────────────────────────────────────────
    property int volumeValue:     50   // 0–100
    property int brightnessValue: 50   // 0–100

    // ── Misc ──────────────────────────────────────────────────────────────────
    property bool presentationMode:    false   // keepalive timer active
    property bool notificationsPaused: false   // dunst paused

    // ── Power profile: 0 = Performance, 1 = Balanced, 2 = Power Saver ─────────
    property int powerProfileIndex: 1

    // =========================================================================
    //  COMMAND STRINGS
    //  Defined as properties so the exact string is shared between exec() calls
    //  and dispatchOutput() matching — typos would cause silent failures.
    // =========================================================================

    readonly property string _cmdWifi:    "nmcli radio wifi"
    readonly property string _cmdBt:      "rfkill list bluetooth"
    readonly property string _cmdVolRead: "amixer sget Master | grep 'Left:' | awk -F'[][]' '{print $2}' | tr -d '%'"
    readonly property string _cmdBriRead: "brightnessctl -m | cut -d, -f4 | tr -d '%'"
    readonly property string _cmdPwrRead: "powerprofilesctl get"

    // =========================================================================
    //  SHELL COMMAND RUNNER  (Plasma 6 DataSource, engine: "executable")
    // =========================================================================

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            dispatchOutput(sourceName, out)
        }
    }

    /** Enqueue a shell command for asynchronous execution. */
    function exec(cmd) {
        executable.connectSource(cmd)
    }

    /**
     * Route the stdout of a completed command to the appropriate state property.
     * Commands are matched by their exact string as passed to exec().
     */
    function dispatchOutput(cmd, out) {
        // WiFi  ("enabled" | "disabled")
        if (cmd === _cmdWifi) {
            quickSettings.wifiEnabled = (out === "enabled")
            wifiSwitch.checked = quickSettings.wifiEnabled
            return
        }

        // Bluetooth  ("Soft blocked: no" means the radio is ON)
        if (cmd === _cmdBt) {
            quickSettings.btEnabled = (out.indexOf("Soft blocked: no") !== -1)
            btSwitch.checked = quickSettings.btEnabled
            return
        }

        // Volume  (integer percentage string, e.g. "75")
        if (cmd === _cmdVolRead) {
            var vol = parseInt(out, 10)
            if (!isNaN(vol)) {
                quickSettings.volumeValue = vol
                volumeSlider.value = vol
            }
            return
        }

        // Brightness  (integer percentage string, e.g. "60")
        if (cmd === _cmdBriRead) {
            var bri = parseInt(out, 10)
            if (!isNaN(bri)) {
                quickSettings.brightnessValue = bri
                brightnessSlider.value = bri
            }
            return
        }

        // Power profile  ("performance" | "balanced" | "power-saver")
        if (cmd === _cmdPwrRead) {
            if      (out === "performance") quickSettings.powerProfileIndex = 0
            else if (out === "balanced")    quickSettings.powerProfileIndex = 1
            else if (out === "power-saver") quickSettings.powerProfileIndex = 2
            powerProfileBox.currentIndex = quickSettings.powerProfileIndex
            return
        }
    }

    // =========================================================================
    //  DEBOUNCE TIMERS
    // =========================================================================

    /**
     * Volume debounce — restarts on every user slider move; fires 200 ms after
     * the last one and issues a single amixer command.
     */
    Timer {
        id:       volumeDebounce
        interval: 200
        repeat:   false
        onTriggered: exec("amixer sset Master " + quickSettings.volumeValue + "%")
    }

    /**
     * Brightness debounce — same pattern as volume, using brightnessctl.
     */
    Timer {
        id:       brightnessDebounce
        interval: 200
        repeat:   false
        onTriggered: exec("brightnessctl set " + quickSettings.brightnessValue + "%")
    }

    /**
     * Presentation-mode keepalive.
     * Resets the X screensaver timer every 30 s so the display stays awake.
     * The timer starts and stops automatically via the `running` binding.
     */
    Timer {
        id:       presentationTimer
        interval: 30000
        repeat:   true
        running:  quickSettings.presentationMode
        onTriggered: exec("xdg-screensaver reset")
    }

    // =========================================================================
    //  INITIAL STATE
    // =========================================================================
    Component.onCompleted: {
        exec(_cmdWifi)
        exec(_cmdBt)
        exec(_cmdVolRead)
        exec(_cmdBriRead)
        exec(_cmdPwrRead)
    }

    // =========================================================================
    //  LAYOUT
    // =========================================================================

    ColumnLayout {
        id: mainColumn
        anchors {
            left:  parent.left
            right: parent.right
            top:   parent.top
        }
        // Section-level spacing is handled by internal padding / separators.
        spacing: 0

        // ─────────────────────────────────────────────────────────────────────
        //  ALWAYS-VISIBLE ROW
        // ─────────────────────────────────────────────────────────────────────
        RowLayout {
            id:               alwaysRow
            Layout.fillWidth: true
            spacing:          Kirigami.Units.smallSpacing

            // ── 1. WiFi toggle ────────────────────────────────────────────
            // A Switch whose indicator is paired with an icon + label pair
            // stacked vertically inside contentItem (replaces the default
            // text-only content area).
            PlasmaComponents3.Switch {
                id: wifiSwitch
                // No live binding — initial value injected by dispatchOutput so
                // that programmatic updates never fire onToggled.

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

                // onToggled fires ONLY on user interaction — safe to call exec().
                onToggled: exec(checked ? "nmcli radio wifi on" : "nmcli radio wifi off")
            }

            // ── 2. Bluetooth toggle ───────────────────────────────────────
            PlasmaComponents3.Switch {
                id: btSwitch
                // No live binding — initial value injected by dispatchOutput.

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

            // Thin vertical divider between compact toggles and the sliders
            Kirigami.Separator {
                Layout.fillHeight: true
            }

            // ── 3. Volume slider ──────────────────────────────────────────
            // Speaker icon adapts to the current level.
            // Slider moves are debounced 200 ms before issuing amixer.
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

                    QQC2.ToolTip.text:    i18n("Volume: %1%",Math.round(value))
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

                    QQC2.ToolTip.text:    i18n("Brightness: %1%",Math.round(value))
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
                // orientation:       Qt.Vertical
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
