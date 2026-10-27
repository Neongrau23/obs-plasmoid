import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Connection")
        icon: "network-connect"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Appearance & Behavior")
        icon: "preferences-desktop-color"
        source: "configAppearance.qml"
    }
    ConfigCategory {
        name: i18n("Follow Mouse Pointer")
        icon: "input-mouse"
        source: "configFollowMouse.qml"
    }
}
