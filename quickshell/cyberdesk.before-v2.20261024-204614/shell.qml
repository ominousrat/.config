import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var cfg: ({accent:'#26cbe8',background:'#041820',text:'#b6e7f5',opacity:0.7,panel_width:360,top_margin:54,bottom_margin:20,monitor:''})
    property var stats: ({cpu:0,memory:0,memory_text:'',gpu:{usage:null,temp:null,vram:''},disks:[],uptime:0})
    property var messages: []
    property var models: []
    property var swatches: []
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property string stream: ''
    property string error: ''
    property string performance: ''
    property bool busy: false
    property bool settingsOpen: false
    property color accent: cfg.accent
    property color ink: cfg.text
    property color glass: Qt.rgba(Qt.color(cfg.background).r,Qt.color(cfg.background).g,Qt.color(cfg.background).b,cfg.opacity)
    property var targetScreen: {
        for (let s of Quickshell.screens) if (s.name === cfg.monitor) return s;
        return Quickshell.screens.length ? Quickshell.screens[0] : null;
    }
    function send(o) { backend.write(JSON.stringify(o)+'\n'); }
    function setting(k,v) { let o={}; o[k]=v; send({op:'settings',values:o}); }
    function appendSample(a,v) { return a.concat([v === null ? 0 : v]).slice(-120); }
    function submit() {
        if (busy || !entry.text.trim()) return;
        let text=entry.text; entry.clear(); busy=true; error=''; performance='';
        send({op:'chat',text:text});
    }
    function receive(d) {
        if(d.type==='config') cfg=d.config;
        else if(d.type==='metrics') {
            stats=d; cpuHistory=appendSample(cpuHistory,d.cpu);
            memHistory=appendSample(memHistory,d.memory); gpuHistory=appendSample(gpuHistory,d.gpu.usage);
        } else if(d.type==='history') { messages=d.messages; stream=''; }
        else if(d.type==='begin') { busy=true; stream=''; }
        else if(d.type==='delta') stream+=d.text;
        else if(d.type==='done') busy=false;
        else if(d.type==='error') error=d.error;
        else if(d.type==='models') { models=d.models; error=d.error; }
        else if(d.type==='palette') swatches=d.colors;
        else if(d.type==='performance') performance=d.text;
    }
    Process {
        id: backend
        command: ['python3','-u',Quickshell.shellPath('backend.py')]
        stdinEnabled: true
        running: true
        stdout: SplitParser { onRead: data => { try { root.receive(JSON.parse(data)); } catch(e) { root.error=String(e); } } }
        stderr: SplitParser { onRead: data => console.warn(data) }
        onExited: (code,status) => { root.error='Backend stopped ('+code+'). Restart Quickshell and check terminal output.'; root.busy=false; }
    }
    component Label: Text {
        color: root.ink
        font.family: 'monospace'
        font.pixelSize: 13
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Frame: Rectangle {
        color: root.glass
        border.color: Qt.rgba(root.accent.r,root.accent.g,root.accent.b,0.65)
        border.width: 1
        radius: 3
    }
    component Action: Button {
        id: control
        palette.buttonText: root.ink
        contentItem: Text { text: control.text; color: control.enabled ? root.ink : '#667780'; font.family:'monospace'; font.pixelSize:12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { color: control.down ? Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.25) : '#142b3640'; border.color:root.accent; radius:3 }
    }
    component Field: TextField {
        color: root.ink
        font.family:'monospace'
        selectByMouse:true
        background: Rectangle { color:'#38000000'; border.color:root.accent; radius:3 }
    }
    component Chart: Canvas {
        id: chartCanvas
        property var values: []
        onValuesChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let c=getContext('2d'); c.reset();
            c.strokeStyle=Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.18);
            for(let i=1;i<4;i++){ c.beginPath();c.moveTo(0,height*i/4);c.lineTo(width,height*i/4);c.stroke(); }
            if(values.length<2)return;
            c.strokeStyle=root.accent; c.lineWidth=1.5;c.beginPath();
            for(let i=0;i<values.length;i++){
                let x=i*width/(values.length-1), y=height*(1-values[i]/100);
                if(i===0)c.moveTo(x,y);else c.lineTo(x,y);
            }
            c.stroke();
        }
        Connections { target:root; function onAccentChanged(){chartCanvas.requestPaint();} }
    }
    PanelWindow {
        id: chatPanel
        screen: root.targetScreen
        anchors { left:true;top:true;bottom:true }
        margins { left:18;top:root.cfg.top_margin;bottom:root.cfg.bottom_margin }
        implicitWidth:root.cfg.panel_width
        color:'transparent'
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.namespace:'cyberdesk-chat'
        WlrLayershell.layer:WlrLayer.Top
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
        Frame { anchors.fill:parent }
        ColumnLayout {
            anchors.fill:parent;anchors.margins:14;spacing:12
            RowLayout {
                Layout.fillWidth:true
                Label { text:'[≡] LOCAL AI';color:root.accent;Layout.fillWidth:true }
                Action { text:'New';enabled:!root.busy;onClicked:root.send({op:'new'}) }
                Action { text:root.settingsOpen ? 'Chat':'Setup';onClicked:{root.settingsOpen=!root.settingsOpen;} }
            }
            Label { text:root.cfg.model || 'Select a model in Setup';font.pixelSize:11;Layout.fillWidth:true }
            ScrollView {
                id:scroll
                visible:!root.settingsOpen
                Layout.fillHeight:true;Layout.fillWidth:true;clip:true
                contentWidth:availableWidth
                Column {
                    width:scroll.availableWidth;spacing:12
                    Repeater {
                        model:root.messages
                        delegate: Rectangle {
                            required property var modelData
                            width:parent.width
                            height:messageText.implicitHeight+30
                            color:modelData.role==='user' ? Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.10) : 'transparent'
                            radius:3
                            Label { id:messageText;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:10;text:(modelData.role==='user'?'You':'Assistant')+'\n'+modelData.content }
                        }
                    }
                    Label { width:parent.width;visible:root.busy;text:'Assistant\n'+(root.stream || 'Waiting for model…') }
                    onHeightChanged: Qt.callLater(function(){ if(scroll.contentItem && scroll.contentItem.contentHeight !== undefined) scroll.contentItem.contentY=Math.max(0,scroll.contentItem.contentHeight-scroll.height); })
                }
            }
            ScrollView {
                id:settingsScroll
                visible:root.settingsOpen
                Layout.fillHeight:true;Layout.fillWidth:true;contentWidth:availableWidth;clip:true
                ColumnLayout {
                    width:settingsScroll.availableWidth;spacing:9
                    Label { text:'Ollama server URL' }
                    Field { Layout.fillWidth:true;text:root.cfg.ollama_url || '';onEditingFinished:root.setting('ollama_url',text) }
                    Action { text:'Connect / refresh models';onClicked:root.send({op:'models'}) }
                    ComboBox { Layout.fillWidth:true;model:root.models;onActivated:root.setting('model',currentText) }
                    Label { text:'Current: '+(root.cfg.model||'none');Layout.fillWidth:true }
                    Label { text:'Accent / background / text (hex)' }
                    Repeater {
                        model:['accent','background','text']
                        delegate:Field { required property string modelData;Layout.fillWidth:true;text:root.cfg[modelData];onEditingFinished:{if(/^#[0-9a-fA-F]{6}$/.test(text))root.setting(modelData,text);} }
                    }
                    Label { text:'Panel opacity: '+Math.round(root.cfg.opacity*100)+'%' }
                    Slider { Layout.fillWidth:true;from:.1;to:1;value:root.cfg.opacity;onMoved:root.setting('opacity',value) }
                    CheckBox { text:'Auto colors from hyprpaper';checked:root.cfg.auto_palette || false;palette.windowText:root.ink;onClicked:root.setting('auto_palette',checked) }
                    RowLayout {
                        Action { text:'Palette';onClicked:root.send({op:'palette'}) }
                        Action { text:'Pick pixel';onClicked:root.send({op:'pick'}) }
                    }
                    Flow {
                        Layout.fillWidth:true;spacing:5
                        Repeater {
                            model:root.swatches
                            delegate:Rectangle {
                                required property string modelData
                                width:28;height:28;color:modelData;border.color:root.ink;radius:3
                                MouseArea { anchors.fill:parent;onClicked:root.send({op:'settings',values:{accent:parent.modelData,auto_palette:false}}) }
                            }
                        }
                    }
                    Label { text:'Wallpaper fallback (absolute path)';Layout.fillWidth:true }
                    Field { Layout.fillWidth:true;text:root.cfg.wallpaper || '';onEditingFinished:root.setting('wallpaper',text) }
                    Label { text:'Monitor name (empty = first screen)' }
                    Field { Layout.fillWidth:true;text:root.cfg.monitor || '';onEditingFinished:root.setting('monitor',text) }
                    Label { text:'Panel width' }
                    SpinBox { from:280;to:650;value:root.cfg.panel_width;onValueModified:root.setting('panel_width',value) }
                    Label { text:'Settings save automatically. Chat is stored locally as plain text. AI has no shell access.';Layout.fillWidth:true }
                }
            }
            Label { visible:root.error!=='';text:root.error;color:'#ff9b9b';Layout.fillWidth:true;font.pixelSize:11 }
            Label { visible:root.performance!=='';text:root.performance;font.pixelSize:11;Layout.fillWidth:true }
            RowLayout {
                visible:!root.settingsOpen;Layout.fillWidth:true
                Field { id:entry;Layout.fillWidth:true;placeholderText:'Type a message…';enabled:!root.busy;onAccepted:root.submit() }
                Action { text:'Send';enabled:!root.busy;onClicked:root.submit() }
            }
        }
    }
    PanelWindow {
        screen:root.targetScreen
        anchors { top:true }
        margins.top:12
        implicitWidth:240;implicitHeight:76
        color:'transparent';exclusionMode:ExclusionMode.Ignore
        WlrLayershell.namespace:'cyberdesk-clock'
        WlrLayershell.layer:WlrLayer.Top
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        Frame { anchors.fill:parent }
        SystemClock { id:clock;precision:SystemClock.Minutes }
        Column {
            anchors.centerIn:parent;spacing:1
            Label { anchors.horizontalCenter:parent.horizontalCenter;text:Qt.formatDateTime(clock.date,'HH:mm');font.pixelSize:32;color:root.accent }
            Label { anchors.horizontalCenter:parent.horizontalCenter;text:Qt.formatDateTime(clock.date,'ddd, dd MMM') }
        }
    }
    PanelWindow {
        screen:root.targetScreen
        anchors { right:true;top:true;bottom:true }
        margins { right:18;top:root.cfg.top_margin;bottom:root.cfg.bottom_margin }
        implicitWidth:root.cfg.panel_width
        color:'transparent';exclusionMode:ExclusionMode.Ignore
        WlrLayershell.namespace:'cyberdesk-stats'
        WlrLayershell.layer:WlrLayer.Top
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        Frame { anchors.fill:parent }
        ColumnLayout {
            anchors.fill:parent;anchors.margins:18;spacing:10
            Label { text:'CachyOS / LIVE SYSTEM';font.pixelSize:19;color:root.accent }
            Label { text:'Ryzen 5 7600X\nRadeon RX 9060 XT · 16 GB\nHyprland · '+root.stats.uptime+' min uptime';Layout.fillWidth:true }
            Label { text:'CPU   '+root.stats.cpu.toFixed(0)+'%';color:root.accent }
            Chart { Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:35;values:root.cpuHistory }
            Label { text:'RAM   '+root.stats.memory_text+'  ('+root.stats.memory.toFixed(0)+'%)';Layout.fillWidth:true }
            Chart { Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:35;values:root.memHistory }
            Label { text:'GPU   '+(root.stats.gpu.usage===null?'N/A':root.stats.gpu.usage.toFixed(0)+'%')+'\nVRAM  '+root.stats.gpu.vram;Layout.fillWidth:true }
            Chart { Layout.fillWidth:true;Layout.fillHeight:true;Layout.minimumHeight:35;values:root.gpuHistory }
            Label { text:'TEMPERATURES';color:root.accent }
            Label { text:'CPU '+(root.stats.cpu_temp===undefined || root.stats.cpu_temp===null?'N/A':root.stats.cpu_temp.toFixed(0)+' °C')+'   GPU '+(root.stats.gpu.temp===null?'N/A':root.stats.gpu.temp.toFixed(0)+' °C');Layout.fillWidth:true }
            Label { text:root.stats.disks.join('\n');Layout.fillWidth:true }
            Label { text:'History: last 2 minutes · 1 Hz\nMetrics are from this PC, not the AI server.';font.pixelSize:10;Layout.fillWidth:true }
        }
    }
}
