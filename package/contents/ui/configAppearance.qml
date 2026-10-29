import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls

import "seconds.js" as Seconds

KCM.SimpleKCM {
    id: page

    property alias cfg_showDuration: showDurationBox.checked
    property alias cfg_notifyOnSave: notifyOnSaveBox.checked
    property string cfg_clickMode
    property alias cfg_holdDurationMs: holdDurationBox.value
    property alias cfg_launchHoldDurationMs: launchHoldDurationBox.value
    property string cfg_launchMode
    property alias cfg_launchRecording: launchRecordingBox.checked
    property string cfg_discardMode
    property string cfg_scrollUpScene
    property string cfg_scrollDownScene
    property string cfg_offlineColor
    property int cfg_offlineOpacity
    property string cfg_readyColor
    property int cfg_readyOpacity
    property string cfg_recordingColor
    property int cfg_recordingOpacity

    // Keys of the other pages; followMouse is left out, see configFollowMouse.qml.
    property string cfg_followMouseScenes
    property int cfg_followMouseDelayMs

    // Keys of the connection page, see configGeneral.qml.
    property string cfg_host
    property int cfg_port
    property string cfg_password

    // Own short-lived connection, only to offer the OBS scene names in the wheel settings.
    ObsClient {
        id: sceneSource
        host: page.cfg_host
        port: page.cfg_port
        password: page.cfg_password
    }

    // Hold duration in milliseconds, shown in seconds.
    component HoldDurationBox: QQC2.SpinBox {
        from: 500
        to: 5000
        stepSize: 250
        textFromValue: value => i18n("%1 s", (value / 1000).toLocaleString(Qt.locale(), "f", 2).replace(/[,.]?0+$/, ""))
        valueFromText: text => {
            const seconds = Seconds.parse(text);
            return isNaN(seconds) ? value : Math.round(seconds * 1000);
        }
    }

    // Color and opacity of one state, stored in cfg_<key>Color / cfg_<key>Opacity.
    // An empty color means the theme color, which is what the button shows then.
    component StateRow: RowLayout {
        id: stateRow

        required property string key
        required property color themeColor
        readonly property string colorKey: "cfg_" + key + "Color"
        readonly property string opacityKey: "cfg_" + key + "Opacity"

        spacing: Kirigami.Units.smallSpacing

        KQuickControls.ColorButton {
            showAlphaChannel: false
            color: page[stateRow.colorKey] || stateRow.themeColor
            onAccepted: color => page[stateRow.colorKey] = color.toString()
        }

        QQC2.ToolButton {
            icon.name: "edit-undo"
            enabled: page[stateRow.colorKey] !== ""
            display: QQC2.AbstractButton.IconOnly
            text: i18n("Use system color")
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            onClicked: page[stateRow.colorKey] = ""
        }

        QQC2.Slider {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            from: 0
            to: 100
            stepSize: 5
            value: page[stateRow.opacityKey]
            onMoved: page[stateRow.opacityKey] = value
        }

        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
            horizontalAlignment: Text.AlignRight
            text: i18n("%1 %", page[stateRow.opacityKey])
        }
    }

    // Both radio groups share the FormLayout as parent; without explicit groups
    // autoExclusive would treat them as one.
    QQC2.ButtonGroup {
        id: clickModeGroup
    }

    QQC2.ButtonGroup {
        id: discardModeGroup
    }

    QQC2.ButtonGroup {
        id: launchModeGroup
    }

    Kirigami.FormLayout {
        StateRow {
            Kirigami.FormData.label: i18n("OBS closed:")
            key: "offline"
            themeColor: Kirigami.Theme.textColor
        }

        StateRow {
            Kirigami.FormData.label: i18n("OBS running:")
            key: "ready"
            themeColor: Kirigami.Theme.textColor
        }

        StateRow {
            Kirigami.FormData.label: i18n("Recording:")
            key: "recording"
            themeColor: Kirigami.Theme.negativeTextColor
        }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("Start/stop recording:")
            text: i18n("Single click")
            QQC2.ButtonGroup.group: clickModeGroup
            checked: page.cfg_clickMode === "single"
            onToggled: if (checked) page.cfg_clickMode = "single"
        }

        QQC2.RadioButton {
            text: i18n("Double click")
            QQC2.ButtonGroup.group: clickModeGroup
            checked: page.cfg_clickMode === "double"
            onToggled: if (checked) page.cfg_clickMode = "double"
        }

        QQC2.RadioButton {
            text: i18n("Start with single click, stop only with double click")
            QQC2.ButtonGroup.group: clickModeGroup
            checked: page.cfg_clickMode === "doubleToStop"
            onToggled: if (checked) page.cfg_clickMode = "doubleToStop"
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        SceneComboBox {
            Kirigami.FormData.label: i18n("Scroll up:")
            scenes: sceneSource.scenes
            current: page.cfg_scrollUpScene
            onPicked: scene => page.cfg_scrollUpScene = scene
        }

        SceneComboBox {
            Kirigami.FormData.label: i18n("Scroll down:")
            scenes: sceneSource.scenes
            current: page.cfg_scrollDownScene
            onPicked: scene => page.cfg_scrollDownScene = scene
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            visible: !sceneSource.connected
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("OBS is not running, so no scenes are listed. Start OBS to see them.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        HoldDurationBox {
            id: holdDurationBox
            Kirigami.FormData.label: i18n("Hold to discard:")
        }

        HoldDurationBox {
            id: launchHoldDurationBox
            Kirigami.FormData.label: i18n("Hold to launch:")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("How long the button has to be held to discard a running recording, or to launch OBS when it is not running.")
        }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("Launch OBS:")
            text: i18n("Normally")
            QQC2.ButtonGroup.group: launchModeGroup
            checked: page.cfg_launchMode !== "minimized" && page.cfg_launchMode !== "tray"
            onToggled: if (checked) page.cfg_launchMode = "normal"
        }

        QQC2.RadioButton {
            text: i18n("Minimized to the task manager")
            QQC2.ButtonGroup.group: launchModeGroup
            checked: page.cfg_launchMode === "minimized"
            onToggled: if (checked) page.cfg_launchMode = "minimized"
        }

        QQC2.RadioButton {
            text: i18n("Minimized to the system tray")
            QQC2.ButtonGroup.group: launchModeGroup
            checked: page.cfg_launchMode === "tray"
            onToggled: if (checked) page.cfg_launchMode = "tray"
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            visible: page.cfg_launchMode === "tray"
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("Applies only when the widget launches OBS. The system tray icon has to be enabled in OBS under Settings → General, otherwise the window cannot be reached.")
        }

        QQC2.CheckBox {
            id: launchRecordingBox
            text: i18n("Start recording right away")
        }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("Discarded recording:")
            text: i18n("Move to trash")
            QQC2.ButtonGroup.group: discardModeGroup
            checked: page.cfg_discardMode !== "delete"
            onToggled: if (checked) page.cfg_discardMode = "trash"
        }

        QQC2.RadioButton {
            text: i18n("Delete permanently")
            QQC2.ButtonGroup.group: discardModeGroup
            checked: page.cfg_discardMode === "delete"
            onToggled: if (checked) page.cfg_discardMode = "delete"
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            visible: page.cfg_discardMode === "delete"
            type: Kirigami.MessageType.Warning
            text: i18n("Discarded recordings cannot be restored then.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showDurationBox
            Kirigami.FormData.label: i18n("While recording:")
            text: i18n("Show duration")
        }

        QQC2.CheckBox {
            id: notifyOnSaveBox
            Kirigami.FormData.label: i18n("After stopping:")
            text: i18n("Show a notification with the file name")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: i18n("The slider sets the opacity of the dot, 0 % hides it. Without a custom color, the color of the Plasma theme is used. Pause (orange) and password errors (red outline) cannot be changed.")
        }
    }
}
