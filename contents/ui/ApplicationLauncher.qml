/**
 * ApplicationLauncher.qml — Searchable application grid
 *
 * Part of com.github.yahir.systempanel (Plasma 6 plasmoid)
 * Target: KDE Neon 24.04 · Plasma 6.x · Qt 6.x · KF6
 *
 * ── External interface (used by main.qml) ────────────────────────────────────
 *   property int columns     — number of grid columns; driven by
 *                               Plasmoid.configuration.launcherColumns (default 4)
 *   function focusSearch()   — forces keyboard focus into the search field;
 *                               called from fullRepresentation.onActiveFocusChanged
 *
 * ── App loading (two-step, see AppLauncher.js) ───────────────────────────────
 *   Step 1 — findDS (executable DataSource) runs a `find` command to collect
 *            the absolute paths of all *.desktop files on the system.
 *   Step 2 — AppLauncher.processDesktopFiles() issues one XMLHttpRequest per
 *            path, parses each [Desktop Entry] section, and appends valid
 *            Application entries to appModel.
 *   Step 3 — filter("") is called once all XHR reads settle, which copies
 *            the full sorted list into filteredModel (the GridView's model).
 *
 * ── Filtering ────────────────────────────────────────────────────────────────
 *   Each keystroke rebuilds filteredModel by scanning appModel for entries
 *   whose name or description contains the search text (case-insensitive).
 *   Results are sorted alphabetically by name.
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid                  // Plasmoid singleton (expanded, etc.)
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "../code/AppLauncher.js" as AppLauncher
import org.kde.plasma.plasma5support as Plasma5Support
Item {
    id: root

    // ── External interface ────────────────────────────────────────────────────

    /// Number of columns in the app grid; set by main.qml from configuration.
    property int columns: 4

    /// Called by main.qml when the panel overlay gains active focus so the
    /// user can immediately start typing without clicking first.
    function focusSearch() {
        searchField.forceActiveFocus()
    }

    // ── Internal state ────────────────────────────────────────────────────────

    /// True while the initial *.desktop scan + XHR reads are still in progress.
    property bool loading: true

    // ── Models ────────────────────────────────────────────────────────────────

    /// Master list populated once at startup by AppLauncher.processDesktopFiles().
    /// Never cleared after initial load; serves as the authoritative source for filter().
    ListModel { id: appModel }

    /// Visible subset shown in appGrid.  Rebuilt on every change to searchField.text.
    ListModel { id: filteredModel }

    // ── Filtering / search ────────────────────────────────────────────────────

    /**
     * Rebuilds filteredModel from appModel, keeping only entries whose name
     * or description contains `text` (case-insensitive).
     * Results are sorted alphabetically so the grid is stable on each keystroke.
     * Passing an empty string restores the full sorted list.
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

        // Stable alphabetical sort — makes the grid deterministic regardless of
        // the order in which async XHR reads completed during startup.
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

    Rectangle {
        anchors.fill:    parent
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.cornerRadius
        border.color: Kirigami.Theme.disabledTextColor
    }

    // ── Step 1: Collect *.desktop paths via `find` ────────────────────────────
    /**
     * The `executable` DataSource engine passes the source name as a shell
     * command (via /bin/sh), so standard variables ($HOME) and operators
     * (pipes, redirection) all work as expected.
     *
     * We search three standard XDG locations:
     *   /usr/share/applications          — distribution packages
     *   /usr/local/share/applications    — locally installed software
     *   $HOME/.local/share/applications  — per-user installed apps
     *
     * `2>/dev/null` suppresses errors for directories that do not exist.
     * `head -400`   caps the output to avoid extremely long startup times on
     *               systems with many applications.
     */
 // ── Step 1: Collect *.desktop paths via `find` ────────────────────────────
    Plasma5Support.DataSource {
        id: findDS
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            var stdout = (data["stdout"] || "").toString().trim()

            if (stdout !== "") {
                var paths = stdout.split("\n").filter(function(p) {
                    return p.trim() !== ""
                })

                var validPaths = AppLauncher.processDesktopFiles(appModel, paths, function() {
                    root.loading = false
                    root.filter("")
                })

                for (var i = 0; i < validPaths.length; i++) {
                    fileReaderDS.readFile(validPaths[i])
                }
            } else {
                root.loading = false
            }

            disconnectSource(sourceName)
        }
    }

    // ── Step 2: Read each .desktop file's contents ────────────────────────────
    Plasma5Support.DataSource {
        id: fileReaderDS
        engine: "executable"
        connectedSources: []

        property var pathBySource: ({})

        onNewData: (sourceName, data) => {
            var content  = (data["stdout"] || "").toString()
            var filePath = pathBySource[sourceName]

            AppLauncher.handleDesktopFileContent(filePath, content)

            delete pathBySource[sourceName]
            disconnectSource(sourceName)
        }

        function readFile(path) {
            var cmd = "cat " + JSON.stringify(path)
            pathBySource[cmd] = path
            connectSource(cmd)
        }
    }

    // ── Step 3: Launch DataSource ──────────────────────────────────────────────
    Plasma5Support.DataSource {
        id: execDS
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, _data) {
            disconnectSource(sourceName)
        }
    }

    // Kick off the directory scan once this component is fully constructed.
    Component.onCompleted: {
        var cmd = "find /usr/share/applications /usr/local/share/applications " +
                  "$HOME/.local/share/applications -maxdepth 1 -name '*.desktop' " +
                  "2>/dev/null | head -400"
        findDS.connectSource(cmd)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  UI
    // ═══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing
        anchors.margins: Kirigami.Units.largeSpacing

        // ── Search bar ────────────────────────────────────────────────────────
        PlasmaComponents3.TextField {
            id: searchField
            Layout.fillWidth: true

            placeholderText: i18n("Search applications…")

            // Reserve room on the left for the inline search icon
            leftPadding: searchIcon.width + Kirigami.Units.smallSpacing * 3

            // Inline search icon embedded in the left padding area
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

            // Clear (✕) button — visible only when the field contains text
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

            // Rebuild the visible grid on every keystroke
            onTextChanged: root.filter(text)
        }

        // ── App grid area ─────────────────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true   // fills all remaining vertical space

            // Loading spinner — shown while the initial app scan is in progress
            /*PlasmaComponents3.BusyIndicator {
                anchors.centerIn: parent
                visible: root.loading
                running: visible
            }*/

            // "No results" label — shown only during an active search with 0 matches
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
                // Suppress horizontal scrollbar — the grid wraps by column count
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                GridView {
                    id: appGrid
                    model: filteredModel

                    // Guard against a zero-column misconfiguration from settings
                    readonly property int safeColumns: Math.max(1, root.columns)

                    // Divide available width evenly; height accommodates icon + two-line label
                    cellWidth:  Math.floor(width / safeColumns)
                    cellHeight: Kirigami.Units.iconSizes.large
                               + Kirigami.Units.gridUnit * 2.6
                               + Kirigami.Units.smallSpacing

                    clip:  true
                    focus: true

                    // Physics-based momentum scrolling for a native feel
                    flickDeceleration:    1500
                    maximumFlickVelocity: 2500

                    // ── App tile delegate ──────────────────────────────────────
                    delegate: Item {
                        id: tileRoot
                        width:  appGrid.cellWidth
                        height: appGrid.cellHeight

                        // Fade-in animation — each tile appears smoothly when the
                        // grid is first populated or after a search clears/changes
                        opacity: 0
                        NumberAnimation on opacity {
                            from:    0
                            to:      1
                            duration: 150
                            running: true
                        }

                        // Hover highlight — subtle, theme-respecting background
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

                        // ── Tile content: icon + name ──────────────────────────
                        ColumnLayout {
                            anchors {
                                fill:    parent
                                margins: Kirigami.Units.smallSpacing
                            }
                            spacing: Kirigami.Units.smallSpacing / 2

                            // Application icon — loaded asynchronously to keep the UI
                            // responsive while many icons are resolved in parallel
                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignHCenter
                                source:       model.icon || "application-x-executable"
                                width:        Kirigami.Units.iconSizes.large
                                height:       width
                                //asynchronous: true   // lazy-load; avoids blocking the UI thread
                            }

                            // Application name — up to two lines, right-truncated if needed
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

                        // ── Click handler — launch app and close the panel ──────
                        MouseArea {
                            id: tileMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor

                            onClicked: {
                                // Strip XDG field codes (%U, %f, %i, %k, %c …) before
                                // passing to the shell; they are only meaningful to
                                // desktop-file launchers, not raw command execution.
                                var cleanExec = model.exec.replace(/ ?%[a-zA-Z]/g, "").trim()
                                if (cleanExec !== "") {
                                    execDS.connectSource(cleanExec)
                                }
                                // Collapse the panel overlay.
                                // Plasmoid is the attached singleton from
                                // org.kde.plasma.plasmoid, accessible from all QML
                                // files within the plasmoid's component hierarchy.
                                Plasmoid.expanded = false
                            }
                        }
                    }  // delegate
                }  // GridView
            }  // ScrollView
        }  // grid container Item
    }  // ColumnLayout
}  // root Item
