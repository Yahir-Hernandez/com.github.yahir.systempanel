// SPDX-License-Identifier: LGPL-2.0-or-later
// SPDX-FileCopyrightText: 2024 Yahir <com.github.yahir>
//
// config.qml — página de configuración del plasmoide
// Se muestra cuando el usuario hace clic derecho sobre el widget → Configurar…
//
// Plasma 6 crea automáticamente propiedades cfg_<key> para cada clave
// declarada en config/main.xml cuyo nombre coincida con una propiedad
// Plasmoid.configuration.* usada en los archivos QML.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {

    // ── Propiedades de configuración enlazadas ───────────────────────────────
    // El sistema de configuración de Plasma las crea automáticamente desde config/main.xml.
    // Los nombres deben coincidir con las claves usadas en main.qml mediante Plasmoid.configuration.*

    property int  cfg_refreshInterval: 2      // seconds
    property bool cfg_showAnimations:  true
    property int  cfg_launcherColumns: 4

    // ── Contenido de la página ────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        // ── Sección de rendimiento ─────────────────────────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true

            // Separador / título de sección
            Kirigami.Separator {
                Kirigami.FormData.label: i18n("Performance")
                Kirigami.FormData.isSection: true
                Layout.fillWidth: true
            }

            // Intervalo de refresco
            QQC2.SpinBox {
                id: refreshIntervalSpinBox
                Kirigami.FormData.label: i18n("Refresh interval (seconds):")

                from:  1
                to:    30
                value: cfg_refreshInterval

                onValueModified: cfg_refreshInterval = value

                textFromValue: function(value, locale) {
                    return value + " " + i18ncp("seconds abbreviation", "s", "s", value)
                }

                QQC2.ToolTip {
                    text: i18n("How often the system stats bar polls CPU, RAM, disk, temperature, and network data.")
                    visible: parent.hovered
                }
            }

            // Toggle de animaciones
            QQC2.CheckBox {
                id: animationsCheckBox
                Kirigami.FormData.label: i18n("Enable animations:")

                checked: cfg_showAnimations
                onToggled: cfg_showAnimations = checked

                QQC2.ToolTip {
                    text: i18n("Toggle smooth transitions when switching between launcher pages and opening/closing the panel.")
                    visible: parent.hovered
                }
            }
        }

        // ── Sección del lanzador ──────────────────────────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true

            Kirigami.Separator {
                Kirigami.FormData.label: i18n("Launcher")
                Kirigami.FormData.isSection: true
                Layout.fillWidth: true
            }

            // Número de columnas para la cuadrícula de apps
            QQC2.SpinBox {
                id: launcherColumnsSpinBox
                Kirigami.FormData.label: i18n("Launcher columns:")

                from:  2
                to:    6
                value: cfg_launcherColumns

                onValueModified: cfg_launcherColumns = value

                QQC2.ToolTip {
                    text: i18n("Number of columns in the application launcher grid (2-6).")
                    visible: parent.hovered
                }
            }

            // Nota informativa debajo del selector de columnas
            PlasmaCommentLabel {
                text: i18n("Wider panels benefit from more columns; narrower panels from fewer.")
            }
        }

        // Empuja todo hacia arriba.
        Item {
            Layout.fillHeight: true
        }
    }

    // ── Componente auxiliar pequeño: etiqueta de ayuda atenuada ──────────────
    component PlasmaCommentLabel: QQC2.Label {
        Layout.fillWidth:    true
        wrapMode:            Text.WordWrap
        font.pointSize:      Math.round(Kirigami.Theme.defaultFont.pointSize * 0.85)
        opacity:             0.6
    }
}
