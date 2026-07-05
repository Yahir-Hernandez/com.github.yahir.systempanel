/**
 * main.qml — System Panel Plasmoid (com.github.yahir.systempanel)
 *
 * Componente raíz. Proporciona:
 *   • Un icono / botón compacto que vive en el panel de Plasma.
 *   • Un popup de casi pantalla completa con cuatro secciones:
 *       1. StatusBar           – usuario, batería, Wi-Fi, fecha/hora y host
 *       2. QuickSettings       – toggles de Wi-Fi/BT, volumen, brillo y más
 *       3. ApplicationLauncher – cuadrícula de apps con búsqueda en tiempo real
 *       4. SystemStats         – medidores de CPU / RAM / disco / temperatura / red
 *
 * Entorno objetivo:
 *   KDE Neon 24.04 (noble) · Plasma 6.x · Qt 6.x · KDE Frameworks 6.x
 *
 * Instalación:
 *   cp -r system-panel-plasmoid \
 *         ~/.local/share/plasma/plasmoids/com.github.yahir.systempanel
 *   kquitapp6 plasmashell && plasmashell &
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ─────────────────────────────────────────────────────────────────────
    //  Metadatos del plasmoide e integración con el panel
    // ─────────────────────────────────────────────────────────────────────
    Plasmoid.icon:            "utilities-system-monitor"
    Plasmoid.title:           i18n("System Panel")
    // Plasmoid.toolTipMainText: i18n("System Panel")
    //Plasmoid.toolTipSubText:  i18n("Quick access to system controls, apps and statistics")

    // Botón compacto en el panel; al hacer clic abre la vista completa.
    preferredRepresentation:   compactRepresentation
    activationTogglesExpanded: true

    // Cierra el popup cuando el usuario hace clic fuera de él,
    // salvo que esté configurando activamente el plasmoide.
    hideOnWindowDeactivate: !Plasmoid.userConfiguring

    // ─────────────────────────────────────────────────────────────────────
    //  Valores por defecto de configuración (editable con clic derecho)
    // ─────────────────────────────────────────────────────────────────────
    readonly property int   refreshIntervalSec:  Plasmoid.configuration.refreshInterval  ?? 2
    readonly property bool  showAnimations:      Plasmoid.configuration.showAnimations   ?? true
    readonly property int   launcherColumns:     Plasmoid.configuration.launcherColumns  ?? 4

    // ═════════════════════════════════════════════════════════════════════
    //  REPRESENTACIÓN COMPACTA  ─ icono / botón del panel
    // ═════════════════════════════════════════════════════════════════════
    compactRepresentation: Item {
        id: compactRoot

        implicitWidth:  Kirigami.Units.iconSizes.medium
        implicitHeight: Kirigami.Units.iconSizes.medium

        // Navegación por teclado
        activeFocusOnTab: true
        Accessible.name:          Plasmoid.title
        Accessible.role:          Accessible.Button
        Accessible.onPressAction: root.expanded = !root.expanded

        // ── Resaltado al pasar el cursor ─────────────────────────────────
        Rectangle {
            anchors.fill: parent
            radius:  Kirigami.Units.smallSpacing
            color:   compactMA.containsMouse ? Kirigami.Theme.hoverColor : "transparent"
            opacity: 0.25
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        // ── Icono del panel ──────────────────────────────────────────────
        Kirigami.Icon {
            id: panelIcon
            anchors.centerIn: parent
            width:  Math.min(parent.width, parent.height) * 0.75
            height: width
            source: "utilities-system-monitor"
            // Atenúa un poco el icono mientras el panel está abierto.
            opacity: root.expanded ? 0.70 : 1.0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        MouseArea {
            id: compactMA
            anchors.fill: parent
            hoverEnabled: true
            onClicked:    root.expanded = !root.expanded
        }

        Keys.onSpacePressed:  root.expanded = !root.expanded
        Keys.onReturnPressed: root.expanded = !root.expanded
    }

    // ═════════════════════════════════════════════════════════════════════
    //  REPRESENTACIÓN COMPLETA  ─ overlay del panel del sistema
    // ═════════════════════════════════════════════════════════════════════
    fullRepresentation:  FocusScope {
        id: fullRoot
        readonly property int scW: Screen.desktopAvailableWidth
        readonly property int scH: Screen.desktopAvailableHeight

        Layout.minimumWidth:    Kirigami.Units.gridUnit * 44
        Layout.minimumHeight:   Kirigami.Units.gridUnit * 34
        Layout.preferredWidth:  Math.min(scW * 0.92, Kirigami.Units.gridUnit * 108)
        Layout.preferredHeight: Math.min(scH * 0.88, Kirigami.Units.gridUnit * 72)
        Layout.maximumWidth:    scW
        Layout.maximumHeight:   scH

        // ── Manejo de teclado ────────────────────────────────────────────
        focus: true
        Keys.onEscapePressed: root.expanded = false

        // ── Animación de entrada ─────────────────────────────────────────
        opacity: root.expanded ? 1.0 : 0.0
        Behavior on opacity {
            enabled: root.showAnimations
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        // Deslizamiento hacia arriba al abrir.
        transform: Translate {
            y: root.expanded ? 0 : Kirigami.Units.gridUnit * 2
            Behavior on y {
                enabled: root.showAnimations
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // ── Fila superior: barra de estado, ancho completo ──────────────
            StatusBar {
                id: statusBar
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            }

            // ── Fila principal: dos columnas ─────────────────────────────────
            GridLayout {
                id: mainGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.largeSpacing

                ApplicationLauncher {
                    id: appLauncher
                    Layout.columnSpan: 2          // ocupa 2 de las 3 columnas → ~66%
                    // Layout.fillWidth: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 70
                    Layout.fillHeight: true
                    columns: root.launcherColumns
                }

                ColumnLayout {
                    Layout.columnSpan: 1          // ocupa 1 de las 3 columnas → ~33%
                    Layout.fillHeight: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 25
                    Layout.alignment: Qt.AlignRight
                    spacing: Kirigami.Units.largeSpacing

                    QuickSettings {
                        id: quickSettings
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    SystemStats {
                        id: systemStats
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        refreshInterval: root.refreshIntervalSec * 1000
                    }
                }
            }
        }

        onActiveFocusChanged: {
            if (activeFocus) {
                appLauncher.focusSearch()
            }
        }
    }
    
    
    /*FocusScope {
        id: fullRoot

        // ── Tamaño ───────────────────────────────────────────────────────
        // Solicita dimensiones casi a pantalla completa; Plasma las limita
        // automáticamente a la geometría disponible.
        readonly property int scW: Screen.desktopAvailableWidth
        readonly property int scH: Screen.desktopAvailableHeight

        Layout.minimumWidth:    Kirigami.Units.gridUnit * 44
        Layout.minimumHeight:   Kirigami.Units.gridUnit * 34
        Layout.preferredWidth:  Math.min(scW * 0.92, Kirigami.Units.gridUnit * 108)
        Layout.preferredHeight: Math.min(scH * 0.88, Kirigami.Units.gridUnit * 72)
        Layout.maximumWidth:    scW
        Layout.maximumHeight:   scH

        // ── Manejo de teclado ────────────────────────────────────────────
        focus: true
        Keys.onEscapePressed: root.expanded = false

        // ── Animación de entrada ─────────────────────────────────────────
        opacity: root.expanded ? 1.0 : 0.0
        Behavior on opacity {
            enabled: root.showAnimations
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }

        // Deslizamiento hacia arriba al abrir.
        transform: Translate {
            y: root.expanded ? 0 : Kirigami.Units.gridUnit * 2
            Behavior on y {
                enabled: root.showAnimations
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        // ── Fondo ────────────────────────────────────────────────────────
        // Fondo semitransparente que respeta el tema activo de Plasma.
        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius * 2
            color: Qt.rgba(
                Kirigami.Theme.backgroundColor.r,
                Kirigami.Theme.backgroundColor.g,
                Kirigami.Theme.backgroundColor.b,
                0.96
            )
            border.color: Kirigami.Theme.separatorColor
            border.width: 1
        }

        // ── Layout principal ─────────────────────────────────────────────
        ColumnLayout {
            id: mainLayout
            anchors {
                fill:    parent
                margins: Kirigami.Units.largeSpacing * 1.5
            }
            spacing: Kirigami.Units.largeSpacing

            // ── 1. Barra de estado ────────────────────────────────────────
            // Muestra usuario · batería · Wi-Fi · reloj · hostname.
            StatusBar {
                id: statusBar
                Layout.fillWidth:       true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 3.5
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ── 2. Ajustes rápidos ────────────────────────────────────────
            // Toggles de Wi-Fi / BT, volumen y brillo.
            // Un botón "Más" revela controles adicionales con animación suave.
            QuickSettings {
                id: quickSettings
                Layout.fillWidth: true
                // La altura se administra internamente (colapsado / expandido).
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ── 3. Lanzador de aplicaciones ──────────────────────────────
            // Buscador en tiempo real + cuadrícula de apps instaladas.
            // focusSearch() se llama automáticamente al abrir el panel.
            ApplicationLauncher {
                id: appLauncher
                Layout.fillWidth:  true
                Layout.fillHeight: true   // Takes all remaining vertical space.

                // Expone el número de columnas desde la configuración.
                columns: root.launcherColumns
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // ── 4. Estadísticas del sistema ──────────────────────────────
            // CPU · RAM · almacenamiento · temperatura · red.
            // Se consultan cada refreshIntervalSec segundos usando /proc y /sys.
            SystemStats {
                id: systemStats
                Layout.fillWidth:       true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 7.5

                refreshInterval: root.refreshIntervalSec * 1000
            }
        }

        // Enfoca automáticamente el buscador apenas el overlay recibe foco
        // (es decir, justo después de hacer clic en el botón del panel).
        onActiveFocusChanged: {
            if (activeFocus) {
                appLauncher.focusSearch()
            }
        }
    }*/  // fullRepresentation
}  // PlasmoidItem
