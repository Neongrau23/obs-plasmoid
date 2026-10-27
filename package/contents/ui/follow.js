.pragma library

// Scene follows the mouse pointer: which screen the pointer is on, and which scene that means.
// Screens are KWin output names such as "DP-1"; the assignment is stored as a JSON object
// { output: scene } in the followMouseScenes setting.

function parseScenes(json) {
    try {
        const scenes = JSON.parse(json || "{}");
        return scenes !== null && typeof scenes === "object" && !Array.isArray(scenes) ? scenes : {};
    } catch (e) {
        return {};
    }
}

// Returns the JSON with the scene of one output set, or removed for an empty scene.
function withScene(json, output, scene) {
    const scenes = parseScenes(json);
    if (scene) {
        scenes[output] = scene;
    } else {
        delete scenes[output];
    }
    return JSON.stringify(scenes);
}

// Keeps the assignments when a scene is renamed in OBS.
function renameScene(json, oldName, newName) {
    const scenes = parseScenes(json);
    let changed = false;
    for (const output in scenes) {
        if (scenes[output] === oldName) {
            scenes[output] = newName;
            changed = true;
        }
    }
    return changed ? JSON.stringify(scenes) : json;
}

// A screen counts only once the pointer has stayed on it for delayMs, so passing over a
// screen on the way to another switches nothing. Feed every poll result into update();
// it returns the screen that counts, or "" while the pointer has not stayed long enough.
function createTracker() {
    return { output: "", since: 0 };
}

function update(tracker, output, now, delayMs) {
    if (output !== tracker.output) {
        tracker.output = output;
        tracker.since = now;
    }
    return output !== "" && now - tracker.since >= delayMs ? output : "";
}
