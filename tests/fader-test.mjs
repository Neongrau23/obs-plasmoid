// Checks package/contents/ui/fader.js: end points, round trips and reference values.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = readFileSync(new URL("../package/contents/ui/fader.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const f = {};
vm.runInNewContext(src, f);

let failed = 0;
const check = (name, ok) => {
    if (!ok) {
        console.error(`fader: ${name} failed`);
        failed++;
    }
};
const near = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;

check("position 1 is 0 dB", f.positionToDb(1) === 0 && f.positionToMul(1) === 1);
check("position 0 is silence", f.positionToDb(0) === -Infinity && f.positionToMul(0) === 0);
check("0 dB is position 1", f.dbToPosition(0) === 1);
check("-96 dB is position 0", near(f.dbToPosition(-96), 0));
check("above 0 dB clamps", f.mulToPosition(2) === 1);
check("silence is position 0", f.mulToPosition(0) === 0);
for (let p = 0.05; p < 1; p += 0.05) {
    check(`round trip ${p.toFixed(2)}`, near(f.mulToPosition(f.positionToMul(p)), p));
}
// Monotonic: louder further right.
let last = -1;
for (let p = 0; p <= 1.0001; p += 0.01) {
    const mul = f.positionToMul(Math.min(p, 1));
    check(`monotonic at ${p.toFixed(2)}`, mul >= last);
    last = mul;
}
// Reference values from libobs (obs_fader_create(OBS_FADER_LOG) + obs_fader_get_db), OBS 32.
for (const [p, db] of [[0.1, -70.8343], [0.25, -44.2329], [0.5, -18.7386], [0.75, -6.1833], [0.9, -1.9652]]) {
    check(`libobs reference ${p}`, near(f.positionToDb(p), db, 1e-3));
}
check("format", f.formatDb(1) === "0,0 dB" && f.formatDb(0) === "-∞ dB" && f.formatDb(0.5) === "-6,0 dB");

console.log(failed ? `fader: ${failed} failures` : "fader: all checks passed");
process.exit(failed ? 1 : 0);
