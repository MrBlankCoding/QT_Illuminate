import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 300
    height: 200

    Component {
        id: profileTileComponent
        ProfileTile {
            width: 120
            height: 128
        }
    }

    SignalSpy {
        id: tileClickedSpy
        signalName: "tileClicked"
    }

    SignalSpy {
        id: tileRightClickedSpy
        signalName: "tileRightClicked"
    }

    TestCase {
        name: "ProfileTileTests"
        when: windowShown

        function test_componentExists() {
            let tile = createTemporaryObject(profileTileComponent, root)
            verify(!!tile, "Component exists")
        }

        function test_defaults() {
            let tile = createTemporaryObject(profileTileComponent, root)
            verify(!!tile, "Component exists")
            compare(tile.avatarColor, "")
            compare(tile.profile, null)
        }

        function test_avatarColorWritable() {
            let tile = createTemporaryObject(profileTileComponent, root)
            verify(!!tile, "Component exists")
            tile.avatarColor = '#2da7a1'
            compare(tile.avatarColor, '#2da7a1')
        }

        function test_profileNameRenders() {
            let tile = createTemporaryObject(profileTileComponent, root)
            verify(!!tile, "Component exists")
            tile.profile = { name: qsTr("Ethan") }
            compare(tile.profile.name, qsTr("Ethan"))
        }

        function test_tileClicked() {
            let tile = createTemporaryObject(profileTileComponent, root)
            verify(!!tile, "Component exists")
            tileClickedSpy.target = tile
            tileClickedSpy.clear()
            mouseClick(tile, tile.width / 2, tile.height / 2)
            tryCompare(tileClickedSpy, "count", 1)
        }

        function test_tileRightClicked() {
            let tile = createTemporaryObject(profileTileComponent, root)
            verify(!!tile, "Component exists")
            tileRightClickedSpy.target = tile
            tileRightClickedSpy.clear()
            mouseClick(tile, tile.width / 2, tile.height / 2, Qt.RightButton)
            tryCompare(tileRightClickedSpy, "count", 1)
        }
    }
}