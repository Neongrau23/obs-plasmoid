.pragma library

// Geometry of the replay buffer indicator next to the dot. All values are relative to
// the dot's top left corner; dotSize is the dot's diameter. Checked in tests/replaymark-test.mjs.

// Small disc (dot or circular arrow) on the dot's top right, centered on its outline.
function badge(dotSize) {
    const r = dotSize / 2;
    const offset = r * 0.72;
    return { cx: r + offset, cy: r - offset, size: Math.max(4, Math.round(dotSize * 0.38)) };
}

// Line below the dot, like the marker of running apps in the task manager. Its width has
// the dot's parity, so both ends sit on whole pixels.
function bar(dotSize) {
    const width = dotSize - 2 * Math.round(dotSize * 0.1);
    const height = Math.max(2, Math.round(dotSize * 0.15));
    const gap = Math.max(1, Math.round(dotSize * 0.15));
    return { x: (dotSize - width) / 2, y: dotSize + gap, width: width, height: height };
}

// Arrow head at the end of a clockwise arc (center cx/cy, radius r, end angle endDeg with
// 0 = 3 o'clock, y downwards as in QML). Returns [tip, base1, base2].
function arrowHead(cx, cy, r, endDeg, len) {
    const a = endDeg * Math.PI / 180;
    const end = { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) };
    const tangent = { x: -Math.sin(a), y: Math.cos(a) };
    const normal = { x: Math.cos(a), y: Math.sin(a) };
    const point = (n, t) => ({ x: end.x + normal.x * n + tangent.x * t,
                               y: end.y + normal.y * n + tangent.y * t });
    return [point(0, len * 0.6), point(len * 0.5, -len * 0.2), point(-len * 0.5, -len * 0.2)];
}
