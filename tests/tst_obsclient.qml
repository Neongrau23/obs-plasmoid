import QtQuick
import QtTest
import QtWebSockets

import "../package/contents/ui"

// Runs against tests/mock-obs.py (port 14455, password "testpass"); see run-tests.sh.
TestCase {
    name: "ObsClient"

    ObsClient {
        id: obs
        host: "127.0.0.1"
        port: 14455
        password: "wrong"
        retryInterval: 300
        authRetryInterval: 600
    }

    SignalSpy {
        id: savedSpy
        target: obs
        signalName: "recordingSaved"
    }

    SignalSpy {
        id: discardedSpy
        target: obs
        signalName: "recordingDiscarded"
    }

    SignalSpy {
        id: renamedSpy
        target: obs
        signalName: "sceneRenamed"
    }

    ScreenFollower {
        id: follower
        client: obs
        scenesJson: JSON.stringify({ top: "Gameplay", main: "Kamera", left: "Pause" })
    }

    SignalSpy {
        id: otherChangeSpy
        target: follower
        signalName: "otherSceneChange"
    }

    WebSocket {
        id: control
        url: "ws://127.0.0.1:14455/control"
    }

    function test_1_wrongPasswordIsReported() {
        tryCompare(obs, "connectionState", "authFailed", 5000);
    }

    function test_2_connectsWithCorrectPassword() {
        obs.password = "testpass";
        tryCompare(obs, "connectionState", "connected", 5000);
        compare(obs.recording, false);
    }

    function test_3_togglesRecordingAndTracksDuration() {
        savedSpy.clear();
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        tryVerify(() => obs.durationMs >= 1500, 5000);
        obs.toggleRecord();
        tryCompare(obs, "recording", false, 3000);
        compare(obs.durationMs, 0);
        compare(savedSpy.count, 1);
        compare(savedSpy.signalArguments[0][0], "/videos/mock-recording.mkv");
    }

    function test_3a_discardsRecording() {
        savedSpy.clear();
        discardedSpy.clear();
        obs.discardRecording();
        wait(300);
        compare(discardedSpy.count, 0, "nothing to discard while not recording");

        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        obs.discardRecording();
        tryCompare(obs, "recording", false, 3000);
        tryCompare(discardedSpy, "count", 1, 3000);
        compare(JSON.stringify(discardedSpy.signalArguments[0][0]), JSON.stringify(["/videos/mock-recording.mkv"]));
        compare(savedSpy.count, 0, "a discarded recording is not reported as saved");

        // The next normal stop is a save again.
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        obs.toggleRecord();
        tryCompare(savedSpy, "count", 1, 3000);
        compare(discardedSpy.count, 1);
    }

    // With automatic file splitting in OBS, discarding removes every part, not just the last.
    function test_3a3_discardsEverySplitFile() {
        savedSpy.clear();
        discardedSpy.clear();
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        mockCommand({ cmd: "splitFile" });
        mockCommand({ cmd: "splitFile" });
        obs.discardRecording();
        tryCompare(discardedSpy, "count", 1, 3000);
        compare(JSON.stringify(discardedSpy.signalArguments[0][0]),
                JSON.stringify(["/videos/mock-recording.mkv", "/videos/mock-recording-2.mkv",
                                "/videos/mock-recording-3.mkv"]));

        // A saved split recording still reports its last file, and the next one starts fresh.
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        mockCommand({ cmd: "splitFile" });
        obs.toggleRecord();
        tryCompare(savedSpy, "count", 1, 3000);
        compare(savedSpy.signalArguments[0][0], "/videos/mock-recording-2.mkv");
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        obs.discardRecording();
        tryCompare(discardedSpy, "count", 2, 3000);
        compare(JSON.stringify(discardedSpy.signalArguments[1][0]), JSON.stringify(["/videos/mock-recording.mkv"]));
    }

    function test_3a2_failedDiscardKeepsNextRecording() {
        savedSpy.clear();
        discardedSpy.clear();
        control.active = true;
        tryCompare(control, "status", WebSocket.Open, 3000);
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);

        control.sendTextMessage(JSON.stringify({ cmd: "failNext", request: "StopRecord" }));
        wait(200);
        obs.discardRecording();
        tryVerify(() => obs.lastError !== "", 3000);
        verify(obs.recording, "the failed stop leaves the recording running");

        obs.toggleRecord();
        tryCompare(obs, "recording", false, 3000);
        tryCompare(savedSpy, "count", 1, 3000);
        compare(discardedSpy.count, 0, "the failed discard does not hit the next recording");
    }

    function test_3b_pausesAndResumes() {
        obs.toggleRecordPause();
        wait(300);
        verify(!obs.paused, "pause is ignored while not recording");

        obs.toggleRecord();
        tryVerify(() => obs.durationMs >= 500, 3000);
        obs.toggleRecordPause();
        tryCompare(obs, "paused", true, 3000);
        wait(1100); // let the status poll pick up the frozen duration
        const frozen = obs.durationMs;
        wait(1500);
        verify(obs.durationMs - frozen < 300, "duration stands still while paused");

        obs.toggleRecordPause();
        tryCompare(obs, "paused", false, 3000);
        verify(obs.recording);
        tryVerify(() => obs.durationMs >= frozen + 1000, 4000);

        obs.toggleRecord();
        tryCompare(obs, "recording", false, 3000);
    }

    function test_3c_listsAndSwitchesScenes() {
        compare(obs.scenes, ["Gameplay", "Kamera", "Pause-Bildschirm"]);
        compare(obs.currentScene, "Gameplay");
        obs.setScene("Kamera");
        tryCompare(obs, "currentScene", "Kamera", 3000);
        obs.setScene("Gibt es nicht");
        tryVerify(() => obs.lastError !== "", 3000);
        compare(obs.currentScene, "Kamera");
    }

    function test_3d_waitsForSceneTransition() {
        // Mock transition: 300 ms. Notches of one wheel flick arrive within milliseconds.
        verify(obs.switchScene("Gameplay"));
        verify(obs.sceneSwitchBusy);
        verify(!obs.switchScene("Kamera"), "ignored while the transition runs");
        verify(!obs.switchScene("Kamera"));
        tryCompare(obs, "currentScene", "Gameplay", 3000);
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
        verify(!obs.switchScene("Gameplay"), "already the current scene");
        verify(obs.switchScene("Kamera"), "accepted again after the transition");
        tryCompare(obs, "currentScene", "Kamera", 3000);
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
    }

    function test_3d2_waitsForFixedTransition() {
        // A stinger reports no duration; the lock must outlast it instead of falling back after 1 s.
        control.active = true;
        tryCompare(control, "status", WebSocket.Open, 3000);
        control.sendTextMessage(JSON.stringify({ cmd: "setTransition", fixed: true, ms: 2000 }));
        wait(300);
        verify(obs.switchScene("Gameplay"));
        wait(1500);
        verify(obs.sceneSwitchBusy, "still locked while the stinger runs");
        verify(!obs.switchScene("Kamera"));
        tryCompare(obs, "sceneSwitchBusy", false, 3000);

        control.sendTextMessage(JSON.stringify({ cmd: "setTransition", fixed: false, ms: 300 }));
        wait(300);
        verify(obs.switchScene("Kamera"));
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
    }

    function test_3e_reportsRenamedScenes() {
        control.active = true;
        tryCompare(control, "status", WebSocket.Open, 3000);
        control.sendTextMessage(JSON.stringify({ cmd: "renameScene", from: "Pause-Bildschirm", to: "Pause" }));
        tryCompare(renamedSpy, "count", 1, 3000);
        compare(renamedSpy.signalArguments[0][0], "Pause-Bildschirm");
        compare(renamedSpy.signalArguments[0][1], "Pause");
        tryVerify(() => obs.scenes.join() === "Gameplay,Kamera,Pause", 3000);
    }

    function test_3f_followsThePointerAcrossScreens() {
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
        compare(obs.currentScene, "Kamera");
        otherChangeSpy.clear();
        follower.reset();
        follower.delayMs = 0;

        // Pointer from the top screen across the main one to the left one, faster than
        // OBS reports the first switch and its transition (mock: 300 ms).
        follower.pointerOn("top", 0);
        follower.pointerOn("main", 100);
        follower.pointerOn("left", 200);
        tryCompare(obs, "currentScene", "Gameplay", 3000);
        compare(otherChangeSpy.count, 0, "own switch counts as own");

        // After the transition the next poll catches up with the pointer.
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
        follower.pointerOn("left", 700);
        tryCompare(obs, "currentScene", "Pause", 3000);
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
        compare(otherChangeSpy.count, 0);

        // Screens without a scene switch nothing.
        follower.pointerOn("elsewhere", 800);
        verify(!obs.sceneSwitchBusy);

        // A switch made elsewhere is reported.
        obs.setScene("Kamera");
        tryCompare(otherChangeSpy, "count", 1, 3000);
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
    }

    // Mouse wheel with following switched on: its own switch must not turn following off.
    function test_3g_wheelSwitchStartsFollowing() {
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
        compare(obs.currentScene, "Kamera");
        otherChangeSpy.clear();
        verify(follower.switchAndFollow("Pause"));
        tryCompare(obs, "currentScene", "Pause", 3000);
        compare(otherChangeSpy.count, 0, "wheel switch counts as own");
        tryCompare(obs, "sceneSwitchBusy", false, 3000);

        // During a transition the switch is refused, as with switchScene().
        verify(follower.switchAndFollow("Kamera"));
        verify(!follower.switchAndFollow("Gameplay"));
        tryCompare(obs, "currentScene", "Kamera", 3000);
        tryCompare(obs, "sceneSwitchBusy", false, 3000);
        compare(otherChangeSpy.count, 0);
    }

    SignalSpy {
        id: replaySavedSpy
        target: obs
        signalName: "replaySaved"
    }

    SignalSpy {
        id: unavailableSpy
        target: obs
        signalName: "replayBufferUnavailable"
    }

    property var lastControlReply: null

    Connections {
        target: control
        function onTextMessageReceived(message) {
            lastControlReply = JSON.parse(message);
        }
    }

    // Sends a command to the mock; the pause keeps it ahead of the client's next request.
    function mockCommand(cmd) {
        openControl();
        control.sendTextMessage(JSON.stringify(cmd));
        wait(100);
    }

    // A mock restart closes the control connection, and setting active to true again does
    // nothing while it already is.
    function openControl() {
        if (control.status !== WebSocket.Open) {
            control.active = false;
            control.active = true;
        }
        tryCompare(control, "status", WebSocket.Open, 3000);
    }

    function reconnectObs() {
        obs.reconnect();
        tryCompare(obs, "connectionState", "connected", 3000);
    }

    // The mock's OBS profile as {"Category/Name": value}.
    function mockProfile() {
        lastControlReply = null;
        mockCommand({ cmd: "getProfile" });
        tryVerify(() => lastControlReply !== null, 3000);
        return lastControlReply.profile;
    }

    function cleanupReplay() {
        obs.replayAutoStart = false;
        obs.replayLengthSeconds = 0;
        if (obs.replayBufferActive) {
            obs.toggleReplayBuffer();
            tryCompare(obs, "replayBufferActive", false, 3000);
        }
    }

    function test_3h_startsStopsAndSavesReplayBuffer() {
        replaySavedSpy.clear();
        mockCommand({ cmd: "setReplay", enabled: true });
        reconnectObs();
        tryCompare(obs, "replayBufferAvailable", true, 3000);
        compare(obs.replayBufferActive, false, "no autostart by default");

        obs.toggleReplayBuffer();
        tryCompare(obs, "replayBufferActive", true, 3000);
        obs.saveReplayBuffer();
        tryCompare(replaySavedSpy, "count", 1, 3000);
        compare(replaySavedSpy.signalArguments[0][0], "/videos/mock-replay.mkv");

        // Saved with the OBS hotkey instead of the widget.
        mockCommand({ cmd: "saveReplay" });
        tryCompare(replaySavedSpy, "count", 2, 3000);

        obs.toggleReplayBuffer();
        tryCompare(obs, "replayBufferActive", false, 3000);
        compare(obs.lastError, "");
        cleanupReplay();
    }

    function test_3i_autoStartsReplayBufferOnConnect() {
        obs.replayAutoStart = true;
        reconnectObs();
        tryCompare(obs, "replayBufferActive", true, 3000);

        // OBS restarts: the buffer is gone with it and starts again on the new connection.
        mockCommand({ cmd: "restart", downMs: 800 });
        tryVerify(() => obs.connectionState !== "connected", 3000);
        compare(obs.replayBufferActive, false);
        compare(obs.replayBufferAvailable, false);
        tryCompare(obs, "connectionState", "connected", 8000);
        tryCompare(obs, "replayBufferActive", true, 3000);
        cleanupReplay();
        openControl();
    }

    function test_3j_reportsDisabledReplayBuffer() {
        unavailableSpy.clear();
        mockCommand({ cmd: "setReplay", enabled: false });
        obs.replayAutoStart = true;
        reconnectObs();
        tryCompare(unavailableSpy, "count", 1, 3000);
        compare(obs.replayBufferAvailable, false);
        compare(obs.lastError, "", "a disabled buffer is not a widget error");

        obs.toggleReplayBuffer();
        tryCompare(unavailableSpy, "count", 2, 3000);

        // Meanwhile the user enables the buffer in OBS; OBS sends no event for that.
        mockCommand({ cmd: "setReplay", enabled: true });
        obs.toggleReplayBuffer();
        tryCompare(obs, "replayBufferActive", true, 3000);
        compare(obs.replayBufferAvailable, true);
        compare(unavailableSpy.count, 2);
        cleanupReplay();
    }

    function test_3k_writesReplayLengthForOutputMode() {
        // Off: the OBS profile stays untouched.
        reconnectObs();
        compare(mockProfile()["AdvOut/RecRBTime"], "20");

        // Advanced output mode.
        obs.replayLengthSeconds = 45;
        reconnectObs();
        tryVerify(() => mockProfile()["AdvOut/RecRBTime"] === "45", 3000);
        compare(mockProfile()["SimpleOutput/RecRBTime"], "20");

        // Fresh profile without a stored mode means simple mode; a change while the buffer
        // runs is written but does not restart it.
        mockCommand({ cmd: "setProfile", category: "Output", name: "Mode", value: null });
        reconnectObs();
        obs.toggleReplayBuffer();
        tryCompare(obs, "replayBufferActive", true, 3000);
        obs.replayLengthSeconds = 90;
        tryVerify(() => mockProfile()["SimpleOutput/RecRBTime"] === "90", 3000);
        verify(obs.replayBufferActive, "the running buffer keeps running");
        compare(obs.lastError, "");

        cleanupReplay();
        mockCommand({ cmd: "setProfile", category: "Output", name: "Mode", value: "Advanced" });
    }

    // While OBS is still loading, obs-websocket answers 207 instead of the real state.
    function test_3l_retriesReplaySetupWhileObsIsLoading() {
        unavailableSpy.clear();
        mockCommand({ cmd: "setReplay", enabled: true });
        obs.replayAutoStart = true;
        obs.replayLengthSeconds = 50;
        mockCommand({ cmd: "failNext", request: "GetProfileParameter", code: 207 });
        mockCommand({ cmd: "failNext", request: "GetReplayBufferStatus", code: 207 });
        reconnectObs();
        tryCompare(obs, "replayBufferActive", true, 5000);
        compare(unavailableSpy.count, 0, "loading is not reported as turned off");
        compare(obs.lastError, "");
        compare(mockProfile()["AdvOut/RecRBTime"], "50");
        cleanupReplay();
    }

    // Quitting OBS waits for the replay buffer to stop: OBS asks before quitting while it runs.
    function test_3m_stopsReplayBuffer() {
        obs.stopReplayBuffer();
        compare(obs.lastError, "", "stopping an inactive buffer does nothing");
        obs.toggleReplayBuffer();
        tryCompare(obs, "replayBufferActive", true, 3000);
        obs.stopReplayBuffer();
        tryCompare(obs, "replayBufferActive", false, 3000);
        compare(obs.lastError, "");
    }

    function inputs() {
        const rows = [];
        for (let i = 0; i < obs.audioInputs.count; i++) {
            const row = obs.audioInputs.get(i);
            rows.push(row.name + ":" + row.volumeMul + ":" + row.muted);
        }
        return rows.join(" ");
    }

    function test_3d_listsAndControlsAudioInputs() {
        // "Bildschirm" has no audio and is left out.
        tryCompare(obs.audioInputs, "count", 2, 3000);
        compare(inputs(), "Desktop-Audio:1:false Mikrofon:0.5:false");

        obs.setInputMuted("Mikrofon", true);
        tryVerify(() => inputs() === "Desktop-Audio:1:false Mikrofon:0.5:true", 3000);
        obs.setInputVolume("Desktop-Audio", 0.25);
        tryVerify(() => inputs() === "Desktop-Audio:0.25:false Mikrofon:0.5:true", 3000);
        compare(obs.lastError, "", "own requests do not report errors");

        control.active = true;
        tryCompare(control, "status", WebSocket.Open, 3000);
        control.sendTextMessage(JSON.stringify({ cmd: "addInput", name: "Gast" }));
        tryCompare(obs.audioInputs, "count", 3, 3000);
        compare(obs.audioInputs.get(2).name, "Gast");
    }

    function test_4_reconnectsAfterObsRestart() {
        control.active = true;
        tryCompare(control, "status", WebSocket.Open, 3000);
        control.sendTextMessage(JSON.stringify({ cmd: "restart", downMs: 1500 }));
        tryVerify(() => obs.connectionState !== "connected", 3000);
        wait(800);
        verify(obs.connectionState !== "connected", "still down while OBS is gone");
        compare(obs.scenes.length, 0);
        compare(obs.audioInputs.count, 0);
        tryCompare(obs, "connectionState", "connected", 8000);
        tryVerify(() => obs.scenes.length === 3, 3000);
    }

    function test_5_missingPasswordIsReported() {
        obs.password = "";
        tryCompare(obs, "connectionState", "authRequired", 3000);
    }
}
