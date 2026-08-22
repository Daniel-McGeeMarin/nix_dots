import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// On-screen push-to-talk indicator. Reads $XDG_RUNTIME_DIR/workmic/state,
// which the workmic script writes on every transition: off | armed | talking.
ShellRoot {
    id: root

    property string mode: "off"
    readonly property string pos: Quickshell.env("WORKMIC_POSITION") || "bottom-right"

    FileView {
        id: stateFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/workmic/state"
        watchChanges: true
        blockLoading: true
        onLoaded: root.mode = text().trim()
        onFileChanged: {
            reload();
            root.mode = text().trim();
        }
    }

    PanelWindow {
        id: win
        visible: root.mode !== "off"

        anchors.bottom: root.pos.indexOf("bottom") === 0
        anchors.top: root.pos.indexOf("top") === 0
        anchors.right: root.pos.indexOf("right") !== -1
        anchors.left: root.pos.indexOf("left") !== -1
        margins.bottom: 16
        margins.top: 16
        margins.right: 16
        margins.left: 16

        implicitWidth: pill.implicitWidth
        implicitHeight: pill.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}   // click-through — never steals input

        Rectangle {
            id: pill
            readonly property bool live: root.mode === "talking"

            implicitWidth: row.implicitWidth + 26
            implicitHeight: 36
            radius: height / 2
            color: live ? "#e5484d" : "#1e222bd0"
            border.width: live ? 0 : 1
            border.color: "#3a4150"

            SequentialAnimation on opacity {
                running: pill.live
                loops: Animation.Infinite
                NumberAnimation { to: 0.6; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
            }
            onLiveChanged: if (!live) opacity = 1.0

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.live ? "" : ""
                    font.family: "Ubuntu Nerd Font"
                    font.pixelSize: 16
                    color: pill.live ? "#ffffff" : "#8b93a5"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pill.live ? "MIC LIVE" : "PTT"
                    font.family: "Ubuntu Nerd Font"
                    font.pixelSize: 13
                    font.bold: pill.live
                    color: pill.live ? "#ffffff" : "#8b93a5"
                }
            }
        }
    }
}
