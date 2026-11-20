import QtQuick
import QtTest

import "../package/contents/ui"

// ConfigSync keeps a settings page in step with configuration changes made elsewhere while
// the dialog is open (e.g. a scene renamed in OBS), without overriding what the user edited.
TestCase {
    name: "ConfigSync"

    Component {
        id: configComponent
        QtObject {
            signal valueChanged(string key, var value)
            property var values: ({ scrollUpScene: "Gameplay", host: "localhost", followMouse: false })
            function keys() {
                return Object.keys(values);
            }
        }
    }

    Component {
        id: pageComponent
        Item {
            property string cfg_scrollUpScene: "Gameplay"
            property string cfg_host: "localhost"
        }
    }

    Component {
        id: syncComponent
        ConfigSync {}
    }

    function setup() {
        const config = createTemporaryObject(configComponent, this);
        const page = createTemporaryObject(pageComponent, this);
        createTemporaryObject(syncComponent, this, { page: page, config: config });
        return { config: config, page: page };
    }

    function test_followsUntouchedValue() {
        const t = setup();
        t.config.valueChanged("scrollUpScene", "Spiel");
        compare(t.page.cfg_scrollUpScene, "Spiel");
    }

    function test_keepsValueEditedOnThePage() {
        const t = setup();
        t.page.cfg_host = "obs.example";
        t.config.valueChanged("host", "other.example");
        compare(t.page.cfg_host, "obs.example");
    }

    // After Apply the configuration holds the page's value; later outside changes follow again.
    function test_followsAgainAfterApply() {
        const t = setup();
        t.page.cfg_host = "obs.example";
        t.config.valueChanged("host", "obs.example");
        t.config.valueChanged("host", "renamed.example");
        compare(t.page.cfg_host, "renamed.example");
    }

    function test_ignoresKeysThePageDoesNotHave() {
        const t = setup();
        t.config.valueChanged("followMouse", true);
        verify(!("cfg_followMouse" in t.page));
        compare(t.page.cfg_scrollUpScene, "Gameplay");
    }
}
