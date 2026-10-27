.pragma library

// Same slider curve as the OBS audio mixer (OBS_FADER_LOG in libobs/obs-audio-controls.c),
// so a slider position here matches the one in OBS. Position 0..1, volume as multiplier.

var LOG_OFFSET_DB = 6;
var LOG_RANGE_DB = 96;
var LOG_OFFSET_VAL = -Math.log10(LOG_OFFSET_DB);
var LOG_RANGE_VAL = -Math.log10(LOG_RANGE_DB + LOG_OFFSET_DB);

function dbToPosition(db) {
    if (db >= 0) {
        return 1;
    }
    if (db <= -LOG_RANGE_DB) {
        return 0;
    }
    return (-Math.log10(-db + LOG_OFFSET_DB) - LOG_RANGE_VAL) / (LOG_OFFSET_VAL - LOG_RANGE_VAL);
}

function positionToDb(position) {
    if (position >= 1) {
        return 0;
    }
    if (position <= 0) {
        return -Infinity;
    }
    return -(LOG_RANGE_DB + LOG_OFFSET_DB) * Math.pow((LOG_RANGE_DB + LOG_OFFSET_DB) / LOG_OFFSET_DB, -position)
           + LOG_OFFSET_DB;
}

function mulToDb(mul) {
    return mul > 0 ? 20 * Math.log10(mul) : -Infinity;
}

function dbToMul(db) {
    return db === -Infinity ? 0 : Math.pow(10, db / 20);
}

function mulToPosition(mul) {
    return dbToPosition(mulToDb(mul));
}

function positionToMul(position) {
    return dbToMul(positionToDb(position));
}

function formatDb(mul) {
    var db = mulToDb(mul);
    return db === -Infinity ? "-∞ dB" : db.toFixed(1).replace(".", ",") + " dB";
}
