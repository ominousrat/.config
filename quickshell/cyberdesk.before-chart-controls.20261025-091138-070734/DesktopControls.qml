import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import Quickshell
import Quickshell.Services.SystemTray

Item {
    id:bar
    required property var shell
    required property var panelWindow
    property real u:shell.u
    property var audio:shell.desktop.audio
    property var windows:shell.desktop.windows
    function action(a){a.op='desktop-action';shell.send(a);}
    component Label:Text {
        color:bar.shell.ink;font.family:'monospace';font.pixelSize:bar.shell.fontSize*.86
        textFormat:Text.PlainText;elide:Text.ElideRight;verticalAlignment:Text.AlignVCenter
    }
    component Chip:Basic.Button {
        id:chip
        font.family:'monospace';font.pixelSize:bar.shell.fontSize*.85
        height:32*bar.u;hoverEnabled:true
        contentItem:Label { text:chip.text;horizontalAlignment:Text.AlignHCenter }
        background:Rectangle { color:bar.shell.tint(bar.shell.accent,chip.hovered?.13:.05);border.color:bar.shell.tint(bar.shell.accent,.45);radius:5*bar.u }
    }
    // cyberdesk-unified-icon-toolbar-v1
    readonly property int iconCount: 2+trayRepeater.count
    readonly property int rowCount: Math.max(1,Math.ceil(iconCount/5))
    readonly property real gap: 7*bar.u
    readonly property real rowHeight: (rowCount>1?32:36)*bar.u
    readonly property real iconSize: (rowCount>1?20:25)*bar.u
    implicitHeight:rowCount*rowHeight+(rowCount-1)*gap
    function rowItems(row){return Math.floor(iconCount/rowCount)+(row<iconCount%rowCount?1:0);}
    function rowOf(index){
        let offset=0;
        for(let row=0;row<rowCount;row++){
            if(index<offset+rowItems(row))return row;
            offset+=rowItems(row);
        }
        return rowCount-1;
    }
    function columnOf(index){
        let row=rowOf(index),offset=0;
        for(let r=0;r<row;r++)offset+=rowItems(r);
        return index-offset;
    }
    function slotWidth(index){return Math.max(1,(width-gap*(rowItems(rowOf(index))-1))/rowItems(rowOf(index)));}
    function slotX(index){return columnOf(index)*(slotWidth(index)+gap);}
    function slotY(index){return rowOf(index)*(rowHeight+gap);}

    component IconButton:Basic.Button {
        id:iconButton
        property int slot:0
        property string kind:''
        property string iconSource:''
        property string tooltip:''
        x:bar.slotX(slot);y:bar.slotY(slot)
        width:bar.slotWidth(slot);height:bar.rowHeight
        padding:5*bar.u
        hoverEnabled:true
        ToolTip.visible:hovered
        ToolTip.text:tooltip
        background:Rectangle {
            color:bar.shell.tint(bar.shell.accent,iconButton.down?.22:iconButton.hovered?.12:.04)
            border.color:bar.shell.tint(bar.shell.accent,.65)
            radius:3*bar.u
        }
        contentItem:Item {
            Image {
                id:actualIcon
                anchors.centerIn:parent
                width:Math.max(1,Math.min(bar.iconSize,parent.width,parent.height))
                height:width
                source:iconButton.iconSource
                sourceSize.width:Math.ceil(width);sourceSize.height:Math.ceil(height)
                fillMode:Image.PreserveAspectFit
                visible:iconButton.kind==='tray' && status===Image.Ready
            }
            Canvas {
                id:vectorIcon
                anchors.centerIn:parent
                width:Math.max(1,Math.min(bar.iconSize,parent.width,parent.height));height:width
                visible:iconButton.kind!=='tray' || actualIcon.status!==Image.Ready
                property color ink:bar.shell.ink
                property bool muted:bar.audio.muted
                property bool available:bar.audio.available
                property real level:bar.audio.volume
                property string kind:iconButton.kind
                onInkChanged:requestPaint()
                onMutedChanged:requestPaint()
                onAvailableChanged:requestPaint()
                onLevelChanged:requestPaint()
                onKindChanged:requestPaint()
                onWidthChanged:requestPaint()
                onHeightChanged:requestPaint()
                onVisibleChanged:requestPaint()
                onPaint:{
                    let c=getContext('2d');c.reset();c.clearRect(0,0,width,height);
                    c.save();c.scale(width/24,height/24);
                    c.strokeStyle=ink;c.fillStyle=ink;c.lineWidth=1.7;c.lineCap='round';c.lineJoin='round';
                    if(kind==='audio'){
                        c.beginPath();c.moveTo(3,9);c.lineTo(7,9);c.lineTo(12,5);c.lineTo(12,19);c.lineTo(7,15);c.lineTo(3,15);c.closePath();c.stroke();
                        if(muted || !available){
                            c.beginPath();c.moveTo(16,9);c.lineTo(22,15);c.moveTo(16,15);c.lineTo(22,9);c.stroke();
                        }else if(level>0){
                            c.beginPath();c.arc(11,12,6,-.8,.8);c.stroke();
                            if(level>45){c.beginPath();c.arc(11,12,10,-.8,.8);c.stroke();}
                        }
                    }else if(kind==='apps'){
                        for(let x of [3,14])for(let y of [3,14])c.strokeRect(x,y,7,7);
                    }else{
                        c.strokeRect(4,4,16,16);
                        c.beginPath();c.moveTo(8,12);c.lineTo(16,12);c.moveTo(12,8);c.lineTo(12,16);c.stroke();
                    }
                    c.restore();
                }
            }
        }
    }
    IconButton {
        id:audioButton;slot:0;kind:'audio'
        tooltip:(!bar.audio.available?'Audio unavailable':bar.audio.muted?'Audio muted':'Volume '+bar.audio.volume+'%')+'\nClick: outputs and volume · Right-click: pavucontrol · Scroll: volume'
        onClicked:{appsPopup.close();audioPopup.visible?audioPopup.close():audioPopup.open();}
        MouseArea {
            anchors.fill:parent;acceptedButtons:Qt.RightButton
            onClicked:bar.action({action:'pavucontrol'})
            onWheel:wheel=>{if(wheel.angleDelta.y!==0){bar.action({action:'step',value:wheel.angleDelta.y>0?5:-5});wheel.accepted=true;}}
        }
    }
    IconButton {
        id:appsButton;slot:1;kind:'apps'
        tooltip:'Open applications: '+bar.windows.length
        onClicked:{audioPopup.close();appsPopup.visible?appsPopup.close():appsPopup.open();}
    }
    Repeater {
        id:trayRepeater
        model:SystemTray.items
        delegate:IconButton {
            id:trayIcon
            required property var modelData
            required property int index
            slot:index+2;kind:'tray';iconSource:modelData.icon
            tooltip:modelData.tooltipTitle || modelData.title || modelData.id
            QsMenuAnchor { id:trayMenu;anchor.item:trayIcon;menu:trayIcon.modelData.menu }
            onClicked:{
                if(modelData.onlyMenu){if(modelData.hasMenu)trayMenu.open();}
                else modelData.activate();
            }
            MouseArea {
                anchors.fill:parent
                acceptedButtons:Qt.RightButton | Qt.MiddleButton
                onClicked:mouse=>{
                    if(mouse.button===Qt.MiddleButton)trayIcon.modelData.secondaryActivate();
                    else if(trayIcon.modelData.hasMenu)trayMenu.open();
                }
                onWheel:wheel=>{
                    if(wheel.angleDelta.y!==0){trayIcon.modelData.scroll(wheel.angleDelta.y/120,false);wheel.accepted=true;}
                    else if(wheel.angleDelta.x!==0){trayIcon.modelData.scroll(wheel.angleDelta.x/120,true);wheel.accepted=true;}
                }
            }
        }
    }
    Basic.Popup {
        id:audioPopup;x:0;y:bar.height+5*bar.u;width:bar.width
        padding:12*bar.u;popupType:Popup.Item
        closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background:Rectangle { color:bar.shell.tint(bar.shell.bg,.98);border.color:bar.shell.tint(bar.shell.accent,.75);radius:4*bar.u }
        contentItem:Column {
            id:audioContent;width:audioPopup.availableWidth;spacing:9*bar.u
            Label { width:parent.width;height:23*bar.u;text:'Audio output';color:bar.shell.accent }
            Label { width:parent.width;height:22*bar.u;visible:bar.audio.error!=='';text:bar.audio.error;color:'#ffaaaa';font.pixelSize:bar.shell.fontSize*.73 }
            ListView {
                width:parent.width;height:Math.min(150*bar.u,Math.max(32*bar.u,bar.audio.sinks.length*35*bar.u))
                clip:true;model:bar.audio.sinks;boundsBehavior:Flickable.StopAtBounds
                delegate:Basic.ItemDelegate {
                    id:sinkEntry;required property var modelData
                    width:ListView.view.width;height:35*bar.u
                    hoverEnabled:true
                    onClicked:bar.action({action:'sink',index:modelData.index,move_streams:movePlayback.checked})
                    contentItem:Label { text:(sinkEntry.modelData.name===bar.audio.default?'● ':'  ')+sinkEntry.modelData.description;color:sinkEntry.modelData.name===bar.audio.default?bar.shell.accent:bar.shell.ink }
                    background:Rectangle { color:sinkEntry.hovered?bar.shell.tint(bar.shell.accent,.17):'transparent';radius:3*bar.u }
                }
                ScrollBar.vertical:Basic.ScrollBar { }
            }
            Basic.CheckBox {
                id:movePlayback;checked:false;height:29*bar.u;width:parent.width
                text:'Move current playback when switching'
                contentItem:Label { text:movePlayback.text;leftPadding:movePlayback.indicator.width+movePlayback.spacing;font.pixelSize:bar.shell.fontSize*.77 }
                palette.highlight:bar.shell.accent
            }
            Row {
                width:parent.width;spacing:9*bar.u;height:32*bar.u
                Chip { width:83*bar.u;enabled:bar.audio.available;text:bar.audio.muted?'Unmute':'Mute';onClicked:bar.action({action:'mute'}) }
                Basic.Slider {
                    id:volumeSlider;width:audioContent.width-153*bar.u;height:32*bar.u
                    from:0;to:100;stepSize:1;enabled:bar.audio.available
                    value:bar.audio.volume
                    onPressedChanged:{if(!pressed)bar.action({action:'volume',value:Math.round(value)});}
                    onMoved:{if(!pressed)bar.action({action:'volume',value:Math.round(value)});}
                    background:Rectangle { x:volumeSlider.leftPadding;y:volumeSlider.topPadding+volumeSlider.availableHeight/2-height/2;width:volumeSlider.availableWidth;height:4*bar.u;radius:2*bar.u;color:bar.shell.tint(bar.shell.accent,.2)
                        Rectangle { width:volumeSlider.visualPosition*parent.width;height:parent.height;radius:parent.radius;color:bar.shell.accent }
                    }
                    handle:Rectangle { x:volumeSlider.leftPadding+volumeSlider.visualPosition*(volumeSlider.availableWidth-width);y:volumeSlider.topPadding+volumeSlider.availableHeight/2-height/2;width:12*bar.u;height:12*bar.u;radius:6*bar.u;color:bar.shell.ink }
                }
                Label { width:52*bar.u;height:32*bar.u;text:Math.round(volumeSlider.value)+'%' }
            }
            Chip { width:parent.width;text:'Open pavucontrol';onClicked:{audioPopup.close();bar.action({action:'pavucontrol'});} }
        }
    }
    Basic.Popup {
        id:appsPopup;x:0;y:bar.height+5*bar.u;width:bar.width
        padding:8*bar.u;popupType:Popup.Item
        closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background:Rectangle { color:bar.shell.tint(bar.shell.bg,.98);border.color:bar.shell.tint(bar.shell.accent,.75);radius:4*bar.u }
        contentItem:Column {
            width:appsPopup.availableWidth;spacing:7*bar.u
            Label { width:parent.width;height:25*bar.u;text:'Open applications';color:bar.shell.accent }
            Label { visible:bar.windows.length===0;width:parent.width;height:25*bar.u;text:bar.shell.desktop.window_error || 'No open windows' }
            ListView {
                width:parent.width;height:Math.min(290*bar.u,bar.windows.length*47*bar.u)
                clip:true;model:bar.windows;boundsBehavior:Flickable.StopAtBounds
                delegate:Basic.ItemDelegate {
                    id:windowEntry;required property var modelData
                    width:ListView.view.width;height:47*bar.u;hoverEnabled:true
                    onClicked:{appsPopup.close();bar.action({action:'focus',address:modelData.address});}
                    contentItem:Column {
                        Label { width:parent.width;height:22*bar.u;text:windowEntry.modelData.title;color:windowEntry.modelData.active?bar.shell.accent:bar.shell.ink }
                        Label { width:parent.width;height:17*bar.u;text:windowEntry.modelData.app+' · workspace '+windowEntry.modelData.workspace;opacity:.65;font.pixelSize:bar.shell.fontSize*.7 }
                    }
                    background:Rectangle { color:windowEntry.hovered || windowEntry.modelData.active?bar.shell.tint(bar.shell.accent,.15):'transparent';radius:3*bar.u }
                }
                ScrollBar.vertical:Basic.ScrollBar { }
            }
        }
    }
}


