.pragma library

// Seconds typed into a spin box, such as "1,5 s", "1.5" or "2". Takes comma and point
// alike whatever the locale: Number.fromLocaleString throws on "1.5" in German.
// Returns NaN when the text holds no number.
function parse(text) {
    const number = String(text).replace(",", ".").replace(/[^0-9.]/g, "");
    return number === "" ? NaN : parseFloat(number);
}
