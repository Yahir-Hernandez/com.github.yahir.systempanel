// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2024 Yahir <com.github.yahir>

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

import "../code/SystemMonitor.js" as SysMon

Item {
    id: systemStats

    // Refresh interval in milliseconds (default 2000ms, set by parent from config)
    property int refreshInterval: 2000

    implicitHeight: Kirigami.Units.gridUnit * 7.5

    // ── Internal state ─────────────────────────────────────────────────────────

    // CPU
    property var   cpuPrevSample:  null
    property real  cpuPercent:     0.0
    property bool  cpuWaitingDiff: false

    // RAM
    property real  ramUsedGiB:  0.0
    property real  ramTotalGiB: 0.0
    property real  ramPercent:  0.0

    // Storage
    property real  diskPercent: 0.0

    // Temperature
    property real  tempCelsius: 0.0

    // Network
    /*property var   netPrevSample:    null
    property int   netPrevTimestamp: 0
    property real  netTxMbps:        0.0
    property real  netRxMbps:        0.0
    */

     property int    batteryLevel:    -1

    // ── Helpers ────────────────────────────────────────────────────────────────

    function usageColor(pct) {
        if (pct > 80) return Kirigami.Theme.negativeTextColor   // critical
        if (pct > 50) return Kirigami.Theme.neutralTextColor    // warning
        return Kirigami.Theme.positiveTextColor                  // normal
    }

    function tempIcon(celsius) {
        if (celsius > 70) return "temperature-hot"
        if (celsius > 50) return "temperature-warm"
        return "temperature-normal"
    }

    /*function formatMbps(mbps) {
        if (mbps >= 1000) return (mbps / 1000).toFixed(1) + " Gbps"
        if (mbps >= 1)    return mbps.toFixed(1) + " Mbps"
        return (mbps * 1000).toFixed(0) + " Kbps"
    }*/

    // ── Data collection ────────────────────────────────────────────────────────

    // Commands
    readonly property string cmdCpu:  "awk '/^cpu /{for(i=2;i<=NF;i++) printf $i\" \"; print \"\"}' /proc/stat"
    readonly property string cmdRam:  "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print t, a}' /proc/meminfo"
    readonly property string cmdDisk: "df -k / | awk 'NR==2{printf \"%d %d\", $3, $2}'"
    readonly property string cmdTemp: "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo \"0\""
    readonly property string cmdNet:  "awk 'NR>2 && !/lo/{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev"
    readonly property string cmdBattery: "cat /sys/class/power_supply/BAT0/capacity"

    Plasma5Support.DataSource {
        id: sysMonDS
        engine: "executable"
        connectedSources: []

        onNewData: function(src, data) {
            handleOutput(src, data["stdout"].trim())
            disconnectSource(src)
        }
    }

    function refreshAll() {
        // CPU: first sample — store and schedule second sample
        cpuWaitingDiff = true
        sysMonDS.connectSource(cmdCpu)

        // RAM, Disk, Temp, Net run immediately
        sysMonDS.connectSource(cmdRam)
        sysMonDS.connectSource(cmdDisk)
        sysMonDS.connectSource(cmdTemp)
        sysMonDS.connectSource(cmdNet)
        sysMonDS.connectSource(cmdBattery)
    }

    // Second CPU sample fires 500ms after the first
    Timer {
        id: cpuDiffTimer
        interval: 500
        repeat: false
        onTriggered: sysMonDS.connectSource(systemStats.cmdCpu)
    }

    Timer {
        id: refreshTimer
        interval: refreshInterval
        running: true
        repeat: true
        onTriggered: refreshAll()
    }

    Component.onCompleted: refreshAll()

    // ── Output router ──────────────────────────────────────────────────────────

    function handleOutput(src, output) {
        if (src === cmdCpu) {
            handleCpu(output)
        } else if (src === cmdRam) {
            handleRam(output)
        } else if (src === cmdDisk) {
            handleDisk(output)
        } else if (src === cmdTemp) {
            handleTemp(output)
        } else if (src === cmdNet) {
            handleNet(output)
        } else if (src === cmdBattery) {
            handleBattery(output)
        }
    }

    function handleCpu(output) {
        var sample = SysMon.parseCpuLine(output)
        if (!sample) return

        if (cpuWaitingDiff) {
            // First sample — store and request second
            cpuPrevSample  = sample
            cpuWaitingDiff = false
            cpuDiffTimer.restart()
        } else {
            // Second sample — compute diff
            if (cpuPrevSample) {
                cpuPercent   = SysMon.cpuUsage(cpuPrevSample, sample)
                cpuPrevSample = null
            }
        }
    }

    function handleRam(output) {
        var info = SysMon.parseMemInfo(output)
        if (!info) return
        ramTotalGiB = info.totalKB   / (1024 * 1024)
        ramUsedGiB  = info.usedKB    / (1024 * 1024)
        ramPercent  = info.usedPct
    }

    function handleDisk(output) {
        var info = SysMon.parseDiskInfo(output)
        if (!info) return
        diskPercent = info.usedPct
    }

    function handleTemp(output) {
        tempCelsius = SysMon.parseTemp(output)
    }

    function handleBattery(output) {
        var cap = parseInt(output, 10)
        if (!isNaN(cap)) {
             systemStats.batteryLevel   = cap
        }
    }
    

    /*function handleNet(output) {
        var parts = output.split(" ")
        if (parts.length < 2) return

        var rx = parseInt(parts[0]) || 0
        var tx = parseInt(parts[1]) || 0
        var now = Date.now()

        if (netPrevSample !== null && netPrevTimestamp > 0) {
            var elapsed = now - netPrevTimestamp
            var result  = SysMon.parseNetworkDelta(netPrevSample, { rx: rx, tx: tx }, elapsed)
            netRxMbps   = result.rxMbps
            netTxMbps   = result.txMbps
        }

        netPrevSample    = { rx: rx, tx: tx }
        netPrevTimestamp = now
    }*/

    /**
     * Map a battery level (0-100) and charging flag to an icon name.
     * Uses standard freedesktop/KDE battery icon naming.
     */
    function batteryIconName(level) {

        if (level >= 90) return "battery-full"
        if (level >= 60) return "battery-good"
        if (level >= 35) return "battery-medium"
        if (level >= 10) return "battery-low"
        return "battery-empty"
    }

    // ── UI ─────────────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ── Battery card ─────────────────────────────────────────────────────────
        MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  batteryIconName(systemStats.batteryLevel)
            labelText: i18n("Battery")
            valueText: {
                    if (systemStats.batteryLevel < 0) return ""
                    var pct = systemStats.batteryLevel + "%"
                    return systemStats.batteryCharging ? pct + "  " + i18n("Charging") : pct
                }
            barValue:  systemStats.batteryLevel / 100
            barColor:  {
                    // Colour-code: red below 15%, orange below 30%, normal otherwise
                    if (systemStats.batteryLevel >= 0 && systemStats.batteryLevel < 15)
                        return Kirigami.Theme.negativeTextColor
                    if (systemStats.batteryLevel >= 0 && systemStats.batteryLevel < 30)
                        return Kirigami.Theme.neutralTextColor
                    return Kirigami.Theme.textColor
                }
            showBar:   true
        }

        // ── CPU card ─────────────────────────────────────────────────────────
        MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  "cpu"
            labelText: i18n("CPU")
            valueText: Math.round(systemStats.cpuPercent) + "%"
            barValue:  systemStats.cpuPercent / 100
            barColor:  systemStats.usageColor(systemStats.cpuPercent)
            showBar:   true
        }

        // ── RAM card ─────────────────────────────────────────────────────────
        MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  "memory"
            labelText: i18n("RAM")
            valueText: systemStats.ramUsedGiB.toFixed(1) + " / " + systemStats.ramTotalGiB.toFixed(1) + " GiB"
            barValue:  systemStats.ramPercent / 100
            barColor:  systemStats.usageColor(systemStats.ramPercent)
            showBar:   true
        }

        // ── Storage card ─────────────────────────────────────────────────────
        MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  "drive-harddisk"
            labelText: i18n("Disk /")
            valueText: Math.round(systemStats.diskPercent) + "%"
            barValue:  systemStats.diskPercent / 100
            barColor:  systemStats.usageColor(systemStats.diskPercent)
            showBar:   true
        }

        // ── Temperature card ─────────────────────────────────────────────────
        /*MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  systemStats.tempIcon(systemStats.tempCelsius)
            labelText: i18n("Temp")
            valueText: Math.round(systemStats.tempCelsius) + " °C"
            showBar:   false
        }*/

        // ── Network card ─────────────────────────────────────────────────────
        /*MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  "network-wired"
            labelText: i18n("Net")
            valueText: "↑ " + systemStats.formatMbps(systemStats.netTxMbps) +
                       "  ↓ " + systemStats.formatMbps(systemStats.netRxMbps)
            showBar:   false
        }*/
    }

    // ── MetricCard component ──────────────────────────────────────────────────
    component MetricCard: Rectangle {
        id: card
        property string iconName:  ""
        property string labelText: ""
        property string valueText: ""
        property real   barValue:  0.0   // 0.0 – 1.0
        property color  barColor:  Kirigami.Theme.positiveTextColor
        property bool   showBar:   true

        color:  Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.cornerRadius

        // Subtle border using theme color
        /*border.color: Qt.rgba(
            Kirigami.Theme.textColor.r,
            Kirigami.Theme.textColor.g,
            Kirigami.Theme.textColor.b,
            0.08
        )*/

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.largeSpacing
            anchors.margins: Kirigami.Units.largeSpacing
            Layout.fillWidth: true
            // Icon
            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                source: card.iconName
                implicitWidth:  40 //Kirigami.Units.iconSizes.small
                implicitHeight: 40 //Kirigami.Units.iconSizes.small
            }

            ColumnLayout{
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        Layout.alignment:    Qt.AlignLeft
                        Layout.fillWidth:    true
                        text:                card.labelText
                        font.pixelSize:      Kirigami.Units.gridUnit * 0.7
                        font.weight:         Font.Medium
                        horizontalAlignment: Text.AlignLeft
                        elide:               Text.ElideRight
                        opacity:             0.75
                    }

                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Label {
                        Layout.alignment:    Qt.AlignRight
                        Layout.fillWidth:    true
                        text:                card.valueText
                        font.pixelSize:      Kirigami.Units.gridUnit * 0.75
                        horizontalAlignment: Text.AlignRight
                        elide:               Text.ElideRight
                        color:               card.showBar ? card.barColor : Kirigami.Theme.textColor
                        wrapMode:            Text.NoWrap
                    }
                }

                
                Rectangle {
                    id: progressBackground
                    Layout.fillWidth: card.showBar 
                    Layout.preferredHeight: 8
                    radius: height / 2
                    color: Kirigami.Theme.disabledTextColor
                    

                    Rectangle {
                        /*Layout.preferredWidth: card.barValue * 100
                        Layout.fillHeight: true
                        color: card.barColor */
                        id: progressFill
                        anchors {
                            left:            parent.left
                            top:             parent.top
                            bottom:          parent.bottom
                        }
                        width:  parent.width * card.barValue
                        radius: height / 2
                        color:  card.barColor

                        Behavior on width {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        } 
    }
}
