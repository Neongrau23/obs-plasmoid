import QtQuick

// Keeps a settings page's cfg_ values in step with the widget's configuration while the
// dialog is open. The dialog fills a page once when it opens and on OK/Apply writes back
// every cfg_ value the page has, including the plain properties it only declares. Without
// this, a change made meanwhile, e.g. a scene renamed in OBS, would be reverted. Values the
// user edited on the page are left alone.
Item {
    id: sync

    required property Item page
    // Plasmoid.configuration, or anything with keys() and valueChanged(key, value).
    required property var config

    // Per key the value the page showed last without the user changing it.
    property var shown: ({})

    Component.onCompleted: {
        const values = {};
        config.keys().forEach(key => {
            const property = "cfg_" + key;
            if (property in page) {
                values[key] = page[property];
            }
        });
        shown = values;
    }

    Connections {
        target: sync.config

        function onValueChanged(key, value) {
            const property = "cfg_" + key;
            if (!(property in sync.page)) {
                return;
            }
            const current = String(sync.page[property]);
            if (current === String(value)) {
                // Already in step, e.g. right after Apply wrote the page's value.
                sync.shown[key] = value;
            } else if (current === String(sync.shown[key])) {
                sync.page[property] = value;
                sync.shown[key] = value;
            }
        }
    }
}
