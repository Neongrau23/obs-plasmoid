// Checks package/contents/ui/follow.js: scene assignments and the dwell time per screen.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = readFileSync(new URL("../package/contents/ui/follow.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const f = {};
vm.runInNewContext(src, f);

let failed = 0;
const check = (name, ok) => {
    if (!ok) {
        console.error(`follow: ${name} failed`);
        failed++;
    }
};

check("empty setting", JSON.stringify(f.parseScenes("")) === "{}");
check("broken setting", JSON.stringify(f.parseScenes("{oops")) === "{}");
check("array setting", JSON.stringify(f.parseScenes("[1]")) === "{}");

let json = f.withScene("", "DP-1", "Left = main");
json = f.withScene(json, "HDMI-A-1", "Right");
check("set scenes", f.parseScenes(json)["DP-1"] === "Left = main" && f.parseScenes(json)["HDMI-A-1"] === "Right");
json = f.withScene(json, "HDMI-A-1", "");
check("remove scene", !("HDMI-A-1" in f.parseScenes(json)));

const renamed = f.renameScene(f.withScene(json, "HDMI-A-3", "Left = main"), "Left = main", "Main");
check("rename all", f.parseScenes(renamed)["DP-1"] === "Main" && f.parseScenes(renamed)["HDMI-A-3"] === "Main");
check("rename unknown keeps json", f.renameScene(json, "Nope", "X") === json);

// Immediately: the screen counts on the first poll.
let t = f.createTracker();
check("delay 0 counts at once", f.update(t, "DP-1", 1000, 0) === "DP-1");

// 500 ms: passing over a screen switches nothing, staying does.
t = f.createTracker();
check("first poll waits", f.update(t, "DP-1", 0, 500) === "");
check("still waiting", f.update(t, "DP-1", 400, 500) === "");
check("counts after delay", f.update(t, "DP-1", 500, 500) === "DP-1");
check("new screen waits", f.update(t, "HDMI-A-1", 600, 500) === "");
check("back before delay restarts", f.update(t, "DP-1", 800, 500) === "");
check("restarted timer", f.update(t, "DP-1", 1200, 500) === "" && f.update(t, "DP-1", 1300, 500) === "DP-1");
check("no screen never counts", f.update(t, "", 5000, 0) === "");

console.log(failed ? `follow: ${failed} failures` : "follow: all checks passed");
process.exit(failed ? 1 : 0);
