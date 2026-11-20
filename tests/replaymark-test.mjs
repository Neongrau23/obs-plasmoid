// Checks package/contents/ui/replaymark.js: where the replay buffer indicator sits
// relative to the dot (all values relative to the dot's top left corner).
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = readFileSync(new URL("../package/contents/ui/replaymark.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const m = {};
vm.runInNewContext(src, m);

let failed = 0;
const check = (name, ok) => {
    if (!ok) {
        console.error(`replaymark: ${name} failed`);
        failed++;
    }
};
const near = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;

for (const dot of [10, 13, 26]) {
    const r = dot / 2;

    const b = m.badge(dot);
    check(`badge ${dot}: right of the center`, b.cx > r);
    check(`badge ${dot}: above the center`, b.cy < r);
    check(`badge ${dot}: on the 45° diagonal`, near(b.cx - r, r - b.cy));
    check(`badge ${dot}: at least 5 px`, b.size >= 5);

    const bar = m.bar(dot);
    check(`bar ${dot}: below the dot with a gap`, bar.y > dot);
    check(`bar ${dot}: centered`, near(bar.x * 2 + bar.width, dot));
    check(`bar ${dot}: narrower than the dot`, bar.width < dot && bar.width > 0);
    check(`bar ${dot}: at least 2 px high`, bar.height >= 2);
}

// Arc end at 3 o'clock, drawn clockwise (y grows downwards): the tip points down.
const [tip, b1, b2] = m.arrowHead(0, 0, 10, 0, 4);
check("arrow: tip ahead along the clockwise tangent", tip.y > 0 && near(tip.x, 10));
check("arrow: base points on both sides of the arc", near(b1.x + b2.x, 20) && Math.abs(b1.x - b2.x) > 0);
check("arrow: base behind the tip", b1.y < tip.y && b2.y < tip.y);

console.log(failed ? `replaymark: ${failed} failures` : "replaymark: all checks passed");
process.exit(failed ? 1 : 0);
