import QtQuick 2.7
import QtQuick.Controls 2.3
import QtQuick.Layouts 1.3
import Controls 1.0
import Utils 1.0
import MaterialIcons 2.2

/**
  A component displaying a Graph (nodes, attributes and edges).
*/
Item {
    id: root

    property variant uigraph: null  /// Meshroom ui graph (UIGraph)
    readonly property variant graph: uigraph ? uigraph.graph : null  /// core graph contained in ui graph
    property variant nodeTypesModel: null  /// the list of node types that can be instantiated
    property bool readOnly: false

    property var _attributeToDelegate: ({})

    // signals
    signal workspaceMoved()
    signal workspaceClicked()

    signal nodeDoubleClicked(var mouse, var node)
    signal computeRequest(var node)
    signal submitRequest(var node)

    // trigger initial fit() after initialization
    // (ensure GraphEditor has its final size)
    Component.onCompleted: firstFitTimer.start()

    Timer {
        id: firstFitTimer
        running: false
        interval: 10
        onTriggered: fit()
    }

    clip: true

    SystemPalette { id: activePalette }

    /// Get node delegate for the given node object
    function nodeDelegate(node)
    {
        for(var i=0; i<nodeRepeater.count; ++i)
        {
            if(nodeRepeater.itemAt(i).node === node)
                return nodeRepeater.itemAt(i)
        }
        return undefined
    }

    /// Select node delegate
    function selectNode(node)
    {
        uigraph.selectedNode = node
    }

    /// Duplicate a node and optionnally all the following ones
    function duplicateNode(node, duplicateFollowingNodes) {
        if(root.readOnly)
            return;
        var nodes = uigraph.duplicateNode(node, duplicateFollowingNodes)
        selectNode(nodes[0])
    }


    Keys.onPressed: {
        if(event.key === Qt.Key_F)
            fit()
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        property double factor: 1.15
        property real minZoom: 0.1
        property real maxZoom: 2.0
        // Activate multisampling for edges antialiasing
        layer.enabled: true
        layer.samples: 8

        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        drag.threshold: 0
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.ArrowCursor

        onWheel: {
            var zoomFactor = wheel.angleDelta.y > 0 ? factor : 1/factor
            var scale = draggable.scale * zoomFactor
            scale = Math.min(Math.max(minZoom, scale), maxZoom)
            if(draggable.scale == scale)
                return
            var point = mapToItem(draggable, wheel.x, wheel.y)
            draggable.x += (1-zoomFactor) * point.x * draggable.scale
            draggable.y += (1-zoomFactor) * point.y * draggable.scale
            draggable.scale = scale
            workspaceMoved()
        }

        onPressed: {
            if(mouse.button != Qt.MiddleButton && mouse.modifiers == Qt.NoModifier)
                selectNode(null)

            if(mouse.button == Qt.MiddleButton || (mouse.button & Qt.LeftButton && mouse.modifiers & Qt.ShiftModifier))
                drag.target = draggable // start drag
        }
        onReleased: {
            drag.target = undefined // stop drag
            root.forceActiveFocus()
            workspaceClicked()
        }
        onPositionChanged: {
            if(drag.active)
                workspaceMoved()
        }

        onClicked: {
            if(mouse.button == Qt.RightButton)
            {
                if(readOnly)
                    lockedMenu.popup();
                else {
                    // store mouse click position in 'draggable' coordinates as new node spawn position
                    newNodeMenu.spawnPosition = mouseArea.mapToItem(draggable, mouse.x, mouse.y);
                    newNodeMenu.popup();
                }
            }
        }

        // menuItemDelegate is wrapped in a component so it can be used in both the searchbar and sub-menus
        Component {
            id: menuItemDelegateComponent
            MenuItem {
                id: menuItemDelegate
                font.pointSize: 8
                padding: 3
            
                // Hide items that does not match the filter text
                visible: modelData.toLowerCase().indexOf(searchBar.text.toLowerCase()) > -1
                // Reset menu currentIndex if highlighted items gets filtered out
                onVisibleChanged: if(highlighted) newNodeMenu.currentIndex = 0
                text: modelData
                // Forward key events to the search bar to continue typing seamlessly
                // even if this delegate took the activeFocus due to mouse hovering
                Keys.forwardTo: [searchBar.textField]
                Keys.onPressed: {
                    event.accepted = false;
                    switch(event.key) {
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            // create node on validation (Enter/Return keys)
                            newNodeMenu.createNode(modelData);
                            event.accepted = true;
                            break;
                        case Qt.Key_Up:
                        case Qt.Key_Down:
                        case Qt.Key_Left:
                        case Qt.Key_Right:
                            break; // ignore if arrow key was pressed to let the menu be controlled
                        default:
                            console.warn("switching focus");
                            searchBar.forceActiveFocus();
                    }
                }
                // Create node on mouse click
                onClicked: newNodeMenu.createNode(modelData)
            
                states: [
                    State {
                        // Additional property setting when the MenuItem is not visible
                        when: !visible
                        name: "invisible"
                        PropertyChanges {
                            target: menuItemDelegate
                            height: 0 // make sure the item is no visible by setting height to 0
                            focusPolicy: Qt.NoFocus // don't grab focus when not visible
                        }
                    }
                ]
            }
        }

        // Contextual Menu for creating new nodes
        // TODO: add filtering + validate on 'Enter'
        Menu {
            id: newNodeMenu
            property point spawnPosition

            function parseCategories()
            {
                let categories = {};
                for (var n in root.nodeTypesModel) {
                    let category = root.nodeTypesModel[n]["category"];
                    if (categories[category] === undefined) {
                        categories[category] = []
                    }
                    categories[category].push(n)
                }
                return categories
            }

            function createNode(nodeType)
            {
                // add node via the proper command in uigraph
                var node = uigraph.addNewNode(nodeType, spawnPosition)
                newNodeMenu.close()
                selectNode(node)
            }

            onVisibleChanged: {
                if (visible) {
                    // when menu is shown, clear the searchbar
                    searchBar.clear()
                    searchBar.focus = false;
                    newNodeMenu.forceActiveFocus()
                }
            }

            onActiveFocusChanged: {
                // The current index must be reset after the searchbar loses focus and has text
                if (activeFocus && searchBar.text != "") {
                    currentIndex = 2
                }
            }

            SearchBar {
                id: searchBar
                width: parent.width
            }
            
            // Adds a small gap under the searchbar for aesthetic reasons
            MenuSeparator { 
                visible: false
                focusPolicy: Qt.NoFocus
                // Sometimes this steals the activeFocus from the searchbar
                onFocusChanged: {
                    if (focus && searchBar.text != "") {
                        searchBar.forceActiveFocus()
                    }
                }
            } 

            Repeater {
                id: nodeMenuRepeater
                model: searchBar.text != "" ? Object.keys(root.nodeTypesModel) : undefined

                // Create Menu items from available items
                delegate: menuItemDelegateComponent
            }
            
            // Dynamically add the menu categories
            Instantiator { 
                model: !(searchBar.text != "") ? Object.keys(newNodeMenu.parseCategories()) : undefined
                onObjectAdded: newNodeMenu.insertMenu(index+2, object ) 
                onObjectRemoved: newNodeMenu.removeMenu(object)  
                delegate: Menu {  
                    title: modelData
                    id: newNodeSubMenu

                    Instantiator { 
                        model: newNodeMenu.visible && newNodeSubMenu.activeFocus ? newNodeMenu.parseCategories()[modelData] : undefined
                        onObjectAdded: newNodeSubMenu.insertItem(index, object) 
                        onObjectRemoved: newNodeSubMenu.removeItem(object)  
                        delegate: menuItemDelegateComponent
                    }
                }  
            }
        }

        // Informative contextual menu when graph is read-only
        Menu {
            id: lockedMenu
            MenuItem {
                id: item
                font.pointSize: 8
                enabled: false
                text: "Computing - Graph is Locked!"
            }
        }

        Item {
            id: draggable
            transformOrigin: Item.TopLeft
            width: 1000
            height: 1000

            Menu {
                id: edgeMenu
                property var currentEdge: null
                MenuItem {
                    text: "Remove"
                    enabled: !root.readOnly
                    onTriggered: uigraph.removeEdge(edgeMenu.currentEdge)
                }
            }

            // Edges
            Repeater {
                id: edgesRepeater

                // delay edges loading after nodes (edges needs attribute pins to be created)
                model: nodeRepeater.loaded ? root.graph.edges : undefined

                delegate: Edge {
                    property var src: root._attributeToDelegate[edge.src]
                    property var dst: root._attributeToDelegate[edge.dst]
                    property var srcAnchor: src.nodeItem.mapFromItem(src, src.edgeAnchorPos.x, src.edgeAnchorPos.y)
                    property var dstAnchor: dst.nodeItem.mapFromItem(dst, dst.edgeAnchorPos.x, dst.edgeAnchorPos.y)

                    property bool inFocus: containsMouse || (edgeMenu.opened && edgeMenu.currentEdge == edge)

                    edge: object
                    color: inFocus ? activePalette.highlight : activePalette.text
                    thickness: inFocus ? 2 : 1
                    opacity: 0.7
                    point1x: src.nodeItem.x + srcAnchor.x
                    point1y: src.nodeItem.y + srcAnchor.y
                    point2x: dst.nodeItem.x + dstAnchor.x
                    point2y: dst.nodeItem.y + dstAnchor.y
                    onPressed: {
                        if(event.button == Qt.RightButton)
                        {
                            if(!root.readOnly && event.modifiers & Qt.AltModifier) {
                                uigraph.removeEdge(edge)
                            }
                            else {
                                edgeMenu.currentEdge = edge
                                edgeMenu.popup()
                            }
                        }
                    }
                }
            }

            Menu {
                id: nodeMenu
                property var currentNode: null
                property bool canComputeNode: currentNode != null && uigraph.graph.canCompute(currentNode)
                onClosed: currentNode = null

                MenuItem {
                    text: "Compute"
                    enabled: !uigraph.computing && !root.readOnly && nodeMenu.canComputeNode
                    onTriggered: computeRequest(nodeMenu.currentNode)
                }
                MenuItem {
                    text: "Submit"
                    enabled: !uigraph.computing && !root.readOnly && nodeMenu.canComputeNode
                    visible: uigraph.canSubmit
                    height: visible ? implicitHeight : 0
                    onTriggered: submitRequest(nodeMenu.currentNode)
                }
                MenuItem {
                    text: "Open Folder"
                    onTriggered: Qt.openUrlExternally(Filepath.stringToUrl(nodeMenu.currentNode.internalFolder))
                }
                MenuSeparator {}
                MenuItem {
                    text: "Duplicate Node" + (duplicateFollowingButton.hovered ? "s From Here" : "")
                    enabled: !root.readOnly
                    onTriggered: duplicateNode(nodeMenu.currentNode, false)
                    MaterialToolButton {
                        id: duplicateFollowingButton
                        height: parent.height
                        anchors { right: parent.right; rightMargin: parent.padding }
                        text: MaterialIcons.fast_forward
                        onClicked: {
                            duplicateNode(nodeMenu.currentNode, true);
                            nodeMenu.close();
                        }
                    }
                }
                MenuItem {
                    text: "Remove Node" + (removeFollowingButton.hovered ? "s From Here" : "")
                    enabled: !root.readOnly
                    onTriggered: uigraph.removeNode(nodeMenu.currentNode)
                    MaterialToolButton {
                        id: removeFollowingButton
                        height: parent.height
                        anchors { right: parent.right; rightMargin: parent.padding }
                        text: MaterialIcons.fast_forward
                        onClicked: {
                            uigraph.removeNodesFrom(nodeMenu.currentNode);
                            nodeMenu.close();
                        }
                    }
                }
                MenuSeparator {}
                MenuItem {
                    text: "Delete Data" + (deleteFollowingButton.hovered ? " From Here" : "" ) + "..."
                    enabled: !root.readOnly

                    function showConfirmationDialog(deleteFollowing) {
                        var obj = deleteDataDialog.createObject(root,
                                           {
                                               "node": nodeMenu.currentNode,
                                               "deleteFollowing": deleteFollowing
                                           });
                        obj.open()
                        nodeMenu.close();
                    }

                    onTriggered: showConfirmationDialog(false)

                    MaterialToolButton {
                        id: deleteFollowingButton
                        anchors { right: parent.right; rightMargin: parent.padding }
                        height: parent.height
                        text: MaterialIcons.fast_forward
                        onClicked: parent.showConfirmationDialog(true)
                    }

                    // Confirmation dialog for node cache deletion
                    Component {
                        id: deleteDataDialog
                        MessageDialog  {
                            property var node
                            property bool deleteFollowing: false

                            focus: true
                            modal: false
                            header.visible: false

                            text: "Delete Data computed by '" + node.label + (deleteFollowing ?  "' and following Nodes?" : "'?")
                            helperText: "Warning: This operation can not be undone."
                            standardButtons: Dialog.Yes | Dialog.Cancel

                            onAccepted: {
                                if(deleteFollowing)
                                    graph.clearDataFrom(node);
                                else
                                    node.clearData();
                            }
                            onClosed: destroy()
                        }
                    }
                }
            }

            // Nodes
            Repeater {
                id: nodeRepeater

                model: root.graph.nodes
                property bool loaded: count === model.count

                delegate: Node {
                    id: nodeDelegate

                    property bool animatePosition: true

                    node: object
                    width: uigraph.layout.nodeWidth
                    readOnly: root.readOnly
                    selected: uigraph.selectedNode === node
                    hovered: uigraph.hoveredNode === node
                    onSelectedChanged: if(selected) forceActiveFocus()

                    onAttributePinCreated: registerAttributePin(attribute, pin)
                    onAttributePinDeleted: unregisterAttributePin(attribute, pin)

                    onPressed: {
                        selectNode(node)

                        if(mouse.button == Qt.LeftButton && mouse.modifiers & Qt.AltModifier)
                        {
                            duplicateNode(node, true)
                        }
                        if(mouse.button == Qt.RightButton)
                        {
                            nodeMenu.currentNode = node
                            nodeMenu.popup()
                        }
                    }

                    onDoubleClicked: root.nodeDoubleClicked(mouse, node)

                    onMoved: uigraph.moveNode(node, position)

                    onEntered: uigraph.hoveredNode = node
                    onExited: uigraph.hoveredNode = null

                    Keys.onDeletePressed: {
                        if(root.readOnly)
                            return;
                        if(event.modifiers == Qt.AltModifier)
                            uigraph.removeNodesFrom(node)
                        else
                            uigraph.removeNode(node)
                    }

                    Behavior on x {
                        enabled: animatePosition
                        NumberAnimation { duration: 100 }
                    }
                    Behavior on y {
                        enabled: animatePosition
                        NumberAnimation { duration: 100 }
                    }
                }
            }
        }
    }

    // Toolbar
    FloatingPane {
        padding: 2
        anchors.bottom: parent.bottom
        RowLayout {
            spacing: 4
            // Fit
            MaterialToolButton {
                text: MaterialIcons.fullscreen
                ToolTip.text: "Fit"
                onClicked: root.fit()
            }
            // Auto-Layout
            MaterialToolButton {
                text: MaterialIcons.linear_scale
                ToolTip.text: "Auto-Layout"
                onClicked: uigraph.layout.reset()
            }

            // Separator
            Rectangle {
                Layout.fillHeight: true
                Layout.margins: 2
                implicitWidth: 1
                color: activePalette.window
            }
            // Settings
            MaterialToolButton {
                text: MaterialIcons.settings
                font.pointSize: 11
                onClicked: menu.open()
                Menu {
                    id: menu
                    y: -height
                    padding: 4
                    RowLayout {
                        spacing: 2
                        Label {
                            padding: 2
                            text: "Auto-Layout Depth:"
                        }
                        ComboBox {
                            flat: true
                            model: ['Minimum', 'Maximum']
                            implicitWidth: 80
                            currentIndex: uigraph.layout.depthMode
                            onActivated: {
                                uigraph.layout.depthMode = currentIndex
                            }
                        }
                    }
                }
            }
        }
    }

    function registerAttributePin(attribute, pin)
    {
        root._attributeToDelegate[attribute] = pin
    }
    function unregisterAttributePin(attribute, pin)
    {
        delete root._attributeToDelegate[attribute]
    }

    function boundingBox()
    {
        var first = nodeRepeater.itemAt(0)
        var bbox = Qt.rect(first.x, first.y, first.x + first.width, first.y + first.height)
        for(var i=0; i<root.graph.nodes.count; ++i) {
            var item = nodeRepeater.itemAt(i)
            bbox.x = Math.min(bbox.x, item.x)
            bbox.y = Math.min(bbox.y, item.y)
            bbox.width = Math.max(bbox.width, item.x+item.width)
            bbox.height = Math.max(bbox.height, item.y+item.height)
        }
        bbox.width -= bbox.x
        bbox.height -= bbox.y
        return bbox;
    }

    // Fit graph to fill root
    function fit() {
        // compute bounding box
        var bbox = boundingBox()
        // rescale
        draggable.scale = Math.min(root.width/bbox.width, root.height/bbox.height)
        // recenter
        draggable.x = bbox.x*draggable.scale*-1 + (root.width-bbox.width*draggable.scale)*0.5
        draggable.y = bbox.y*draggable.scale*-1 + (root.height-bbox.height*draggable.scale)*0.5
    }

}
