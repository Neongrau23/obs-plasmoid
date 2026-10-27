import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "fader.js" as Fader

// Popup with one volume slider and mute button per OBS audio input.
PlasmaExtras.Representation {
    id: mixer

    required property var client

    readonly property bool empty: !client.connected || client.audioInputs.count === 0

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 8
    Layout.preferredHeight: Math.min(header.implicitHeight + list.contentHeight + Kirigami.Units.largeSpacing * 2,
                                     Kirigami.Units.gridUnit * 24)

    header: PlasmaExtras.PlasmoidHeading {
        PlasmaExtras.Heading {
            anchors.fill: parent
            leftPadding: Kirigami.Units.smallSpacing
            level: 1
            text: i18n("Audio Mixer")
        }
    }

    PlasmaComponents3.ScrollView {
        anchors.fill: parent

        ListView {
            id: list
            model: mixer.client.audioInputs
            topMargin: Kirigami.Units.largeSpacing
            bottomMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            delegate: ColumnLayout {
                id: row

                required property string name
                required property real volumeMul
                required property bool muted

                width: ListView.view.width
                spacing: 0

                RowLayout {
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: row.name
                        elide: Text.ElideRight
                    }

                    PlasmaComponents3.Label {
                        opacity: 0.7
                        font.features: ({ "tnum": 1 })
                        text: row.muted ? i18n("muted")
                            : Fader.formatDb(slider.pressed ? Fader.positionToMul(slider.value) : row.volumeMul)
                    }
                }

                RowLayout {
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing

                    PlasmaComponents3.ToolButton {
                        icon.name: row.muted ? "audio-volume-muted" : "audio-volume-high"
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        text: row.muted ? i18n("Unmute") : i18n("Mute")
                        PlasmaComponents3.ToolTip.text: text
                        PlasmaComponents3.ToolTip.visible: hovered
                        onClicked: mixer.client.setInputMuted(row.name, !row.muted)
                    }

                    PlasmaComponents3.Slider {
                        id: slider
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        opacity: row.muted ? 0.5 : 1
                        onMoved: mixer.client.setInputVolume(row.name, Fader.positionToMul(value))

                        // Follow OBS, but not while dragging, so incoming events do not fight the mouse.
                        Binding on value {
                            value: Fader.mulToPosition(row.volumeMul)
                            when: !slider.pressed
                            restoreMode: Binding.RestoreNone
                        }
                    }
                }
            }
        }
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: mixer.empty
        iconName: "audio-volume-muted"
        text: !mixer.client.connected ? i18n("OBS is not running") : i18n("No audio sources")
    }
}
