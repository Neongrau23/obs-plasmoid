import QtQuick
import QtWebSockets

import "sha256.js" as Sha

// obs-websocket v5 client: connects, authenticates, tracks the recording state, the
// scenes and the audio inputs, and reconnects on its own whenever OBS is not reachable.
Item {
    id: client

    property string host: "localhost"
    property int port: 4455
    property string password: ""
    property int retryInterval: 3000
    property int authRetryInterval: 15000

    // "offline" | "connecting" | "authRequired" | "authFailed" | "connected"
    readonly property string connectionState: d.state
    readonly property bool connected: d.state === "connected"
    readonly property bool recording: d.recording
    readonly property bool paused: d.paused
    readonly property int durationMs: d.durationMs
    readonly property string lastError: d.lastError
    // Scene names in the order the OBS scene list shows them, top to bottom.
    readonly property var scenes: d.scenes
    readonly property string currentScene: d.currentScene
    // Inputs with audio, in OBS input list order. Roles: name, volumeMul (0..1+), muted.
    readonly property ListModel audioInputs: inputsModel

    // Emitted when a recording has been stopped and written to disk.
    signal recordingSaved(string path)
    // Instead of recordingSaved when the recording was stopped by discardRecording().
    // Removing the file is up to the receiver: OBS cannot delete files.
    signal recordingDiscarded(string path)
    signal sceneRenamed(string oldName, string newName)

    function toggleRecord() {
        if (connected) {
            d.lastError = "";
            d.request("ToggleRecord");
        }
    }

    function discardRecording() {
        if (connected && recording) {
            d.lastError = "";
            d.discardPending = true;
            d.request("StopRecord");
        }
    }

    function stopRecording() {
        if (connected && recording) {
            d.lastError = "";
            d.request("StopRecord");
        }
    }

    function toggleRecordPause() {
        if (connected && recording) {
            d.lastError = "";
            d.request("ToggleRecordPause");
        }
    }

    function setScene(name) {
        if (connected) {
            d.lastError = "";
            d.request("SetCurrentProgramScene", { sceneName: name });
        }
    }

    // True from a switchScene() request until OBS reports the scene transition finished,
    // and while a transition started elsewhere (e.g. in OBS itself) is running.
    readonly property bool sceneSwitchBusy: d.switchLocked || d.transitioning

    // Like setScene(), but ignored while sceneSwitchBusy: a new switch request during a
    // transition makes OBS cut it short. For rapid input such as mouse wheel notches.
    // Returns whether the switch was requested.
    function switchScene(name) {
        if (!connected || sceneSwitchBusy || name === currentScene) {
            return false;
        }
        d.lastError = "";
        d.switchLocked = true;
        // Safety net in case the end of the transition is never reported.
        switchFallback.interval = Math.max(d.transitionDuration, 0) + 1000;
        switchFallback.restart();
        d.request("SetCurrentProgramScene", { sceneName: name }, (ok, data) => {
            if (!ok) {
                d.switchLocked = false;
            }
        });
        return true;
    }

    function setInputVolume(name, volumeMul) {
        if (connected) {
            d.lastError = "";
            d.request("SetInputVolume", { inputName: name, inputVolumeMul: volumeMul });
        }
    }

    function setInputMuted(name, muted) {
        if (connected) {
            d.lastError = "";
            d.request("SetInputMute", { inputName: name, inputMuted: muted });
        }
    }

    function reconnect() {
        socket.active = false;
        d.reset("connecting");
        socket.url = "ws://" + host + ":" + port;
        socket.active = true;
    }

    onHostChanged: Qt.callLater(reconnect)
    onPortChanged: Qt.callLater(reconnect)
    onPasswordChanged: Qt.callLater(reconnect)
    Component.onCompleted: reconnect()

    QtObject {
        id: d

        // Event subscriptions: General (1 << 0) for ExitStarted, Scenes (1 << 2),
        // Inputs (1 << 3) for mute/volume, Transitions (1 << 4) for scene transition
        // start/end and duration, Outputs (1 << 6) for RecordStateChanged.
        readonly property int eventSubscriptions: (1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 6)

        property string state: "offline"
        property bool recording: false
        property bool paused: false
        property int durationMs: 0
        property string lastError: ""
        property var scenes: []
        property string currentScene: ""
        property bool identifySent: false
        property int nextRequestId: 1
        // requestId -> function(ok, responseData) for requests that handle their own result.
        property var callbacks: ({})
        property int inputsGeneration: 0
        property bool discardPending: false
        property bool switchLocked: false
        property bool transitioning: false
        // Duration of the current scene transition in ms, -1 for fixed ones (e.g. stinger).
        property int transitionDuration: -1

        function reset(newState) {
            state = newState;
            recording = false;
            paused = false;
            durationMs = 0;
            scenes = [];
            currentScene = "";
            inputsModel.clear();
            inputsGeneration++;
            callbacks = {};
            discardPending = false;
            switchLocked = false;
            transitioning = false;
            transitionDuration = -1;
            identifySent = false;
        }

        function send(op, data) {
            socket.sendTextMessage(JSON.stringify({ op: op, d: data }));
        }

        function request(type, data, callback) {
            const id = String(nextRequestId++);
            if (callback) {
                callbacks[id] = callback;
            }
            send(6, { requestType: type, requestId: id, requestData: data || {} });
        }

        function requestTransition() {
            request("GetCurrentSceneTransition", {}, (ok, data) => {
                if (ok) {
                    transitionDuration = data.transitionDuration === null ? -1 : data.transitionDuration;
                }
            });
        }

        function inputRow(name) {
            for (let i = 0; i < inputsModel.count; i++) {
                if (inputsModel.get(i).name === name) {
                    return i;
                }
            }
            return -1;
        }

        // OBS has no "audio inputs" request: ask every input for volume and mute state
        // and keep those that answer both. Fills the model in one go once all replies are in.
        function refreshInputs() {
            const generation = ++inputsGeneration;
            request("GetInputList", {}, (ok, data) => {
                if (!ok || generation !== inputsGeneration) {
                    return;
                }
                const found = data.inputs.map(input => ({ name: input.inputName }));
                let open = found.length * 2;
                const done = () => {
                    if (--open === 0 && generation === inputsGeneration) {
                        inputsModel.clear();
                        found.filter(row => row.volumeMul !== undefined && row.muted !== undefined)
                             .forEach(row => inputsModel.append(row));
                    }
                };
                if (open === 0) {
                    inputsModel.clear();
                }
                found.forEach(row => {
                    request("GetInputVolume", { inputName: row.name }, (ok, v) => {
                        if (ok) row.volumeMul = v.inputVolumeMul;
                        done();
                    });
                    request("GetInputMute", { inputName: row.name }, (ok, m) => {
                        if (ok) row.muted = m.inputMuted;
                        done();
                    });
                });
            });
        }

        function onHello(data) {
            const identify = { rpcVersion: 1, eventSubscriptions: eventSubscriptions };
            if (data.authentication) {
                if (client.password === "") {
                    reset("authRequired");
                    socket.active = false;
                    return;
                }
                identify.authentication = Sha.obsAuth(client.password,
                                                      data.authentication.salt,
                                                      data.authentication.challenge);
            }
            identifySent = true;
            send(1, identify);
        }

        function onEvent(data) {
            if (data.eventType === "RecordStateChanged") {
                const s = data.eventData.outputState;
                recording = data.eventData.outputActive;
                paused = s === "OBS_WEBSOCKET_OUTPUT_PAUSED";
                if (s === "OBS_WEBSOCKET_OUTPUT_STARTED" || s === "OBS_WEBSOCKET_OUTPUT_STOPPED") {
                    durationMs = 0;
                }
                if (s === "OBS_WEBSOCKET_OUTPUT_STOPPED" && data.eventData.outputPath) {
                    // The file is complete only now, not yet when StopRecord returns.
                    if (discardPending) {
                        client.recordingDiscarded(data.eventData.outputPath);
                    } else {
                        client.recordingSaved(data.eventData.outputPath);
                    }
                }
                if (s === "OBS_WEBSOCKET_OUTPUT_STOPPED") {
                    discardPending = false;
                }
                request("GetRecordStatus");
            } else if (data.eventType === "InputVolumeChanged" || data.eventType === "InputMuteStateChanged") {
                const row = inputRow(data.eventData.inputName);
                if (row >= 0 && data.eventType === "InputVolumeChanged") {
                    inputsModel.setProperty(row, "volumeMul", data.eventData.inputVolumeMul);
                } else if (row >= 0) {
                    inputsModel.setProperty(row, "muted", data.eventData.inputMuted);
                }
            } else if (["InputCreated", "InputRemoved", "InputNameChanged"].includes(data.eventType)) {
                refreshInputs();
            } else if (data.eventType === "SceneTransitionStarted") {
                transitioning = true;
                // OBS sends no end event when a transition is interrupted.
                switchFallback.interval = Math.max(transitionDuration, 0) + 1000;
                switchFallback.restart();
            } else if (data.eventType === "SceneTransitionEnded") {
                transitioning = false;
                switchLocked = false;
                switchFallback.stop();
            } else if (data.eventType === "CurrentSceneTransitionDurationChanged") {
                transitionDuration = data.eventData.transitionDuration;
            } else if (data.eventType === "CurrentSceneTransitionChanged") {
                requestTransition();
            } else if (data.eventType === "CurrentProgramSceneChanged") {
                currentScene = data.eventData.sceneName;
            } else if (["SceneListChanged", "SceneCreated", "SceneRemoved", "SceneNameChanged"].includes(data.eventType)) {
                if (data.eventType === "SceneNameChanged") {
                    client.sceneRenamed(data.eventData.oldSceneName, data.eventData.sceneName);
                }
                request("GetSceneList");
            } else if (data.eventType === "ExitStarted") {
                // OBS is shutting down; drop the connection now instead of waiting for the socket to die.
                socket.active = false;
                reset("offline");
            }
        }

        function onResponse(data) {
            const callback = callbacks[data.requestId];
            if (callback) {
                delete callbacks[data.requestId];
                callback(data.requestStatus.result, data.responseData);
                return;
            }
            if (!data.requestStatus.result) {
                lastError = data.requestStatus.comment || ("Fehler " + data.requestStatus.code);
                return;
            }
            if (data.requestType === "GetRecordStatus") {
                recording = data.responseData.outputActive;
                paused = data.responseData.outputPaused;
                durationMs = recording ? data.responseData.outputDuration : 0;
            } else if (data.requestType === "GetSceneList") {
                // OBS counts sceneIndex from the bottom of its scene list.
                scenes = data.responseData.scenes
                    .slice()
                    .sort((a, b) => b.sceneIndex - a.sceneIndex)
                    .map(scene => scene.sceneName);
                currentScene = data.responseData.currentProgramSceneName;
            }
        }

        function onMessage(message) {
            let msg;
            try {
                msg = JSON.parse(message);
            } catch (e) {
                return;
            }
            switch (msg.op) {
            case 0: onHello(msg.d); break;
            case 2:
                state = "connected";
                request("GetRecordStatus");
                request("GetSceneList");
                requestTransition();
                refreshInputs();
                break;
            case 5: onEvent(msg.d); break;
            case 7: onResponse(msg.d); break;
            }
        }
    }

    ListModel {
        id: inputsModel
    }

    Timer {
        id: switchFallback
        onTriggered: {
            d.switchLocked = false;
            d.transitioning = false;
        }
    }

    WebSocket {
        id: socket
        active: false

        onTextMessageReceived: message => d.onMessage(message)
        onStatusChanged: newStatus => {
            if (newStatus !== WebSocket.Closed && newStatus !== WebSocket.Error) {
                return;
            }
            // QML's WebSocket does not expose the close code. A close right after
            // Identify and before Identified means OBS rejected the password (4009).
            if (d.identifySent && d.state !== "connected") {
                d.reset("authFailed");
            } else if (d.state !== "authRequired") {
                d.reset("offline");
            }
        }
    }

    Timer {
        id: retryTimer
        interval: d.state === "authFailed" || d.state === "authRequired" ? client.authRetryInterval : client.retryInterval
        repeat: true
        running: d.state !== "connected" && (socket.status === WebSocket.Closed || socket.status === WebSocket.Error || !socket.active)
        onTriggered: client.reconnect()
    }

    Timer {
        interval: 1000
        repeat: true
        running: d.state === "connected" && d.recording
        onTriggered: d.request("GetRecordStatus")
    }
}
