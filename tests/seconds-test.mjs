// Checks package/contents/ui/seconds.js: seconds typed with comma or point.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = readFileSync(new URL("../package/contents/ui/seconds.js", import.meta.url), "utf8")
    .replace(/^\.pragma library$/m, "");
const s = {};
vm.runInNewContext(src, s);

let failed = 0;
const check = (name, ok) => {
    if (!ok) {
        console.error(`seconds: ${name} failed`);
        failed++;
    }
};

check("comma", s.parse("1,5 s") === 1.5);
check("point", s.parse("1.5") === 1.5);
check("whole", s.parse("2 s") === 2);
check("leading point", s.parse(".5") === 0.5);
check("empty", Number.isNaN(s.parse("")));
check("no number", Number.isNaN(s.parse("Sofort")));

console.log(failed ? `seconds: ${failed} failures` : "seconds: all checks passed");
process.exit(failed ? 1 : 0);
