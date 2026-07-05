/**
 * StatusBar.qml  —  System Panel Plasmoid (com.github.yahir.systempanel)
 *
 * A self-contained horizontal status bar that displays, left-to-right:
 *   1. User avatar + username
 *   2. Battery level and charging state   (polled from /sys/class/power_supply/BAT0/)
 *   3. WiFi SSID + signal strength         (polled via nmcli)
 *   4. Live clock                          (updated every second, pure Qt — no shell)
 *   5. Hostname                            (polled via hostname -s)
 *
 * All data is fetched internally — the parent only needs to set the item size.
 *
 * Target: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
Item {
    id: statusBar

    // ── Sizing hint (parent may override via Layout.preferredHeight) ──────────
    implicitHeight: Kirigami.Units.gridUnit * 3.5
    implicitWidth:  parent ? parent.width : Kirigami.Units.gridUnit * 40

    // =========================================================================
    //  INTERNAL STATE
    // =========================================================================

    // User
    property string userName: ""

    // Battery  (-1 means no battery present / not yet read)
    property int    batteryLevel:    -1
    property bool   batteryCharging: false
    property bool   batteryPresent:  false

    // WiFi  (-1 signal means disconnected / unknown)
    property string wifiSsid:   ""
    property int    wifiSignal: -1

    // Hostname
    property string hostName: ""

    // Clock (updated by clockTimer, no shell needed)
    property string clockText: Qt.formatDateTime(new Date(), "ddd dd MMM") + " | " + Qt.formatDateTime(new Date(), "HH:mm:ss")

    // =========================================================================
    //  SHELL COMMAND RUNNER  (Plasma 6 DataSource, engine: "executable")
    // =========================================================================
    /**
     * A single DataSource handles every shell command.
     * Usage: call exec(cmd) to queue a command; onNewData dispatches
     * the stdout to the appropriate state property based on sourceName,
     * then disconnects the source so it can be reused.
     */
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

    /** Queue a shell command for execution. */
    function exec(cmd) {
        executable.connectSource(cmd)
    }

    /**
     * Route the stdout of a completed command to the right state variable.
     * Each command is identified by its exact command string.
     */
    function dispatchOutput(cmd, out) {
        // ── Username (whoami) ────────────────────────────────────────────
        if (cmd === "whoami") {
            if (out.length > 0) {
                statusBar.userName = out
            }
            return
        }

        // ── Battery capacity ─────────────────────────────────────────────
        if (cmd === "cat /sys/class/power_supply/BAT0/capacity") {
            var cap = parseInt(out, 10)
            if (!isNaN(cap)) {
                statusBar.batteryLevel   = cap
                statusBar.batteryPresent = true
            }
            return
        }

        // ── Battery charging status ──────────────────────────────────────
        if (cmd === "cat /sys/class/power_supply/BAT0/status") {
            // Possible values: Charging, Discharging, Full, Unknown, Not charging
            statusBar.batteryCharging = (out === "Charging" || out === "Full")
            return
        }

        // ── WiFi SSID + signal  (nmcli -t output: yes:SSID:signal) ───────
        if (cmd === "nmcli -t -f active,ssid,signal dev wifi | grep '^yes'") {
            if (out.length > 0) {
                // Format: "yes:MyNetwork:85"
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
                // No active connection
                statusBar.wifiSsid   = ""
                statusBar.wifiSignal = -1
            }
            return
        }

        // ── Hostname ─────────────────────────────────────────────────────
        if (cmd === "hostname -s") {
            if (out.length > 0) {
                statusBar.hostName = out
            }
            return
        }
    }

    // =========================================================================
    //  TIMERS
    // =========================================================================

    /**
     * Master refresh timer — polls battery and WiFi every 5 seconds.
     * Username and hostname are fetched once at Component.onCompleted and
     * re-polled here in case of a user switch or hostname change.
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
     * Clock timer — updates the clock text every second using Qt's built-in
     * date formatting (no shell process needed).
     */
    Timer {
        id: clockTimer
        interval: 1000
        running:  true
        repeat:   true

        onTriggered: {
            statusBar.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM") + " | " + Qt.formatDateTime(new Date(), "HH:mm:ss")
        }
    }

    // Fetch username once on startup (also picked up by refreshTimer,
    // but this ensures it is available before the first 5-second tick).
    Component.onCompleted: {
        exec("whoami")
    }

    // =========================================================================
    //  HELPER FUNCTIONS
    // =========================================================================

    /**
     * Map a battery level (0-100) and charging flag to an icon name.
     * Uses standard freedesktop/KDE battery icon naming.
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
     * Map a WiFi signal strength (0-100) to an icon name.
     * Returns a disconnected icon when signal is -1.
     */
    function wifiIconName(signal) {
        if (signal < 0)  return "network-wireless-disconnected"
        if (signal >= 80) return "network-wireless-signal-excellent"
        if (signal >= 55) return "network-wireless-signal-good"
        if (signal >= 30) return "network-wireless-signal-ok"
        if (signal >= 5)  return "network-wireless-signal-weak"
        return "network-wireless-disconnected"
    }

    Rectangle {
        anchors.fill:    parent
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.cornerRadius
        border.color: Kirigami.Theme.disabledTextColor
    }

    // =========================================================================
    //  LAYOUT
    // =========================================================================
    RowLayout {
        id: mainRow
        anchors.fill:    parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing:         Kirigami.Units.largeSpacing

        // ── 1. USER ───────────────────────────────────────────────────────
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

        // ── Separator ─────────────────────────────────────────────────────
        /*Kirigami.Separator {
            Layout.fillHeight: true
        }

        // ── 2. BATTERY ────────────────────────────────────────────────────
        // Hidden entirely when no battery is detected.
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
                    // Colour-code: red below 15%, orange below 30%, normal otherwise
                    if (statusBar.batteryLevel >= 0 && statusBar.batteryLevel < 15)
                        return Kirigami.Theme.negativeTextColor
                    if (statusBar.batteryLevel >= 0 && statusBar.batteryLevel < 30)
                        return Kirigami.Theme.neutralTextColor
                    return Kirigami.Theme.textColor
                }
                Layout.alignment: Qt.AlignVCenter
            }
        }*/

        // Separator after battery — only shown when battery is present
        /*Kirigami.Separator {
            //orientation: Qt.Vertical
            Layout.fillHeight: true
            visible: statusBar.batteryPresent
        }*/

        // ── 3. WIFI ───────────────────────────────────────────────────────
        /*RowLayout {
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
                // Truncate long SSIDs gracefully
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }*/

        // ── Separator ─────────────────────────────────────────────────────
        /*Kirigami.Separator {
            //orientation: Qt.Vertical
            Layout.fillHeight: true
        }*/

        // ── 4. CLOCK ──────────────────────────────────────────────────────
        // Spacer pushes the clock toward the centre of the bar.
        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            /*Kirigami.Icon {
                source: "clock"
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }*/

            PlasmaComponents3.Label {
                text:  statusBar.clockText
                color: Kirigami.Theme.textColor
                font.family:    "monospace"
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Item { Layout.fillWidth: true }

        // ── Separator ─────────────────────────────────────────────────────
        /*Kirigami.Separator {
            //orientation: Qt.Vertical
            Layout.fillHeight: true
        }*/

        // ── 5. HOSTNAME ───────────────────────────────────────────────────
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            /*Kirigami.Icon {
                source: "computer-laptop"
                width:  Kirigami.Units.iconSizes.small
                height: width
                Layout.alignment: Qt.AlignVCenter
            }*/

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
