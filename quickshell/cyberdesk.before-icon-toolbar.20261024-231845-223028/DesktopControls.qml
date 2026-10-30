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
    Chip {
        id:audioButton;x:0;width:120*bar.u
        text:!bar.audio.available?'Audio N/A':bar.audio.muted?'Audio muted':('Audio '+bar.audio.volume+'%')
        onClicked:{appsPopup.close();audioPopup.visible?audioPopup.close():audioPopup.open();}
        ToolTip.visible:hovered
        ToolTip.text:'Click: outputs and volume · Right-click: pavucontrol · Scroll: volume'
        MouseArea {
            anchors.fill:parent;acceptedButtons:Qt.RightButton
            onClicked:bar.action({action:'pavucontrol'})
            onWheel:wheel=>{if(wheel.angleDelta.y!==0){bar.action({action:'step',value:wheel.angleDelta.y>0?5:-5});wheel.accepted=true;}}
        }
    }
    Chip {
        id:appsButton;x:audioButton.width+8*bar.u;width:87*bar.u
        text:'Apps '+bar.windows.length+' ▾'
        onClicked:{audioPopup.close();appsPopup.visible?appsPopup.close():appsPopup.open();}
    }
    Flickable {
        id:trayFlick;x:appsButton.x+appsButton.width+9*bar.u;y:0;width:Math.max(0,parent.width-x);height:32*bar.u
        clip:true;contentWidth:trayRow.width;contentHeight:height;boundsBehavior:Flickable.StopAtBounds
        flickableDirection:Flickable.HorizontalFlick
        Row {
            id:trayRow;height:parent.height;spacing:5*bar.u
            Repeater {
                model:SystemTray.items
                delegate:Rectangle {
                    id:trayIcon
                    required property var modelData
                    width:29*bar.u;height:30*bar.u
                    color:trayMouse.containsMouse?bar.shell.tint(bar.shell.accent,.12):'transparent'
                    radius:4*bar.u
                    Image { anchors.centerIn:parent;width:21*bar.u;height:21*bar.u;source:trayIcon.modelData.icon;sourceSize.width:width;sourceSize.height:height;fillMode:Image.PreserveAspectFit }
                    QsMenuAnchor { id:trayMenu;anchor.item:trayIcon;menu:trayIcon.modelData.menu }
                    ToolTip.visible:trayMouse.containsMouse
                    ToolTip.text:trayIcon.modelData.tooltipTitle || trayIcon.modelData.title || trayIcon.modelData.id
                    MouseArea {
                        id:trayMouse;anchors.fill:parent;hoverEnabled:true
                        acceptedButtons:Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked:mouse=>{
                            if(mouse.button===Qt.MiddleButton)trayIcon.modelData.secondaryActivate();
                            else if(mouse.button===Qt.RightButton || trayIcon.modelData.onlyMenu){if(trayIcon.modelData.hasMenu)trayMenu.open();}
                            else trayIcon.modelData.activate();
                        }
                        onWheel:wheel=>trayIcon.modelData.scroll(wheel.angleDelta.y/120,false)
                    }
                }
            }
        }
        Label { visible:trayRow.width===0;anchors.verticalCenter:parent.verticalCenter;width:parent.width;text:'Tray empty';opacity:.55;font.pixelSize:bar.shell.fontSize*.73 }
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
