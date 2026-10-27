import QtQuick

import "follow.js" as Follow

// Scene follows the mouse pointer: switches the client to the scene assigned to the screen
// the pointer is on. Fed with screen names by pointerOn(); where they come from is up to
// the owner (main.qml asks KWin). Reports scene changes it did not make itself, so the
// owner can turn following off.
Item {
    id: follower

    property var client
    // JSON object { screen name: scene name }, see follow.js.
    property string scenesJson: "{}"
    // How long the pointer has to stay on a screen before its scene shows.
    property int delayMs: 0

    readonly property var scenes: Follow.parseScenes(scenesJson)
    readonly property bool hasScenes: Object.keys(scenes).length > 0

    // The scene changed some other way: mouse wheel, menu, OBS itself.
    signal otherSceneChange()

    property var tracker: Follow.createTracker()
    // Scene the follower last asked OBS for, and the scene before the latest change.
    property string requestedScene: ""
    property string lastScene: ""

    function reset() {
        tracker = Follow.createTracker();
        requestedScene = "";
    }

    // now: time in ms, for tests; defaults to the current time.
    function pointerOn(screen, now) {
        const counted = Follow.update(tracker, screen, now === undefined ? Date.now() : now, delayMs);
        const scene = scenes[counted];
        if (!scene || scene === client.currentScene || !client.scenes.includes(scene)) {
            return;
        }
        // During a transition switchScene() refuses, and the next call tries again. Only a
        // switch actually requested counts as own: OBS reports it a moment later, and the
        // pointer may have reached the next screen by then.
        if (client.switchScene(scene)) {
            requestedScene = scene;
        }
    }

    // The current scene arrives under its new name; that is no scene change.
    function sceneRenamed(oldName, newName) {
        if (requestedScene === oldName) {
            requestedScene = newName;
        }
        if (lastScene === oldName) {
            lastScene = newName;
        }
    }

    Connections {
        target: follower.client

        // The scene showing up after (re)connecting is no change.
        function onCurrentSceneChanged() {
            const scene = follower.client.currentScene;
            const previous = follower.lastScene;
            follower.lastScene = scene;
            if (previous !== "" && scene !== "" && scene !== previous && scene !== follower.requestedScene) {
                follower.otherSceneChange();
            }
        }
    }
}
