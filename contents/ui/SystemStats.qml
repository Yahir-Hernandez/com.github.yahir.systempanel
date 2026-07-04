// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2024 Yahir <com.github.yahir>

import QtQuick
import QtCore
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "../code/SystemMonitor.js" as SysMon

Item {
    id: systemStats

    // Intervalo de refresco en milisegundos (por defecto 2000 ms, lo define el padre desde la configuración).
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
    property var   netPrevSample:    null
    property int   netPrevTimestamp: 0
    property real  netTxMbps:        0.0
    property real  netRxMbps:        0.0

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

    function formatMbps(mbps) {
        if (mbps >= 1000) return (mbps / 1000).toFixed(1) + " Gbps"
        if (mbps >= 1)    return mbps.toFixed(1) + " Mbps"
        return (mbps * 1000).toFixed(0) + " Kbps"
    }

    // ── Data collection ────────────────────────────────────────────────────────

    // Commands
    readonly property string cmdCpu:  "awk '/^cpu /{for(i=2;i<=NF;i++) printf $i\" \"; print \"\"}' /proc/stat"
    readonly property string cmdRam:  "awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print t, a}' /proc/meminfo"
    readonly property string cmdDisk: "df -k / | awk 'NR==2{printf \"%d %d\", $3, $2}'"
    readonly property string cmdTemp: "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo \"0\""
    readonly property string cmdNet:  "awk 'NR>2 && !/lo/{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev"

    /**
     * Execute a shell command and call the callback with the output.
     * The Process is destroyed after completion.
     */
    function execCommand(cmd, callback) {
        var proc = Qt.createQmlObject(
            'import QtCore; Process { }',
            systemStats
        )

        proc.finished.connect(function() {
            var output = proc.readAllStandardOutput().toString().trim()
            if (callback) {
                callback(output)
            }
            proc.destroy()
        })

        proc.command = "/bin/sh"
        proc.arguments = ["-c", cmd]
        proc.start()
    }

    function refreshAll() {
        // CPU: first sample — store and schedule second sample
        cpuWaitingDiff = true
        execCommand(cmdCpu, function(output) {
            handleCpu(output)
        })

        // RAM, Disk, Temp, Net run immediately
        execCommand(cmdRam, function(output) {
            handleRam(output)
        })

        execCommand(cmdDisk, function(output) {
            handleDisk(output)
        })

        execCommand(cmdTemp, function(output) {
            handleTemp(output)
        })

        execCommand(cmdNet, function(output) {
            handleNet(output)
        })
    }

    // Second CPU sample fires 500ms after the first
    Timer {
        id: cpuDiffTimer
        interval: 500
        repeat: false
        onTriggered: {
            execCommand(systemStats.cmdCpu, function(output) {
                handleCpu(output)
            })
        }
    }

    Timer {
        id: refreshTimer
        interval: refreshInterval
        running: true
        repeat: true
        onTriggered: refreshAll()
    }

    Component.onCompleted: refreshAll()

    // ── Output handler ─────────────────────────────────────────────────────────

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

    function handleNet(output) {
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
    }

    // ── UI ─────────────────────────────────────────────────────────────────────

    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

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
        MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  systemStats.tempIcon(systemStats.tempCelsius)
            labelText: i18n("Temp")
            valueText: Math.round(systemStats.tempCelsius) + " °C"
            showBar:   false
        }

        // ── Network card ─────────────────────────────────────────────────────
        MetricCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            iconName:  "network-wired"
            labelText: i18n("Net")
            valueText: "↑ " + systemStats.formatMbps(systemStats.netTxMbps) +
                       "  ↓ " + systemStats.formatMbps(systemStats.netRxMbps)
            showBar:   false
        }
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
        border.color: Qt.rgba(
            Kirigami.Theme.textColor.r,
            Kirigami.Theme.textColor.g,
            Kirigami.Theme.textColor.b,
            0.08
        )
        border.width: 1

        ColumnLayout {
            anchors {
                fill:    parent
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing / 2

            // Icon
            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                source: card.iconName
                implicitWidth:  Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            // Label (metric name)
            PlasmaComponents3.Label {
                Layout.alignment:    Qt.AlignHCenter
                Layout.fillWidth:    true
                text:                card.labelText
                font.pixelSize:      Kirigami.Units.gridUnit * 0.7
                font.weight:         Font.Medium
                horizontalAlignment: Text.AlignHCenter
                elide:               Text.ElideRight
                opacity:             0.75
            }

            // Value
            PlasmaComponents3.Label {
                Layout.alignment:    Qt.AlignHCenter
                Layout.fillWidth:    true
                text:                card.valueText
                font.pixelSize:      Kirigami.Units.gridUnit * 0.75
                horizontalAlignment: Text.AlignHCenter
                elide:               Text.ElideRight
                color:               card.showBar ? card.barColor : Kirigami.Theme.textColor
                wrapMode:            Text.NoWrap
            }

            // Progress bar (optional)
            //Kirigami.ProgressBar {
            //    Layout.fillWidth: true
            //    visible:  card.showBar
            //    value:    card.barValue
            //    from:     0.0
            //    to:       1.0
            //
            //    // Tint the bar using the color-coded foreground
            //    Kirigami.Theme.highlightColor: card.barColor
            //}

            Item { Layout.fillHeight: true }
        }
    }
}
