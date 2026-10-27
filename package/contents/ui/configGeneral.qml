import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_host: hostField.text
    property alias cfg_port: portField.value
    property alias cfg_password: passwordField.text

    // Plasma passes every config key to every page; keys of the other pages are
    // declared here so the dialog does not log warnings. Only the current page is saved.
    // followMouse is left out, see configFollowMouse.qml.
    property bool cfg_showDuration
    property bool cfg_notifyOnSave
    property string cfg_clickMode
    property int cfg_holdDurationMs
    property int cfg_launchHoldDurationMs
    property string cfg_discardMode
    property string cfg_scrollUpScene
    property string cfg_scrollDownScene
    property string cfg_offlineColor
    property int cfg_offlineOpacity
    property string cfg_readyColor
    property int cfg_readyOpacity
    property string cfg_recordingColor
    property int cfg_recordingOpacity
    property string cfg_followMouseScenes
    property int cfg_followMouseDelayMs

    Kirigami.FormLayout {
        QQC2.TextField {
            id: hostField
            Kirigami.FormData.label: i18n("Host:")
        }

        QQC2.SpinBox {
            id: portField
            Kirigami.FormData.label: i18n("Port:")
            from: 1
            to: 65535
            // No thousands separator ("4.455" in German locale).
            textFromValue: value => String(value)
            valueFromText: text => parseInt(text)
        }

        Kirigami.PasswordField {
            id: passwordField
            Kirigami.FormData.label: i18n("Password:")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("Port and password are shown in OBS under Tools → WebSocket Server Settings → Show Connect Info. Leave the password empty if authentication is disabled there.")
        }
    }
}
