import QtQuick
import QtQuick.Shapes

import org.kde.kirigami as Kirigami

import "replaymark.js" as Mark

// Indicator for a running replay buffer, laid over a dot of dotSize at the item's origin:
// a small dot or circular arrow at its top right ("dot", "arrow"), a small dot in its middle
// ("center"), or a line below it ("bar").
Item {
    id: mark

    property real dotSize: 13
    property string style: "dot"
    property color markColor: Kirigami.Theme.positiveTextColor

    readonly property bool corner: style === "dot" || style === "arrow"
    readonly property var badgeGeo: Mark.badge(dotSize)
    readonly property var barGeo: Mark.bar(dotSize)
    readonly property var coreGeo: Mark.core(dotSize)
    property real blinkScale: 1

    // Short double pulse, e.g. for a saved clip.
    function blink() {
        blinkAnimation.restart();
    }

    width: dotSize
    height: dotSize

    // Circular arrow filling its square item, open at the top, head pointing clockwise.
    component Arrow: Shape {
        id: arrowShape

        property color color: mark.markColor
        readonly property real strokeWidth: Math.max(1, Math.round(width / 7))
        readonly property real radius: width / 2 - strokeWidth
        readonly property var head: Mark.arrowHead(width / 2, width / 2, radius, 240,
                                                   Math.max(strokeWidth * 2.2, radius * 0.9))

        height: width
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: arrowShape.color
            strokeWidth: arrowShape.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: arrowShape.width / 2
                centerY: arrowShape.width / 2
                radiusX: arrowShape.radius
                radiusY: arrowShape.radius
                startAngle: -60
                sweepAngle: 300
            }
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: arrowShape.color
            startX: arrowShape.head[0].x
            startY: arrowShape.head[0].y

            PathLine { x: arrowShape.head[1].x; y: arrowShape.head[1].y }
            PathLine { x: arrowShape.head[2].x; y: arrowShape.head[2].y }
            PathLine { x: arrowShape.head[0].x; y: arrowShape.head[0].y }
        }
    }

    Rectangle {
        visible: mark.style === "bar"
        x: mark.barGeo.x
        y: mark.barGeo.y
        width: mark.barGeo.width
        height: mark.barGeo.height
        radius: height / 2
        color: mark.markColor
        scale: mark.blinkScale
    }

    Rectangle {
        visible: mark.style === "center"
        x: mark.coreGeo.x
        y: mark.coreGeo.x
        width: mark.coreGeo.size
        height: width
        radius: width / 2
        color: mark.markColor
        scale: mark.blinkScale
    }

    Item {
        id: badge
        readonly property bool arrow: mark.style === "arrow"

        visible: mark.corner
        width: arrow ? Mark.arrowSize(mark.dotSize) : mark.badgeGeo.size
        height: width
        x: mark.badgeGeo.cx - width / 2
        y: mark.badgeGeo.cy - height / 2
        scale: mark.blinkScale

        // Separates the mark from the dot's outline.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 2 * Math.max(1, Math.round(parent.width / 5))
            height: width
            radius: width / 2
            color: Kirigami.Theme.backgroundColor
        }

        Rectangle {
            visible: !badge.arrow
            anchors.fill: parent
            radius: width / 2
            color: mark.markColor
        }

        Arrow {
            visible: badge.arrow
            width: badge.width
        }
    }

    SequentialAnimation {
        id: blinkAnimation
        loops: 2
        NumberAnimation { target: mark; property: "blinkScale"; to: 1.6; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: mark; property: "blinkScale"; to: 1; duration: 180; easing.type: Easing.InQuad }
    }
}
