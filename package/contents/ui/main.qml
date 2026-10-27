import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.notification
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus

import "follow.js" as Follow

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property string durationText: formatDuration(obs.durationMs)

    function formatDuration(ms) {
        const total = Math.floor(ms / 1000);
        const h = Math.floor(total / 3600);
        const m = Math.floor(total / 60) % 60;
        const s = total % 60;
        const pad = n => String(n).padStart(2, "0");
        return (h > 0 ? h + ":" : "") + pad(m) + ":" + pad(s);
    }

    // Whether starting (or stopping, while recording) needs a double click; see clickMode in main.xml.
    function needsDoubleClick(recording) {
        const mode = Plasmoid.configuration.clickMode;
        return mode === "double" || (mode === "doubleToStop" && recording);
    }

    readonly property string toggleHint: needsDoubleClick(obs.recording) ? i18n("Double click") : i18n("Click")

    // Set by each single click: whether it already acted, so the second half of a
    // double click does not undo it (e.g. a start immediately followed by a stop).
    property bool lastClickActed: false

    function handleClick() {
        lastClickActed = !(obs.connected && needsDoubleClick(obs.recording));
        if (lastClickActed) {
            activate();
        }
    }

    function handleDoubleClick() {
        if (!lastClickActed && obs.connected && needsDoubleClick(obs.recording)) {
            obs.toggleRecord();
        }
    }

    // Mouse wheel over the dot switches to a fixed scene per direction (scrollUpScene /
    // scrollDownScene). Small touchpad steps add up to one notch (120) before anything happens.
    // Partial steps only count within one gesture in one direction: a reversal or a pause
    // drops them, otherwise leftovers would swallow the next real notch.
    property int wheelDelta: 0

    Timer {
        id: wheelResetTimer
        interval: 400
        onTriggered: root.wheelDelta = 0
    }

    function handleWheel(angleDelta, inverted) {
        const delta = (inverted ? -1 : 1) * angleDelta.y;
        if (delta === 0) {
            return;
        }
        if (Math.sign(delta) !== Math.sign(wheelDelta)) {
            wheelDelta = 0;
        }
        wheelDelta += delta;
        wheelResetTimer.restart();
        if (Math.abs(wheelDelta) < 120) {
            return;
        }
        const scene = wheelDelta > 0 ? Plasmoid.configuration.scrollUpScene
                                     : Plasmoid.configuration.scrollDownScene;
        wheelDelta = 0;
        // One flick of the wheel delivers several notches within milliseconds; switchScene()
        // ignores all of them until OBS has finished the transition of the first.
        if (scene !== "") {
            stopFollowingMouse();
            obs.switchScene(scene);
        }
    }

    // Keep the wheel and screen assignments when a scene is renamed in OBS.
    function followSceneRename(oldName, newName) {
        if (Plasmoid.configuration.scrollUpScene === oldName) {
            Plasmoid.configuration.scrollUpScene = newName;
        }
        if (Plasmoid.configuration.scrollDownScene === oldName) {
            Plasmoid.configuration.scrollDownScene = newName;
        }
        const screenScenes = Follow.renameScene(Plasmoid.configuration.followMouseScenes, oldName, newName);
        if (screenScenes !== Plasmoid.configuration.followMouseScenes) {
            Plasmoid.configuration.followMouseScenes = screenScenes;
        }
        follower.sceneRenamed(oldName, newName);
    }

    // Scene follows the mouse pointer: ScreenFollower switches to the scene assigned to the
    // screen the pointer is on. KWin knows that screen but sends no signal for it over
    // D-Bus, so the widget asks every 100 ms while following is on and OBS connected.
    readonly property bool followingMouse: Plasmoid.configuration.followMouse && follower.hasScenes
    property bool followQueryPending: false

    ScreenFollower {
        id: follower
        client: obs
        scenesJson: Plasmoid.configuration.followMouseScenes
        delayMs: Plasmoid.configuration.followMouseDelayMs
        onOtherSceneChange: root.stopFollowingMouse()
    }

    function setFollowMouse(on) {
        follower.reset();
        Plasmoid.configuration.followMouse = on;
    }

    function stopFollowingMouse() {
        if (Plasmoid.configuration.followMouse) {
            setFollowMouse(false);
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: root.followingMouse && obs.connected
        onTriggered: root.queryPointerScreen()
    }

    function queryPointerScreen() {
        if (followQueryPending) {
            return;
        }
        followQueryPending = true;
        // The screen under the pointer, as long as KWin's option ActiveMouseScreen is on
        // (default); otherwise the screen of the active window.
        const reply = DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/KWin",
            iface: "org.kde.KWin",
            member: "activeOutputName",
            arguments: []
        });
        reply.finished.connect(() => {
            followQueryPending = false;
            if (!reply.isError && followingMouse && obs.connected) {
                follower.pointerOn(String(reply.value));
            }
        });
    }

    readonly property string wheelHint: {
        const up = Plasmoid.configuration.scrollUpScene;
        const down = Plasmoid.configuration.scrollDownScene;
        if (up !== "" && down !== "") {
            return "\n" + i18n("Scroll up: %1 · down: %2", up, down);
        }
        if (up !== "") {
            return "\n" + i18n("Scroll up: %1", up);
        }
        return down !== "" ? "\n" + i18n("Scroll down: %1", down) : "";
    }

    function activate() {
        switch (obs.connectionState) {
        case "connected":
            obs.toggleRecord();
            break;
        case "authRequired":
        case "authFailed":
            Plasmoid.internalAction("configure").trigger();
            break;
        default:
            obs.reconnect();
        }
    }

    preferredRepresentation: compactRepresentation
    // Audio mixer popup, opened from the context menu; left click stays on the compact view.
    // Without a fullRepresentation Plasma would not create the compact view either.
    fullRepresentation: Mixer {
        client: obs
    }
    toolTipMainText: i18n("OBS Control")
    toolTipSubText: {
        if (obs.lastError !== "") {
            return i18n("Error: %1", obs.lastError);
        }
        const scene = obs.currentScene !== "" ? "\n" + i18n("Scene: %1", obs.currentScene) + wheelHint
                                                + (followingMouse ? "\n" + i18n("Scene follows the mouse pointer") : "")
                                              : "";
        switch (obs.connectionState) {
        case "connected":
            if (obs.paused) {
                return i18n("Recording paused – %1", durationText) + scene
                     + "\n" + i18n("%1: stop · Middle click: resume", toggleHint)
                     + "\n" + i18n("Hold: discard recording");
            }
            return obs.recording ? i18n("Recording – %1", durationText) + scene
                                   + "\n" + i18n("%1: stop · Middle click: pause", toggleHint)
                                   + "\n" + i18n("Hold: discard recording")
                                 : i18n("Ready") + scene + "\n" + i18n("%1: start recording", toggleHint);
        case "authRequired":
            return i18n("OBS requires a password\nClick to enter it in the settings");
        case "authFailed":
            return i18n("Password rejected\nClick to check it in the settings");
        }
        if (launchingObs) {
            return i18n("Launching OBS…");
        }
        return i18n("OBS is not running – connects automatically once OBS starts")
             + "\n" + (Plasmoid.configuration.launchRecording ? i18n("Hold: launch OBS and record")
                                                                : i18n("Hold: launch OBS"));
    }

    // Holding the button while OBS is not reachable starts it. Set until OBS connects or 30 s pass.
    property bool launchingObs: false

    Timer {
        id: launchTimeout
        interval: 30000
        onTriggered: root.launchingObs = false
    }

    function launchObs() {
        if (launchingObs || obs.connected) {
            return;
        }
        launchingObs = true;
        launchTimeout.restart();
        if (Plasmoid.configuration.launchMode === "minimized") {
            loadMinimizeScript(startObs);
        } else {
            startObs();
        }
    }

    // Calls OBS directly (package, else Flatpak), since the desktop entry takes no arguments.
    // OBS starts the recording itself once loaded, before that a request could get lost.
    // The screen capture portal tells apps apart by their systemd unit and keeps the chosen
    // screens for com.obsproject.Studio; "kstart -- obs" would run in app-obs@….service and
    // capture black. So the package build gets the unit name a start from the menu gets,
    // Flatpak sets it itself. kstart reports no error for a missing command, hence the check
    // before (exit code 4).
    function startObs() {
        const args = (Plasmoid.configuration.launchMode === "tray" ? " --minimize-to-tray" : "")
            + (Plasmoid.configuration.launchRecording ? " --startrecording" : "");
        const start = "if command -v obs >/dev/null; then "
            + "if command -v systemd-run >/dev/null; then setsid -f systemd-run --user --scope --quiet "
            + "--unit=app-com.obsproject.Studio-$$.scope obs" + args + " >/dev/null 2>&1; "
            + "else kstart -- obs" + args + "; fi; "
            + "elif flatpak info com.obsproject.Studio >/dev/null 2>&1; then "
            + "kstart -- flatpak run com.obsproject.Studio" + args + "; else exit 4; fi";
        // Exit code 3: OBS runs already, so the WebSocket connection is what fails.
        executable.run("pgrep -x obs >/dev/null && exit 3; " + start,
                       (exitCode, stderr) => {
            if (exitCode === 0) {
                return;
            }
            launchingObs = false;
            unloadMinimizeScript();
            if (exitCode === 3) {
                notify(i18n("OBS is already running"),
                       i18n("But the widget cannot reach it. In OBS, enable the server under Tools → WebSocket Server Settings and compare port and password with the widget settings."),
                       "dialog-warning");
            } else if (exitCode === 4) {
                notify(i18n("Could not launch OBS"),
                       i18n("Neither the command “obs” nor the Flatpak com.obsproject.Studio is installed."),
                       "dialog-error");
            } else {
                notify(i18n("Could not launch OBS"), errorText(stderr), "dialog-error");
            }
        });
    }

    // OBS has no option to start minimized to the task bar, so KWin does it: the widget
    // loads contents/code/minimize-obs.js for this one start and removes it afterwards.
    // If KWin refuses the script, OBS starts normally.
    readonly property string minimizeScriptName: Plasmoid.pluginName + ".minimize"

    Timer {
        id: minimizeScriptTimeout
        interval: 31000
        onTriggered: root.unloadMinimizeScript()
    }

    // Calls a method of KWin's scripting interface; callback gets the result or null on error.
    function kwinScripting(member, args, callback) {
        const reply = DBus.SessionBus.asyncCall({
            service: "org.kde.KWin",
            path: "/Scripting",
            iface: "org.kde.kwin.Scripting",
            member: member,
            arguments: args.map(arg => new DBus.string(arg))
        });
        reply.finished.connect(() => callback(reply.isError ? null : reply.value));
    }

    function loadMinimizeScript(then) {
        const path = decodeURIComponent(Qt.resolvedUrl("../code/minimize-obs.js").toString().replace(/^file:\/\//, ""));
        // A script left over from an earlier start would block loading under the same name.
        kwinScripting("unloadScript", [minimizeScriptName], () => {
            kwinScripting("loadScript", [path, minimizeScriptName], id => {
                if (id === null || id < 0) {
                    console.warn("KWin did not load", path);
                    then();
                    return;
                }
                minimizeScriptTimeout.restart();
                kwinScripting("start", [], () => then());
            });
        });
    }

    function unloadMinimizeScript() {
        minimizeScriptTimeout.stop();
        kwinScripting("unloadScript", [minimizeScriptName], () => {});
    }

    ObsClient {
        id: obs
        host: Plasmoid.configuration.host
        port: Plasmoid.configuration.port
        password: Plasmoid.configuration.password
        onRecordingSaved: path => {
            root.notifySaved(path);
            if (root.quittingObs) {
                root.terminateObs();
            }
        }
        onRecordingDiscarded: path => root.removeRecording(path)
        onSceneRenamed: (oldName, newName) => root.followSceneRename(oldName, newName)
        onConnectedChanged: {
            Qt.callLater(root.updateContextualActions);
            if (connected) {
                root.launchingObs = false;
            } else {
                root.quittingObs = false;
            }
        }
    }

    // Quitting from the menu stops a running recording first and waits until OBS has written
    // the file. OBS has no WebSocket request to quit, but shuts down cleanly on SIGTERM.
    property bool quittingObs: false

    function quitObs() {
        if (!obs.connected || quittingObs) {
            return;
        }
        quittingObs = true;
        if (obs.recording) {
            obs.stopRecording();
        } else {
            terminateObs();
        }
    }

    function terminateObs() {
        executable.run("pkill -x -u \"$(id -u)\" obs", (exitCode, stderr) => {
            // Exit code 1: no OBS process (any more), nothing to do.
            if (exitCode > 1) {
                quittingObs = false;
                notify(i18n("Could not quit OBS"), errorText(stderr), "dialog-error");
            }
        });
    }

    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function folderUrl(path) {
        const url = fileUrl(path);
        return url.substring(0, url.lastIndexOf("/") + 1);
    }

    // actionLabel/actionUrl: optional button; fileUrls: files Plasma shows as preview.
    function notify(title, text, iconName, actionLabel, actionUrl, fileUrls) {
        const notification = notificationComponent.createObject(root, {
            title: title,
            text: text,
            iconName: iconName,
            actionUrl: actionUrl || ""
        });
        // Not as initial properties: createObject silently drops list properties there.
        notification.urls = fileUrls || [];
        if (actionLabel) {
            notification.actions[0].label = actionLabel;
        } else {
            notification.actions = [];
        }
        notification.sendEvent();
    }

    function notifySaved(path) {
        if (Plasmoid.configuration.notifyOnSave) {
            notify(i18n("Recording saved"), path.split("/").pop(), "media-record",
                   i18n("Open Folder"), folderUrl(path), [fileUrl(path)]);
        }
    }

    // stderr without Qt logging lines ("kf.kio...: ...") and the program name prefix.
    function errorText(stderr) {
        return stderr.split("\n")
            .filter(line => line.trim() !== "" && !/^[a-z]+(\.[a-z0-9_]+)+:/.test(line))
            .map(line => line.replace(/^(kioclient|rm): /, ""))
            .join("\n");
    }

    // OBS cannot delete files, so the widget does it: kioclient for the KDE trash, rm otherwise.
    function removeRecording(path) {
        const name = path.split("/").pop();
        const toTrash = Plasmoid.configuration.discardMode !== "delete";
        const quoted = "'" + path.replace(/'/g, "'\\''") + "'";
        const command = toTrash ? "kioclient --noninteractive --platform offscreen move " + quoted + " trash:/"
                                : "rm -- " + quoted;
        executable.run(command, (exitCode, stderr) => {
            if (exitCode !== 0) {
                notify(i18n("Could not remove the recording"),
                       i18n("%1 is still in the recording folder.\n%2", name, errorText(stderr)), "dialog-error",
                       i18n("Open Folder"), folderUrl(path), [fileUrl(path)]);
            } else if (toTrash) {
                notify(i18n("Recording discarded"), i18n("%1 was moved to the trash.", name), "user-trash-full",
                       i18n("Open Trash"), "trash:/");
            } else {
                notify(i18n("Recording discarded"), i18n("%1 was deleted permanently.", name), "edit-delete");
            }
        });
    }

    P5Support.DataSource {
        id: executable

        // command -> function(exitCode, stderr)
        property var callbacks: ({})

        function run(command, callback) {
            callbacks[command] = callback;
            connectSource(command);
        }

        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            const callback = callbacks[source];
            delete callbacks[source];
            if (callback) {
                callback(data["exit code"], data["stderr"] || "");
            }
        }
    }

    Component {
        id: notificationComponent

        Notification {
            id: notification
            property string actionUrl

            // Generic Plasma event, so the widget needs no .notifyrc of its own.
            componentName: "plasma_workspace"
            eventId: "notification"
            autoDelete: true
            actions: [
                NotificationAction {
                    onActivated: Qt.openUrlExternally(notification.actionUrl)
                }
            ]
        }
    }

    // Right-click menu: scenes (current one checked) and following the mouse pointer, then
    // the audio mixer and quit entries.
    function updateContextualActions() {
        const actions = [];
        if (sceneActions.count > 0) {
            actions.push(sceneHeader);
            for (let i = 0; i < sceneActions.count; i++) {
                actions.push(sceneActions.objectAt(i));
            }
            actions.push(followAction, sceneSeparator);
        }
        if (obs.connected) {
            actions.push(mixerAction, quitAction, mixerSeparator);
        }
        Plasmoid.contextualActions = actions;
    }

    PlasmaCore.Action {
        id: mixerAction
        text: i18n("Audio Mixer…")
        icon.name: "audio-volume-high"
        onTriggered: mixerOpenTimer.restart()
    }

    // Opening the popup while the context menu is still closing loses the race for focus:
    // the menu's window deactivation hides the popup again right away. Wait for the menu to go.
    Timer {
        id: mixerOpenTimer
        interval: 200
        onTriggered: root.expanded = true
    }

    PlasmaCore.Action {
        id: quitAction
        text: root.quittingObs ? i18n("Quitting OBS…")
            : obs.recording ? i18n("Stop Recording and Quit OBS") : i18n("Quit OBS")
        icon.name: "application-exit"
        enabled: !root.quittingObs
        onTriggered: root.quitObs()
    }

    PlasmaCore.Action {
        id: mixerSeparator
        isSeparator: true
    }

    PlasmaCore.Action {
        id: sceneHeader
        isSeparator: true
        text: i18n("Scene")
    }

    // Without any screen assigned there is nothing to follow; the entry opens the settings then.
    PlasmaCore.Action {
        id: followAction
        text: follower.hasScenes ? i18n("Scene Follows Mouse Pointer") : i18n("Scene Follows Mouse Pointer…")
        icon.name: "input-mouse"
        checkable: follower.hasScenes
        checked: root.followingMouse
        onTriggered: {
            checked = Qt.binding(() => root.followingMouse);
            if (follower.hasScenes) {
                root.setFollowMouse(!Plasmoid.configuration.followMouse);
            } else {
                Plasmoid.internalAction("configure").trigger();
            }
        }
    }

    PlasmaCore.Action {
        id: sceneSeparator
        isSeparator: true
    }

    Instantiator {
        id: sceneActions
        model: obs.scenes

        delegate: PlasmaCore.Action {
            required property string modelData
            text: modelData
            checkable: true
            checked: modelData === obs.currentScene
            onTriggered: {
                // Triggering flips checked and breaks the binding; OBS confirms the switch by event.
                checked = Qt.binding(() => modelData === obs.currentScene);
                root.stopFollowingMouse();
                obs.setScene(modelData);
            }
        }

        onObjectAdded: Qt.callLater(root.updateContextualActions)
        onObjectRemoved: Qt.callLater(root.updateContextualActions)
    }

    compactRepresentation: MouseArea {
        id: compact

        Layout.minimumWidth: root.vertical ? -1 : row.implicitWidth
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: root.vertical ? row.implicitHeight : -1

        // Holding the button discards a running recording, or starts OBS when it is not
        // reachable. A ring around the dot shows the progress; it appears after a short delay
        // so normal clicks do not flash it. Once it is visible, releasing cancels and does
        // not count as a click.
        readonly property int holdDelay: 300
        property real holdProgress: 0
        property bool suppressClick: false
        // "discard" | "launch", decided on press
        property string holdAction: ""

        Timer {
            id: holdDelayTimer
            interval: compact.holdDelay
            onTriggered: holdAnimation.start()
        }

        NumberAnimation {
            id: holdAnimation
            target: compact
            property: "holdProgress"
            from: 0
            to: 1
            duration: Math.max((compact.holdAction === "launch" ? Plasmoid.configuration.launchHoldDurationMs
                                                                   : Plasmoid.configuration.holdDurationMs) - compact.holdDelay, 100)
            onFinished: {
                compact.suppressClick = true;
                compact.holdProgress = 0;
                if (compact.holdAction === "discard") {
                    obs.discardRecording();
                } else if (compact.holdAction === "launch") {
                    root.launchObs();
                }
            }
        }

        function beginHold() {
            if (obs.connected && obs.recording) {
                holdAction = "discard";
            } else if (!obs.connected && !obs.connectionState.startsWith("auth") && !root.launchingObs) {
                holdAction = "launch";
            } else {
                return;
            }
            holdDelayTimer.restart();
        }

        function endHold() {
            holdDelayTimer.stop();
            if (holdAnimation.running) {
                holdAnimation.stop();
                suppressClick = true;
            }
            holdProgress = 0;
        }

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPressed: mouse => {
            suppressClick = false;
            if (mouse.button === Qt.LeftButton) {
                beginHold();
            }
        }
        onReleased: endHold()
        onWheel: wheel => root.handleWheel(wheel.angleDelta, wheel.inverted)
        onCanceled: endHold()
        onClicked: mouse => {
            if (suppressClick) {
                suppressClick = false;
            } else if (mouse.button === Qt.MiddleButton) {
                obs.toggleRecordPause();
            } else {
                root.handleClick();
            }
        }
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton && !suppressClick) {
                root.handleDoubleClick();
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: root.toolTipMainText
        Accessible.description: root.toolTipSubText

        Shape {
            id: holdRing
            readonly property real size: dot.width + Kirigami.Units.smallSpacing * 2

            x: row.x + dot.x + (dot.width - size) / 2
            y: row.y + dot.y + (dot.height - size) / 2
            width: size
            height: size
            visible: compact.holdProgress > 0
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: compact.holdAction === "launch" ? Kirigami.Theme.positiveTextColor
                                                             : Kirigami.Theme.negativeTextColor
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: holdRing.size / 2
                    centerY: holdRing.size / 2
                    radiusX: holdRing.size / 2 - 1
                    radiusY: holdRing.size / 2 - 1
                    startAngle: -90
                    sweepAngle: 360 * compact.holdProgress
                }
            }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 0

            Rectangle {
                id: dot
                readonly property bool active: obs.connected && obs.recording

                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 0.8)
                implicitHeight: implicitWidth
                radius: width / 2

                // Connection state without the short "connecting" phase of each retry,
                // so the dot does not fade back and forth every few seconds.
                property string shownState: "offline"
                Binding on shownState {
                    value: obs.connectionState
                    when: obs.connectionState !== "connecting"
                    restoreMode: Binding.RestoreNone
                }

                // "offline" | "ready" | "recording" | "paused" | "auth"; the first three are configurable.
                readonly property string mode: active ? (obs.paused ? "paused" : "recording")
                                             : shownState.startsWith("auth") ? "auth"
                                             : shownState === "connected" ? "ready"
                                             : "offline"
                readonly property var cfg: Plasmoid.configuration
                readonly property color offlineColor: cfg.offlineColor || Kirigami.Theme.textColor
                readonly property color readyColor: cfg.readyColor || Kirigami.Theme.textColor
                readonly property color recordingColor: cfg.recordingColor || Kirigami.Theme.negativeTextColor

                color: mode === "recording" ? recordingColor
                     : mode === "paused" ? Kirigami.Theme.neutralTextColor
                     : Qt.alpha(recordingColor, 0) // fades in as recording color, not via black
                border.width: active ? 0 : Math.max(1, Math.round(implicitWidth / 8))
                border.color: mode === "auth" ? Kirigami.Theme.negativeTextColor
                            : mode === "ready" ? readyColor
                            : offlineColor
                property real pulse: 1
                // Separate from opacity so the fade below does not smear the pulse animation.
                property real baseOpacity: (mode === "offline" ? cfg.offlineOpacity
                                            : mode === "ready" ? cfg.readyOpacity
                                            : mode === "recording" ? cfg.recordingOpacity
                                            : 100) / 100
                opacity: pulse * baseOpacity

                // Fade between states instead of switching abruptly. veryLongDuration follows
                // the Plasma animation speed setting and is 0 when animations are disabled.
                Behavior on color { ColorAnimation { duration: Kirigami.Units.veryLongDuration } }
                Behavior on border.color { ColorAnimation { duration: Kirigami.Units.veryLongDuration } }
                Behavior on baseOpacity { NumberAnimation { duration: Kirigami.Units.veryLongDuration } }

                SequentialAnimation on pulse {
                    running: (dot.active && !obs.paused) || root.launchingObs
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutQuad }
                }
            }

            // The duration slides open instead of popping in: the clip grows from zero
            // width while the label fades in, so the panel moves the dot along smoothly.
            Item {
                id: labelClip
                readonly property bool shown: dot.active && !root.vertical && Plasmoid.configuration.showDuration

                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: shown ? label.implicitWidth + Kirigami.Units.smallSpacing : 0
                implicitHeight: label.implicitHeight
                clip: true

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutQuad }
                }

                PlasmaComponents3.Label {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: labelClip.shown ? 1 : 0
                    font.features: ({ "tnum": 1 })

                    Behavior on opacity {
                        NumberAnimation { duration: Kirigami.Units.veryLongDuration }
                    }

                    // Keep the last duration while collapsing; it is reset to 0 on stop.
                    Binding on text {
                        value: root.durationText
                        when: labelClip.shown
                        restoreMode: Binding.RestoreNone
                    }
                }
            }
        }
    }
}
