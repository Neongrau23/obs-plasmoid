import QtQuick
import QtQuick.Controls as QQC2

// Scene choice for the settings pages. Offers "none", the OBS scenes and the saved scene
// even if OBS does not know it (any more). Reports a choice by picked(); "" means none.
QQC2.ComboBox {
    id: combo

    property var scenes: []
    property string current

    signal picked(string scene)

    textRole: "text"
    valueRole: "value"
    implicitContentWidthPolicy: QQC2.ComboBox.WidestText
    model: {
        const items = [{ value: "", text: i18n("None") }];
        scenes.forEach(name => items.push({ value: name, text: name }));
        if (current !== "" && !scenes.includes(current)) {
            items.push({ value: current, text: i18n("%1 (not found in OBS)", current) });
        }
        return items;
    }
    // Set explicitly instead of bound: the ComboBox resets its index itself whenever the
    // model is rebuilt (scenes arriving from OBS), after a binding would have run.
    function selectCurrent() {
        currentIndex = Math.max(indexOfValue(current), 0);
    }

    onCountChanged: Qt.callLater(selectCurrent)
    onModelChanged: Qt.callLater(selectCurrent)
    onCurrentChanged: selectCurrent()
    Component.onCompleted: selectCurrent()
    onActivated: picked(currentValue)
}
