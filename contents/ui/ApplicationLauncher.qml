/**
 * ApplicationLauncher.qml — cuadrícula de aplicaciones con búsqueda
 *
 * Parte de com.github.yahir.systempanel (plasmoide de Plasma 6)
 * Destino: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 *
 * ── Interfaz externa (usada por main.qml) ────────────────────────────────────
 *   property int columns     — número de columnas de la cuadrícula; viene de
 *                               Plasmoid.configuration.launcherColumns (por defecto 4)
 *   function focusSearch()   — fuerza el foco de teclado en el campo de búsqueda;
 *                               se llama desde fullRepresentation.onActiveFocusChanged
 *
 * ── Carga de apps (dos pasos, ver AppLauncher.js) ───────────────────────────
 *   Paso 1 — findDesktopFiles() ejecuta un comando `find` para reunir
 *            las rutas absolutas de todos los archivos *.desktop del sistema.
 *   Paso 2 — AppLauncher.processDesktopFiles() lanza un XMLHttpRequest por
 *            cada ruta, analiza cada sección [Desktop Entry] y agrega las
 *            entradas válidas de Application a appModel.
 *   Paso 3 — filter("") se llama cuando terminan todas las lecturas XHR y
 *            copia la lista completa ordenada a filteredModel.
 *
 * ── Filtrado ────────────────────────────────────────────────────────────────
 *   Cada pulsación reconstruye filteredModel revisando appModel y buscando
 *   entradas cuyo nombre o descripción contengan el texto de búsqueda
 *   sin distinguir mayúsculas y minúsculas.
 *   Los resultados se ordenan alfabéticamente por nombre.
 */

import QtQuick
import QtCore
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid                  // Plasmoid singleton (expanded, etc.)
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/AppLauncher.js" as AppLauncher

Item {
    id: root

    // ── External interface ────────────────────────────────────────────────────

    /// Número de columnas en la cuadrícula; lo define main.qml desde la configuración.
    property int columns: 4

    /// Lo llama main.qml cuando el overlay recibe foco activo para que el
    /// usuario pueda empezar a escribir sin hacer clic primero.
    function focusSearch() {
        searchField.forceActiveFocus()
    }

    // ── Internal state ────────────────────────────────────────────────────────

    /// Verdadero mientras el escaneo inicial de *.desktop y las lecturas XHR siguen activas.
    property bool loading: true

    // ── Models ────────────────────────────────────────────────────────────────

    /// Lista maestra poblada una sola vez al arrancar por AppLauncher.processDesktopFiles().
    /// No se borra después de la carga inicial; es la fuente autoritativa para filter().
    ListModel { id: appModel }

    /// Subconjunto visible mostrado en appGrid. Se reconstruye cada vez que cambia searchField.text.
    ListModel { id: filteredModel }

    // ── Filtering / search ────────────────────────────────────────────────────

    /**
    * Reconstruye filteredModel a partir de appModel, conservando solo las
    * entradas cuyo nombre o descripción contengan `text` sin distinguir
    * mayúsculas y minúsculas.
    * Los resultados se ordenan alfabéticamente para que la cuadrícula sea
    * estable en cada pulsación.
    * Pasar una cadena vacía restaura la lista completa ordenada.
     */
    function filter(text) {
        var needle = text.toLowerCase()
        var results = []

        for (var i = 0; i < appModel.count; i++) {
            var app = appModel.get(i)
            if (needle === "" ||
                    app.name.toLowerCase().indexOf(needle) !== -1 ||
                    app.description.toLowerCase().indexOf(needle) !== -1) {
                results.push({
                    name:        app.name,
                    icon:        app.icon,
                    exec:        app.exec,
                    description: app.description,
                    categories:  app.categories
                })
            }
        }

        // Orden alfabético estable: hace la cuadrícula determinista
        // independientemente del orden en que terminaron los XHR asíncronos.
        results.sort(function(a, b) {
            var na = a.name.toLowerCase()
            var nb = b.name.toLowerCase()
            if (na < nb) return -1
            if (na > nb) return  1
            return 0
        })

        filteredModel.clear()
        for (var j = 0; j < results.length; j++) {
            filteredModel.append(results[j])
        }
    }

    // ── Paso 1: recolectar rutas *.desktop con `find` ─────────────────────────
    /**
    * Ejecuta un comando find para reunir rutas de archivos *.desktop desde
    * ubicaciones XDG estándar:
    *   /usr/share/applications          — paquetes de la distribución
    *   /usr/local/share/applications    — software instalado localmente
    *   $HOME/.local/share/applications  — apps instaladas por usuario
    *
    * `2>/dev/null` oculta errores de directorios inexistentes.
    * `head -400` limita la salida para evitar arranques muy lentos en sistemas
    *             con muchísimas aplicaciones.
     */
    function findDesktopFiles() {
        var proc = Qt.createQmlObject(
            'import QtCore; Process { }',
            root
        )

        proc.finished.connect(function() {
            var stdout = proc.readAllStandardOutput().toString().trim()
            if (stdout !== "") {
                var paths = stdout.split("\n").filter(function(p) {
                    return p.trim() !== ""
                })
                // Paso 2: leer y analizar cada archivo .desktop de forma asíncrona.
                AppLauncher.processDesktopFiles(appModel, paths, function() {
                    // Paso 3: todas las lecturas XHR terminaron; ya se puede renderizar.
                    root.loading = false
                    root.filter("")
                })
            } else {
                // `find` no devolvió nada (algo muy raro); se detiene el indicador.
                root.loading = false
            }
            proc.destroy()
        })

        var cmd = "find /usr/share/applications /usr/local/share/applications " +
                  "$HOME/.local/share/applications -maxdepth 1 -name '*.desktop' " +
                  "2>/dev/null | head -400"

        proc.command = "/bin/sh"
        proc.arguments = ["-c", cmd]
        proc.start()
    }

    // ── Paso 2b: lanzar la aplicación mediante Process ───────────────────────
    /**
    * Lanza una aplicación cuando el usuario hace clic en una tarjeta.
    * Crea un Process, ejecuta el comando y destruye el proceso enseguida
    * (patrón fire-and-forget).
     */
    function launchApp(execString) {
        var proc = Qt.createQmlObject(
            'import QtCore; Process { }',
            root
        )

        proc.finished.connect(function() {
            proc.destroy()
        })

        proc.command = "/bin/sh"
        proc.arguments = ["-c", execString]
        proc.start()
    }

    // Inicia el escaneo del directorio cuando este componente ya está construido.
    Component.onCompleted: {
        findDesktopFiles()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  UI
    // ═══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        // ── Barra de búsqueda ───────────────────────────────────────────────
        PlasmaComponents3.TextField {
            id: searchField
            Layout.fillWidth: true

            placeholderText: i18n("Search applications…")

            // Reserva espacio a la izquierda para el icono de búsqueda embebido.
            leftPadding: searchIcon.width + Kirigami.Units.smallSpacing * 3

            // Icono de búsqueda incrustado en el área de padding izquierdo.
            Kirigami.Icon {
                id: searchIcon
                anchors {
                    left:           parent.left
                    leftMargin:     Kirigami.Units.smallSpacing
                    verticalCenter: parent.verticalCenter
                }
                source:  "search"
                width:   Kirigami.Units.iconSizes.small
                height:  width
                opacity: 0.6
            }

            // Botón de limpiar (✕): visible solo cuando el campo tiene texto.
            rightPadding: clearButton.visible
                          ? clearButton.width + Kirigami.Units.smallSpacing
                          : Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: clearButton
                anchors {
                    right:          parent.right
                    rightMargin:    Kirigami.Units.smallSpacing / 2
                    verticalCenter: parent.verticalCenter
                }
                visible:   searchField.text !== ""
                icon.name: "edit-clear"
                flat:      true
                width:     Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                height:    width

                onClicked: searchField.clear()

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text:    i18n("Clear search")
                QQC2.ToolTip.delay:   Kirigami.Units.toolTipDelay
            }

            // Reconstruye la cuadrícula visible en cada pulsación.
            onTextChanged: root.filter(text)
        }

        // ── Área de cuadrícula de apps ───────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true   // fills all remaining vertical space

            // Indicador de carga: se muestra mientras el escaneo inicial sigue activo.
            PlasmaComponents3.BusyIndicator {
                anchors.centerIn: parent
                visible: root.loading
                running: visible
            }

            // Etiqueta "Sin resultados": se muestra solo cuando hay búsqueda activa y cero coincidencias.
            PlasmaComponents3.Label {
                anchors.centerIn: parent
                visible: !root.loading && filteredModel.count === 0 && searchField.text !== ""
                text:    i18n("No results found")
                opacity: 0.6
                font.italic: true
            }

            QQC2.ScrollView {
                anchors.fill: parent
                clip: true
                // Oculta la barra horizontal: la cuadrícula se ajusta por columnas.
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                GridView {
                    id: appGrid
                    model: filteredModel

                    // Evita una mala configuración con cero columnas.
                    readonly property int safeColumns: Math.max(1, root.columns)

                    // Divide el ancho disponible por igual; la altura admite icono + texto de dos líneas.
                    cellWidth:  Math.floor(width / safeColumns)
                    cellHeight: Kirigami.Units.iconSizes.large
                               + Kirigami.Units.gridUnit * 2.6
                               + Kirigami.Units.smallSpacing

                    clip:  true
                    focus: true

                    // Desplazamiento con inercia para una sensación nativa.
                    flickDeceleration:    1500
                    maximumFlickVelocity: 2500

                    // ── App tile delegate ──────────────────────────────────────
                    delegate: Item {
                        id: tileRoot
                        width:  appGrid.cellWidth
                        height: appGrid.cellHeight

                        // Animación de aparición: cada tarjeta entra suavemente
                        // cuando se llena la grilla o cambia la búsqueda.
                        opacity: 0
                        NumberAnimation on opacity {
                            from:    0
                            to:      1
                            duration: 150
                            running: true
                        }

                        // Resaltado al pasar el cursor: fondo sutil y acorde al tema.
                        Rectangle {
                            anchors {
                                fill:    parent
                                margins: Kirigami.Units.smallSpacing / 2
                            }
                            radius:  Kirigami.Units.cornerRadius
                            color:   tileMA.containsMouse
                                     ? Kirigami.Theme.hoverColor
                                     : "transparent"
                            opacity: 0.25
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        // ── Contenido de la tarjeta: icono + nombre ─────────────
                        ColumnLayout {
                            anchors {
                                fill:    parent
                                margins: Kirigami.Units.smallSpacing
                            }
                            spacing: Kirigami.Units.smallSpacing / 2

                            // Icono de la aplicación: se carga de forma asíncrona para
                            // mantener la UI responsive mientras se resuelven muchos iconos.
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                source:       model.icon || "application-x-executable"
                                width:        Kirigami.Units.iconSizes.large
                                height:       width
                                //asynchronous: true   // lazy-load; avoids blocking the UI thread
                            }

                            // Nombre de la aplicación: hasta dos líneas y truncado si hace falta.
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text:                model.name
                                horizontalAlignment: Text.AlignHCenter
                                elide:               Text.ElideRight
                                maximumLineCount:    2
                                wrapMode:            Text.Wrap
                                // Slightly smaller than the default body font
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                            }
                        }

                        // ── Manejo de clic: lanzar app y cerrar el panel ─────────
                        MouseArea {
                            id: tileMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor

                            onClicked: {
                                // Elimina códigos de campo XDG (%U, %f, %i, %k, %c …)
                                // antes de pasar el comando al shell; solo tienen sentido
                                // para launchers de desktop-file, no para ejecución directa.
                                var cleanExec = model.exec.replace(/ ?%[a-zA-Z]/g, "").trim()
                                if (cleanExec !== "") {
                                    root.launchApp(cleanExec)
                                }
                                // Colapsa el overlay del panel.
                                // Plasmoid es el singleton adjunto de org.kde.plasma.plasmoid
                                // y está disponible en todos los QML del plasmoide.
                                Plasmoid.expanded = false
                            }
                        }
                    }  // delegate
                }  // GridView
            }  // ScrollView
        }  // grid container Item
    }  // ColumnLayout
}  // root Item
