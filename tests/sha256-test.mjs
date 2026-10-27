// Checks package/contents/ui/sha256.js against Node's crypto module.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = readFileSync(new URL("../package/contents/ui/sha256.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const lib = {};
vm.runInNewContext(src, lib);

const b64sha = s => createHash("sha256").update(s, "utf8").digest("base64");
const samples = ["", "a", "abc", "x".repeat(55), "y".repeat(56), "z".repeat(64), "q".repeat(1000),
                 "Passwört mit Ümlauten", "emoji 🎥 test", "salt+/=challenge"];

let failed = 0;
for (const s of samples) {
    const got = lib.base64(lib.sha256(lib.utf8Bytes(s)));
    if (got !== b64sha(s)) {
        console.error(`sha256 mismatch for ${JSON.stringify(s)}: ${got} != ${b64sha(s)}`);
        failed++;
    }
}
for (const pw of samples) {
    const expected = b64sha(b64sha(pw + "SALT") + "CHALLENGE");
    if (lib.obsAuth(pw, "SALT", "CHALLENGE") !== expected) {
        console.error(`obsAuth mismatch for ${JSON.stringify(pw)}`);
        failed++;
    }
}
console.log(failed ? `sha256: ${failed} failures` : `sha256: ${samples.length * 2} checks passed`);
process.exit(failed ? 1 : 0);
