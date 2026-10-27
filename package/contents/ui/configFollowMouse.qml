import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "follow.js" as Follow

KCM.SimpleKCM {
    id: page

    property string cfg_followMouseScenes
    property alias cfg_followMouseDelayMs: delayBox.value

    // Keys of the other pages. followMouse itself is left out on every page: a page saves
    // all keys it declares, with the value from when the dialog opened, and following is
    // switched on and off in the context menu, also while the dialog is open.
    property bool cfg_showDuration
    property bool cfg_notifyOnSave
    property string cfg_clickMode
    property int cfg_holdDurationMs
    property int cfg_launchHoldDurationMs
    property string cfg_launchMode
    property bool cfg_launchRecording
    property string cfg_discardMode
    property string cfg_scrollUpScene
    property string cfg_scrollDownScene
    property string cfg_offlineColor
    property int cfg_offlineOpacity
    property string cfg_readyColor
    property int cfg_readyOpacity
    property string cfg_recordingColor
    property int cfg_recordingOpacity
    property string cfg_host
    property int cfg_port
    property string cfg_password

    // Own short-lived connection, only to offer the OBS scene names.
    ObsClient {
        id: sceneSource
        host: page.cfg_host
        port: page.cfg_port
        password: page.cfg_password
    }

    readonly property var assigned: Follow.parseScenes(cfg_followMouseScenes)

    // Connected screens from left to right. The name is the one KWin reports for the pointer.
    readonly property var screens: Array.from(Qt.application.screens)
        .sort((a, b) => a.virtualX - b.virtualX || a.virtualY - b.virtualY)

    function screenLabel(screen) {
        const product = (screen.manufacturer + " " + screen.model).trim();
        return product !== "" ? i18nc("@label screen: connector (maker and model)", "%1 (%2):", screen.name, product)
                              : i18nc("@label screen connector", "%1:", screen.name);
    }

    Kirigami.FormLayout {
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            text: i18n("Shows the scene of the screen the mouse pointer is on. Turn it on and off in the right-click menu of the widget. Changing the scene any other way, by mouse wheel, menu or in OBS, turns it off.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        Repeater {
            model: page.screens

            delegate: SceneComboBox {
                required property var modelData

                Kirigami.FormData.label: page.screenLabel(modelData)
                scenes: sceneSource.scenes
                current: page.assigned[modelData.name] || ""
                onPicked: scene => page.cfg_followMouseScenes = Follow.withScene(page.cfg_followMouseScenes, modelData.name, scene)
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: sceneSource.connected ? i18n("Screens without a scene switch nothing.")
                                        : i18n("OBS is not running, so no scenes are listed. Start OBS to see them.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        // Delay in milliseconds, shown in seconds; 0 switches immediately.
        QQC2.SpinBox {
            id: delayBox
            Kirigami.FormData.label: i18n("Switch after:")
            from: 0
            to: 5000
            stepSize: 100
            textFromValue: value => value === 0 ? i18n("Immediately")
                : i18n("%1 s", (value / 1000).toLocaleString(Qt.locale(), "f", 1).replace(/[,.]0$/, ""))
            valueFromText: text => {
                const seconds = Number.fromLocaleString(Qt.locale(), text.replace(/[^0-9,.]/g, "") || "0");
                return Math.round(seconds * 1000);
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("How long the pointer has to stay on a screen before its scene shows. Passing over a screen on the way to another then switches nothing.")
        }
    }
}
