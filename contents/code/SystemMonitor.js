// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2024 Yahir <com.github.yahir>
//
// SystemMonitor.js — ayudantes de parseo para datos de /proc
// Usado por SystemStats.qml como módulo .pragma library.

.pragma library

// ─────────────────────────────────────────────────────────────────────────────
// CPU
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Analiza una línea de salida de:
 *   awk '/^cpu /{for(i=2;i<=NF;i++) printf $i" "; print ""}' /proc/stat
 *
 * Campos de la línea cpu de /proc/stat (índices desde 0, sin la etiqueta cpu):
 *   0: user   1: nice   2: system   3: idle   4: iowait
 *   5: irq    6: softirq  7: steal  8: guest  9: guest_nice
 *
 * El comando awk ya elimina la etiqueta "cpu", así que la línea queda:
 *   "user nice system idle iowait irq softirq steal ..."
 *
 * Devuelve { user, nice, system, idle, iowait, irq, softirq, steal, total }
 * o null si el parseo falla.
 */
function parseCpuLine(line) {
    if (!line || line.trim() === "") return null

    var parts = line.trim().split(/\s+/)
    if (parts.length < 4) return null

    var user     = parseInt(parts[0]) || 0
    var nice     = parseInt(parts[1]) || 0
    var system   = parseInt(parts[2]) || 0
    var idle     = parseInt(parts[3]) || 0
    var iowait   = parseInt(parts[4]) || 0
    var irq      = parseInt(parts[5]) || 0
    var softirq  = parseInt(parts[6]) || 0
    var steal    = parseInt(parts[7]) || 0

    var total = user + nice + system + idle + iowait + irq + softirq + steal

    return {
        user:    user,
        nice:    nice,
        system:  system,
        idle:    idle,
        iowait:  iowait,
        irq:     irq,
        softirq: softirq,
        steal:   steal,
        total:   total
    }
}

/**
 * Calcula el porcentaje de uso de CPU a partir de dos resultados consecutivos
 * de parseCpuLine().
 *
 * Algoritmo:
 *   deltaTotal = curr.total - prev.total
 *   deltaIdle  = curr.idle  - prev.idle
 *   usage %    = (deltaTotal - deltaIdle) / deltaTotal * 100
 *
 * Devuelve un float de 0–100 (limitado), o 0 ante una entrada inválida.
 */
function cpuUsage(prev, curr) {
    if (!prev || !curr) return 0.0

    var deltaTotal = curr.total - prev.total
    if (deltaTotal <= 0) return 0.0

    var deltaIdle = curr.idle - prev.idle
    var usage     = (deltaTotal - deltaIdle) / deltaTotal * 100.0

    // clamp to [0, 100]
    if (usage < 0)   usage = 0.0
    if (usage > 100) usage = 100.0

    return usage
}

// ─────────────────────────────────────────────────────────────────────────────
// RAM
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Analiza la salida de:
 *   awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print t,a}' /proc/meminfo
 *
 * Returns { totalKB, availableKB, usedKB, usedPct }
 * or null on parse failure.
 *
 * Nota: "used" aquí significa total - disponible (incluye buffers/cache),
 * que refleja mejor la presión real sobre memoria.
 */
function parseMemInfo(line) {
    if (!line || line.trim() === "") return null

    var parts = line.trim().split(/\s+/)
    if (parts.length < 2) return null

    var totalKB     = parseInt(parts[0]) || 0
    var availableKB = parseInt(parts[1]) || 0

    if (totalKB <= 0) return null

    var usedKB  = totalKB - availableKB
    var usedPct = usedKB / totalKB * 100.0

    return {
        totalKB:     totalKB,
        availableKB: availableKB,
        usedKB:      usedKB,
        usedPct:     usedPct
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Disco
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Analiza la salida de:
 *   df -k / | awk 'NR==2{printf "%d %d",$3,$2}'
 *
 * El awk imprime: usedKB totalKB
 *
 * Returns { usedKB, totalKB, usedPct }
 * or null on parse failure.
 */
function parseDiskInfo(line) {
    if (!line || line.trim() === "") return null

    var parts = line.trim().split(/\s+/)
    if (parts.length < 2) return null

    var usedKB  = parseInt(parts[0]) || 0
    var totalKB = parseInt(parts[1]) || 0

    if (totalKB <= 0) return null

    var usedPct = usedKB / totalKB * 100.0

    return {
        usedKB:  usedKB,
        totalKB: totalKB,
        usedPct: usedPct
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Temperatura
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Analiza la temperatura desde /sys/class/thermal/thermal_zone0/temp.
 * El kernel reporta miligrados Celsius como una cadena entera simple, por
 * ejemplo "45000".
 *
 * Devuelve Celsius como float, o 0.0 si la entrada no es válida.
 */
function parseTemp(rawStr) {
    if (!rawStr || rawStr.trim() === "") return 0.0
    var raw = parseInt(rawStr.trim())
    if (isNaN(raw)) return 0.0
    // Divide by 1000 to convert millidegrees → degrees
    return raw / 1000.0
}

// ─────────────────────────────────────────────────────────────────────────────
// Red
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Calcula el rendimiento de red a partir de dos lecturas consecutivas de
 * /proc/net/dev.
 *
 * Cada lectura corresponde a la salida analizada de:
 *   awk 'NR>2 && !/lo/{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev
 * which sums RX/TX bytes across all non-loopback interfaces.
 *
 * prev / curr: objetos con { rx: <bytes>, tx: <bytes> }
 * elapsedMs:   milisegundos entre ambas lecturas
 *
 * Devuelve { rxMbps, txMbps } en megabits por segundo.
 *
 * Fórmula:
 *   deltaBytes = curr.rx - prev.rx
 *   bytesPerSec = deltaBytes / (elapsedMs / 1000)
 *   Mbps = bytesPerSec * 8 / 1_000_000
 */
function parseNetworkDelta(prev, curr, elapsedMs) {
    if (!prev || !curr || elapsedMs <= 0) {
        return { rxMbps: 0.0, txMbps: 0.0 }
    }

    var elapsedSec = elapsedMs / 1000.0

    var rxDeltaBytes = curr.rx - prev.rx
    var txDeltaBytes = curr.tx - prev.tx

    // Protege contra wrap-around de contadores o deltas negativos.
    if (rxDeltaBytes < 0) rxDeltaBytes = 0
    if (txDeltaBytes < 0) txDeltaBytes = 0

    var rxMbps = (rxDeltaBytes / elapsedSec) * 8 / 1000000.0
    var txMbps = (txDeltaBytes / elapsedSec) * 8 / 1000000.0

    return {
        rxMbps: rxMbps,
        txMbps: txMbps
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utilidad
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Formatea un tamaño dado en kilobytes como una cadena legible.
 *
 * Umbrales:
 *   < 1 MB   →  "X KB"
 *   < 1 GB   →  "X.X MB"
 *   >= 1 GB  →  "X.XX GB"
 */
function formatBytes(kb) {
    if (kb < 0)       kb = 0
    if (kb < 1024) {
        return kb.toFixed(0) + " KB"
    }
    var mb = kb / 1024.0
    if (mb < 1024) {
        return mb.toFixed(1) + " MB"
    }
    var gb = mb / 1024.0
    return gb.toFixed(2) + " GB"
}
