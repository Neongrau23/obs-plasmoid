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
        compare(discardedSpy.signalArguments[0][0], "/videos/mock-recording.mkv");
        compare(savedSpy.count, 0, "a discarded recording is not reported as saved");

        // The next normal stop is a save again.
        obs.toggleRecord();
        tryCompare(obs, "recording", true, 3000);
        obs.toggleRecord();
        tryCompare(savedSpy, "count", 1, 3000);
        compare(discardedSpy.count, 1);
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
