//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var desktop: ({audio:{available:false,volume:0,muted:false,default:'',sinks:[],error:''},windows:[],window_error:''})
    property var cfg: ({accent:'#75d8f4',secondary:'#20dfc5',background:'#03131f',text:'#b4e6f7',opacity:.74,panel_ratio:.265,font_scale:1,monitor:'',layer:'bottom',top_margin:16,bottom_margin:16})
    property var monitorScreen: {
        for(let s of Quickshell.screens) if(s.name===cfg.monitor)return s;
        return Quickshell.screens.length ? Quickshell.screens[0] : null;
    }
    property real u: monitorScreen ? Math.max(.75,Math.min(2,monitorScreen.height/1000)) : 1
    property real fontSize: 14*u*(cfg.font_scale || 1)
    property real panelWidth: monitorScreen ? monitorScreen.width*cfg.panel_ratio : 450
    property color accent: cfg.accent
    property color secondary: cfg.secondary
    property color ink: cfg.text
    property color bg: cfg.background
    property color glass: Qt.rgba(bg.r,bg.g,bg.b,cfg.opacity)
    property var info: ({cpu:'Detecting…',host:'',kernel:'',os:'CachyOS',wm:'Hyprland',packages:null,gpu_name:'Detecting…',devices:[]})
    property var stats: ({cpu:0,cpu_temp:null,memory:0,memory_text:'—',gpu:{usage:null,temp:null,total:0,used:0,card:'',pci:''},disks:[],uptime:0})
    property var cpuHistory: []
    property var memoryHistory: []
    property var gpuHistory: []
    property var cpuTemps: []
    property var gpuTemps: []
    property var messages: []
    property var chats: []
    property var modelNames: []
    property var swatches: []
    // cyberdesk-chart-controls-v1
    property int sampleTotal: 0
    property int chartColumns: Math.max(4,Math.min(120,Math.round(Number(cfg.chart_columns)||32)))
    property int chartRows: Math.max(3,Math.min(40,Math.round(Number(cfg.chart_rows)||14)))
    property int chartSeconds: Math.max(30,Math.min(3600,Math.round(Number(cfg.chart_seconds)||300)))
    property int chartWindow: Math.max(chartSeconds,chartColumns)
    property string activeChat: ''
    property string stream: ''
    property string error: ''
    property string perf: ''
    property string page: 'chat'
    property bool menuOpen: false
    property bool busy: false
    property bool connected: false
    function tint(c,a){return Qt.rgba(c.r,c.g,c.b,a);}
    function send(o){backend.write(JSON.stringify(o)+'\n');}
    function set(k,v){let d={};d[k]=v;send({op:'settings',values:d});}
    function history(a,v){return a.concat([v]).slice(-4600);}
    function windowLabel(sec){
        if(sec<90)return '-'+sec+' s';
        let minutes=Math.round(sec/6)/10;
        return '-'+(minutes%1===0?minutes.toFixed(0):minutes.toFixed(1))+' min';
    }
    function percent(v){return v===null || v===undefined ? 'N/A' : Math.round(v)+'%';}
    function temp(v){return v===null || v===undefined ? 'N/A' : Math.round(v)+'°C';}
    function scrollDown(){Qt.callLater(function(){chatFlick.contentY=Math.max(0,chatFlick.contentHeight-chatFlick.height);});}
    function submit(){
        if(busy || !entry.text.trim())return;
        let text=entry.text.trim();entry.clear();busy=true;error='';perf='';send({op:'chat',text:text});
    }
    function receive(d){
        if(d.type==='desktop'){desktop=d;return;}
        if(d.type==='config')cfg=d.config;
        else if(d.type==='system')info=d.info;
        else if(d.type==='metrics'){
            stats=d;sampleTotal+=1;cpuHistory=history(cpuHistory,d.cpu);memoryHistory=history(memoryHistory,d.memory);
            gpuHistory=history(gpuHistory,d.gpu.usage);cpuTemps=history(cpuTemps,d.cpu_temp);gpuTemps=history(gpuTemps,d.gpu.temp);
        }else if(d.type==='history'){messages=d.messages;chats=d.chats;activeChat=d.active;stream='';scrollDown();}
        else if(d.type==='begin'){busy=true;stream='';}
        else if(d.type==='delta'){stream+=d.text;scrollDown();}
        else if(d.type==='done')busy=false;
        else if(d.type==='error')error=d.error;
        else if(d.type==='models'){modelNames=d.models;connected=d.connected;}
        else if(d.type==='palette')swatches=d.colors;
        else if(d.type==='performance')perf=d.text;
    }
    Process {
        id:backend
        command:['python3','-u',Quickshell.shellPath('backend.py')]
        running:true
        stdinEnabled:true
        stdout:SplitParser { onRead:data=>{try{root.receive(JSON.parse(data));}catch(e){root.error=String(e);}} }
        stderr:SplitParser { onRead:data=>console.warn(data) }
        onExited:(code,status)=>{root.error='Backend stopped ('+code+'). Check terminal output.';root.busy=false;}
    }
    SystemClock { id:clock;precision:SystemClock.Minutes }
    component Txt: Text {
        color:root.ink
        font.family:'monospace'
        font.pixelSize:root.fontSize
        textFormat:Text.PlainText
        wrapMode:Text.Wrap
    }
    component Line: Rectangle {
        height:1;color:root.tint(root.accent,.25)
    }
    component Frame: Item {
        Rectangle { anchors.fill:parent;anchors.margins:3*root.u;color:root.glass;border.color:root.tint(root.accent,.37);border.width:1;z:-2 }
        Canvas {
            id:edge;anchors.fill:parent;z:8
            onWidthChanged:requestPaint()
            onHeightChanged:requestPaint()
            Connections { target:root;function onAccentChanged(){edge.requestPaint();} }
            onPaint:{
                let c=getContext('2d');c.reset();c.clearRect(0,0,width,height);
                let p=3*root.u,l=15*root.u,w=width,h=height;
                c.lineWidth=1;c.strokeStyle=root.tint(root.accent,.75);c.beginPath();
                for(let x of [p,w-p])for(let y of [p,h-p]){
                    let sx=x<w/2?1:-1,sy=y<h/2?1:-1;
                    c.moveTo(x+sx*l,y);c.lineTo(x,y);c.lineTo(x,y+sy*l);
                    c.moveTo(x-3*root.u,y);c.lineTo(x+3*root.u,y);
                    c.moveTo(x,y-3*root.u);c.lineTo(x,y+3*root.u);
                }
                c.stroke();c.strokeStyle=root.tint(root.accent,.23);c.beginPath();
                for(let x=25*root.u;x<w-25*root.u;x+=12*root.u){c.moveTo(x,p);c.lineTo(Math.min(x+6*root.u,w-25*root.u),p);c.moveTo(x,h-p);c.lineTo(Math.min(x+6*root.u,w-25*root.u),h-p);}
                for(let y=25*root.u;y<h-25*root.u;y+=12*root.u){c.moveTo(p,y);c.lineTo(p,Math.min(y+6*root.u,h-25*root.u));c.moveTo(w-p,y);c.lineTo(w-p,Math.min(y+6*root.u,h-25*root.u));}
                c.stroke();
            }
        }
    }
    component Btn: Button {
        id:b
        implicitHeight:30*root.u
        implicitWidth:Math.max(54*root.u,buttonText.implicitWidth+18*root.u)
        padding:5*root.u
        contentItem:Text { id:buttonText;text:b.text;font.family:'monospace';font.pixelSize:root.fontSize*.86;color:b.enabled?root.ink:root.tint(root.ink,.4);horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter }
        background:Rectangle { color:root.tint(root.accent,b.down?.22:b.hovered?.12:.04);border.color:root.tint(root.accent,.65);radius:3*root.u }
    }
    component Input: TextField {
        height:34*root.u
        color:root.ink;placeholderTextColor:root.tint(root.ink,.5)
        font.family:'monospace';font.pixelSize:root.fontSize
        selectByMouse:true
        leftPadding:10*root.u;rightPadding:10*root.u
        background:Rectangle { color:root.tint(root.bg,.45);border.color:root.tint(root.accent,.65);radius:3*root.u }
    }
    component Bars: Canvas {
        id:barCanvas
        property var values:[]
        function columnAverage(values,total,col,columns,seconds){
            if(col<0)return null;
            let first=total-values.length;
            let begin=Math.floor((col*seconds+columns-1)/columns);
            let end=Math.floor(((col+1)*seconds+columns-1)/columns);
            let sum=0,count=0;
            for(let sample=begin;sample<end;sample++){
                let index=sample-first;
                if(index>=0 && index<values.length && values[index]!==null && values[index]!==undefined){sum+=values[index];count++;}
            }
            return count?sum/count:null;
        }
        onValuesChanged:requestPaint()
        onWidthChanged:requestPaint()
        onHeightChanged:requestPaint()
        Connections {
            target:root
            function onAccentChanged(){barCanvas.requestPaint();}
            function onSecondaryChanged(){barCanvas.requestPaint();}
            function onSampleTotalChanged(){barCanvas.requestPaint();}
            function onChartColumnsChanged(){barCanvas.requestPaint();}
            function onChartRowsChanged(){barCanvas.requestPaint();}
            function onChartWindowChanged(){barCanvas.requestPaint();}
        }
        onPaint:{
            let c=getContext('2d');c.reset();c.clearRect(0,0,width,height);
            if(width<=0 || height<=0)return;
            let columns=root.chartColumns,rows=root.chartRows,seconds=root.chartWindow;
            let gap=Math.min(5*root.u,width/columns*.35),bw=Math.max(1,(width-gap*(columns-1))/columns);
            let bh=height/rows,seg=Math.max(1,bh-Math.min(3*root.u,bh*.35));
            let accentRows=Math.max(1,Math.round(rows*3/14));
            let lastColumn=Math.floor(root.sampleTotal*columns/seconds)-1;
            for(let i=0;i<columns;i++){
                let value=columnAverage(values,root.sampleTotal,lastColumn-(columns-1-i),columns,seconds);
                let lit=value===null?0:Math.max(0,Math.min(rows,Math.floor(value/100*rows+.75)));
                for(let r=0;r<rows;r++){
                    c.fillStyle=r<lit?(r<accentRows?root.secondary:root.accent):root.tint(root.accent,.13);
                    c.fillRect(i*(bw+gap),height-(r+1)*bh,bw,seg);
                }
            }
        }
    }
    component Usage: Item {
        id:usage
        property string title:''
        property string detail:''
        property var values:[]
        Txt { x:0;y:0;text:usage.title;font.pixelSize:root.fontSize*1.05 }
        Txt { anchors.right:parent.right;y:0;text:usage.detail;font.pixelSize:root.fontSize*.95 }
        Bars { x:0;y:31*root.u;width:parent.width;height:Math.max(20*root.u,parent.height-61*root.u);values:usage.values }
        Txt { x:0;anchors.bottom:parent.bottom;anchors.bottomMargin:8*root.u;text:root.windowLabel(root.chartWindow);font.pixelSize:root.fontSize*.82 }
        Txt { anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.bottomMargin:8*root.u;text:'now';font.pixelSize:root.fontSize*.82 }
        Line { anchors.bottom:parent.bottom;width:parent.width }
    }
    // cyberdesk-layout-v22
    component KV: Item {
        id:kv
        property string label:''
        property string value:''
        height:root.fontSize*1.32
        Txt { x:0;width:kv.width*.30;height:kv.height;verticalAlignment:Text.AlignVCenter;text:kv.label;color:root.accent;font.pixelSize:root.fontSize*.78;wrapMode:Text.NoWrap;elide:Text.ElideRight }
        Txt { x:kv.width*.30;width:kv.width*.70;height:kv.height;verticalAlignment:Text.AlignVCenter;text:kv.value;font.pixelSize:root.fontSize*.78;wrapMode:Text.NoWrap;elide:Text.ElideRight }
    }
    component TempPlot: Canvas {
        id:plot
        onWidthChanged:requestPaint()
        onHeightChanged:requestPaint()
        Connections {
            target:root
            function onCpuTempsChanged(){plot.requestPaint();}
            function onAccentChanged(){plot.requestPaint();}
            function onSecondaryChanged(){plot.requestPaint();}
            function onChartWindowChanged(){plot.requestPaint();}
        }
        onPaint:{
            let c=getContext('2d');c.reset();c.clearRect(0,0,width,height);
            let left=31*root.u,top=6*root.u,bottom=height-23*root.u,w=width-left-5*root.u,h=bottom-top;
            let seconds=Math.max(2,root.chartWindow);
            c.font=(root.fontSize*.8)+'px monospace';c.fillStyle=root.ink;c.strokeStyle=root.tint(root.accent,.18);c.lineWidth=1;
            for(let t of [20,40,60,80,100]){
                let y=bottom-(t-20)/80*h;c.fillText(String(t),0,y+4*root.u);
                c.beginPath();c.moveTo(left,y);c.lineTo(left+w,y);c.stroke();
            }
            c.strokeStyle=root.tint(root.ink,.6);c.beginPath();c.moveTo(left,top);c.lineTo(left,bottom);c.lineTo(left+w,bottom);c.stroke();
            function draw(samples,color){
                let a=samples.length>seconds?samples.slice(samples.length-seconds):samples;
                c.strokeStyle=color;c.lineWidth=1.4*root.u;c.beginPath();let started=false;
                for(let i=0;i<a.length;i++){
                    if(a[i]===null || a[i]===undefined){started=false;continue;}
                    let x=left+(seconds-a.length+i)/(seconds-1)*w,y=bottom-(Math.max(20,Math.min(100,a[i]))-20)/80*h;
                    if(!started){c.moveTo(x,y);started=true;}else c.lineTo(x,y);
                }c.stroke();
            }
            draw(root.cpuTemps,root.accent);draw(root.gpuTemps,root.secondary);
            c.fillStyle=root.ink;c.fillText(root.windowLabel(root.chartWindow),left,height-3*root.u);c.fillText('now',left+w-25*root.u,height-3*root.u);
        }
    }
    PanelWindow {
        id:leftPanel
        screen:root.monitorScreen
        anchors { left:true;top:true;bottom:true }
        margins { left:root.cfg.left_margin===undefined?14:root.cfg.left_margin;top:root.cfg.top_margin;bottom:root.cfg.bottom_margin }
        implicitWidth:root.panelWidth
        color:'transparent';exclusionMode:ExclusionMode.Ignore
        WlrLayershell.namespace:'cyberdesk-chat'
        WlrLayershell.layer:root.cfg.layer==='top'?WlrLayer.Top:WlrLayer.Bottom
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
        Frame { anchors.fill:parent }
        Item {
            x:15*root.u;y:13*root.u;width:parent.width-30*root.u;height:31*root.u
            // cyberdesk-header-menu-v21
            Item {
                height:parent.height;width:155*root.u
                Btn {
                    id:burger
                    x:0;anchors.verticalCenter:parent.verticalCenter
                    width:29*root.u;height:29*root.u
                    text:'☰'
                    onClicked:root.menuOpen=!root.menuOpen
                    ToolTip.visible:hovered
                    ToolTip.text:root.menuOpen?'Close menu':'Chat menu'
                }
                Txt {
                    x:36*root.u;anchors.verticalCenter:parent.verticalCenter
                    text:'Local AI';font.pixelSize:root.fontSize*1.07
                }
            }
            Row {
                anchors.centerIn:parent;spacing:6*root.u
                Rectangle { width:7*root.u;height:7*root.u;radius:width/2;color:root.connected?root.secondary:root.tint(root.ink,.4);anchors.verticalCenter:parent.verticalCenter }
                Txt { text:root.connected?'connected: ai-pc':'not connected';font.pixelSize:root.fontSize*.76 }
            }
            Btn { anchors.right:parent.right;height:28*root.u;text:'[+ New chat]';enabled:!root.busy;onClicked:{root.send({op:'new'});root.page='chat';} }
        }
        Line { x:15*root.u;y:50*root.u;width:parent.width-30*root.u }
        // OPEN button removed; header burger is the only menu toggle.
        Txt { x:22*root.u;y:65*root.u;width:parent.width-x-22*root.u;text:root.cfg.model || 'Choose a model in Settings';elide:Text.ElideRight;wrapMode:Text.NoWrap;font.pixelSize:root.fontSize*.75;color:root.tint(root.ink,.7) }
        Flickable {
            id:chatFlick
            visible:root.page==='chat'
            x:22*root.u;y:100*root.u;width:parent.width-44*root.u;height:parent.height-y-108*root.u
            clip:true;contentWidth:width;contentHeight:conversation.height;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar { policy:ScrollBar.AsNeeded }
            Column {
                id:conversation;width:chatFlick.width;spacing:17*root.u
                Item {
                    width:parent.width;height:root.messages.length || root.busy ? 0 : 83*root.u;visible:height>0
                    Txt { width:parent.width;text:'Local chat is ready.\nOpen Settings to connect your AI PC.';color:root.tint(root.ink,.65);font.pixelSize:root.fontSize*.95 }
                }
                Repeater {
                    model:root.messages
                    delegate:Item {
                        id:msg
                        required property var modelData
                        property bool user:modelData.role==='user'
                        width:conversation.width;height:body.implicitHeight+48*root.u
                        Rectangle { x:msg.user?parent.width*.25:0;width:msg.user?parent.width*.75:parent.width;height:parent.height;color:msg.user?root.tint(root.accent,.10):'transparent';border.color:msg.user?root.tint(root.accent,.65):'transparent';radius:5*root.u }
                        Rectangle { visible:!msg.user;x:0;y:22*root.u;width:1;height:parent.height-24*root.u;color:root.tint(root.accent,.65) }
                        Txt { visible:!msg.user;x:0;y:0;text:'Assistant';color:root.accent;font.pixelSize:root.fontSize*.95 }
                        Txt { id:body;x:msg.user?parent.width*.25+11*root.u:11*root.u;y:msg.user?11*root.u:26*root.u;width:(msg.user?parent.width*.75:parent.width)-22*root.u;text:msg.modelData.content;lineHeight:1.15 }
                        Txt { anchors.right:parent.right;anchors.rightMargin:9*root.u;anchors.bottom:parent.bottom;anchors.bottomMargin:5*root.u;text:(msg.modelData.time || '')+(msg.user?' ✓✓':'');font.pixelSize:root.fontSize*.72;color:root.tint(root.accent,.7) }
                    }
                }
                Item {
                    visible:root.busy;width:parent.width;height:visible?streamText.implicitHeight+33*root.u:0
                    Txt { text:'Assistant';color:root.accent }
                    Txt { id:streamText;y:25*root.u;x:11*root.u;width:parent.width-x;text:root.stream || 'Waiting for model…';lineHeight:1.15 }
                }
            }
        }
        Flickable {
            id:historyView;visible:root.page==='history'
            x:22*root.u;y:100*root.u;width:parent.width-44*root.u;height:parent.height-y-35*root.u;clip:true;contentHeight:historyColumn.height;contentWidth:width
            Column {
                id:historyColumn;width:historyView.width;spacing:10*root.u
                Txt { text:'Chat history';font.pixelSize:root.fontSize*1.2;color:root.accent }
                Repeater {
                    model:root.chats
                    delegate:Btn { required property var modelData;width:historyColumn.width;text:modelData.title;enabled:!root.busy;onClicked:{root.send({op:'switch',id:modelData.id});root.page='chat';} }
                }
            }
        }
        Flickable {
            id:setup;visible:root.page==='settings'
            x:22*root.u;y:100*root.u;width:parent.width-44*root.u;height:parent.height-y-30*root.u;clip:true;contentWidth:width;contentHeight:settingsColumn.height
            ScrollBar.vertical:ScrollBar { policy:ScrollBar.AsNeeded }
            Column {
                id:settingsColumn;width:setup.width;spacing:10*root.u
                Txt { text:'Connection';color:root.accent;font.pixelSize:root.fontSize*1.2 }
                Txt { text:'Ollama server URL' }
                Input { id:urlField;width:parent.width;text:root.cfg.ollama_url || '';onEditingFinished:root.set('ollama_url',text) }
                Btn { text:'Connect / refresh models';onClicked:{root.set('ollama_url',urlField.text);root.error='';root.send({op:'models'});} }
                // cyberdesk-color-controls-v24
                Basic.ComboBox {
                    id:modelSelect
                    width:parent.width;height:38*root.u
                    model:root.modelNames
                    currentIndex:root.modelNames.indexOf(root.cfg.model || '')
                    font.family:'monospace';font.pixelSize:root.fontSize*.95
                    leftPadding:11*root.u;rightPadding:32*root.u
                    hoverEnabled:true
                    onActivated:root.set('model',currentText)
                    contentItem:Text {
                        text:modelSelect.currentText || root.cfg.model || 'Select a model…'
                        color:root.ink;font:modelSelect.font
                        verticalAlignment:Text.AlignVCenter
                        elide:Text.ElideRight
                    }
                    indicator:Text {
                        x:modelSelect.width-width-11*root.u
                        anchors.verticalCenter:parent.verticalCenter
                        text:modelSelect.popup.visible?'▴':'▾'
                        color:root.accent;font.pixelSize:root.fontSize
                    }
                    background:Rectangle {
                        color:root.tint(root.bg,.85)
                        border.color:root.tint(root.accent,modelSelect.activeFocus || modelSelect.hovered?1:.65)
                        border.width:modelSelect.activeFocus?2:1
                        radius:3*root.u
                    }
                    delegate:Basic.ItemDelegate {
                        id:modelOption
                        required property var modelData
                        required property int index
                        width:modelSelect.width-8*root.u;height:36*root.u
                        highlighted:modelSelect.highlightedIndex===index
                        hoverEnabled:true
                        leftPadding:10*root.u;rightPadding:10*root.u
                        contentItem:Text {
                            text:String(modelOption.modelData)
                            color:modelOption.index===modelSelect.currentIndex?root.accent:root.ink
                            font:modelSelect.font;elide:Text.ElideRight
                            verticalAlignment:Text.AlignVCenter
                        }
                        background:Rectangle {
                            color:modelOption.highlighted || modelOption.hovered?root.tint(root.accent,.20):modelOption.index===modelSelect.currentIndex?root.tint(root.accent,.09):'transparent'
                            radius:2*root.u
                        }
                    }
                    popup:Popup {
                        y:modelSelect.height+4*root.u
                        width:modelSelect.width
                        height:Math.min(248*root.u,Math.max(40*root.u,root.modelNames.length*36*root.u+8*root.u))
                        padding:4*root.u
                        popupType:Popup.Item
                        closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background:Rectangle {
                            color:root.tint(root.bg,.98)
                            border.color:root.tint(root.accent,.85)
                            radius:3*root.u
                        }
                        contentItem:ListView {
                            clip:true
                            model:modelSelect.popup.visible?modelSelect.delegateModel:null
                            currentIndex:modelSelect.highlightedIndex
                            boundsBehavior:Flickable.StopAtBounds
                            ScrollBar.vertical:Basic.ScrollBar {
                                contentItem:Rectangle { implicitWidth:4*root.u;implicitHeight:25*root.u;color:root.tint(root.accent,.6);radius:2*root.u }
                            }
                        }
                    }
                }
                Txt { width:parent.width;text:'Selected: '+(root.cfg.model || 'none');font.pixelSize:root.fontSize*.85 }
                Line { width:parent.width }
                Txt { text:'Appearance';color:root.accent;font.pixelSize:root.fontSize*1.2 }
                Repeater {
                    model:['accent','secondary','background','text']
                    delegate:Item {
                        id:colorRow
                        required property string modelData
                        width:settingsColumn.width;height:36*root.u
                        Txt {
                            x:0;width:parent.width*.24;anchors.verticalCenter:parent.verticalCenter
                            text:colorRow.modelData;font.pixelSize:root.fontSize*.9
                            wrapMode:Text.NoWrap
                        }
                        Rectangle {
                            x:parent.width*.25;anchors.verticalCenter:parent.verticalCenter
                            width:26*root.u;height:26*root.u
                            color:root.cfg[colorRow.modelData];radius:3*root.u
                            border.color:root.tint(root.ink,.7)
                            MouseArea {
                                anchors.fill:parent;cursorShape:Qt.PointingHandCursor
                                onClicked:root.send({op:'pick',target:colorRow.modelData})
                            }
                        }
                        Input {
                            x:parent.width*.25+34*root.u
                            width:parent.width-x-75*root.u
                            anchors.verticalCenter:parent.verticalCenter
                            text:root.cfg[colorRow.modelData]
                            onEditingFinished:{
                                let v=text.trim();
                                if(/^#[0-9a-fA-F]{6}$/.test(v)){
                                    let values={};values[colorRow.modelData]=v;
                                    if(colorRow.modelData==='accent' || colorRow.modelData==='secondary')values.auto_palette=false;
                                    root.send({op:'settings',values:values});
                                }
                            }
                        }
                        Btn {
                            anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter
                            width:66*root.u;height:34*root.u;text:'Pick'
                            onClicked:root.send({op:'pick',target:colorRow.modelData})
                        }
                    }
                }
                Txt { text:'Panel opacity: '+Math.round(root.cfg.opacity*100)+'%' }
                Slider { width:parent.width;from:.15;to:1;value:root.cfg.opacity;onMoved:root.set('opacity',value) }
                CheckBox { text:'Auto accent from wallpaper';checked:root.cfg.auto_palette || false;palette.windowText:root.ink;font.pixelSize:root.fontSize;onClicked:root.set('auto_palette',checked) }
                Row { spacing:10*root.u;Btn { text:'Extract palette';onClicked:root.send({op:'palette'}) } Btn { text:'Pick pixel';onClicked:root.send({op:'pick'}) } }
                Row {
                    width:parent.width;height:30*root.u;spacing:4*root.u
                    Repeater {
                        model:root.swatches
                        delegate:Rectangle {
                            required property string modelData
                            width:(settingsColumn.width-11*4*root.u)/12;height:26*root.u;color:modelData;border.color:root.tint(root.ink,.6)
                            MouseArea { anchors.fill:parent;onClicked:root.send({op:'settings',values:{accent:parent.modelData,auto_palette:false}}) }
                        }
                    }
                }
                Txt { text:'Wallpaper path (fallback)';font.pixelSize:root.fontSize*.9 }
                Input { width:parent.width;text:root.cfg.wallpaper || '';onEditingFinished:root.set('wallpaper',text) }
                // cyberdesk-screen-storage-v25
                Txt { text:'Display for all three panels';color:root.accent }
                Basic.ComboBox {
                    id:displaySelect
                    property var outputs: {
                        let result=[{name:'',label:'Automatic (first connected display)'}];
                        for(let s of Quickshell.screens){
                            result.push({name:s.name,label:s.name+' · '+s.width+' × '+s.height});
                        }
                        return result;
                    }
                    width:parent.width;height:38*root.u
                    model:outputs;textRole:'label'
                    currentIndex:{
                        for(let i=0;i<outputs.length;i++)if(outputs[i].name===(root.cfg.monitor || ''))return i;
                        return -1;
                    }
                    leftPadding:11*root.u;rightPadding:32*root.u
                    font.family:'monospace';font.pixelSize:root.fontSize*.92
                    hoverEnabled:true
                    onActivated:{
                        let output=outputs[index].name;
                        Qt.callLater(function(){root.set('monitor',output);});
                    }
                    contentItem:Text {
                        text:displaySelect.currentText || ('Disconnected: '+root.cfg.monitor)
                        color:root.ink;font:displaySelect.font
                        verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight
                    }
                    indicator:Text {
                        x:displaySelect.width-width-11*root.u;anchors.verticalCenter:parent.verticalCenter
                        text:displaySelect.popup.visible?'▴':'▾';color:root.accent;font.pixelSize:root.fontSize
                    }
                    background:Rectangle {
                        color:root.tint(root.bg,.85);radius:3*root.u
                        border.color:root.tint(root.accent,displaySelect.activeFocus || displaySelect.hovered?1:.65)
                        border.width:displaySelect.activeFocus?2:1
                    }
                    delegate:Basic.ItemDelegate {
                        id:displayOption
                        required property var modelData
                        required property int index
                        width:displaySelect.width-8*root.u;height:36*root.u
                        highlighted:displaySelect.highlightedIndex===index;hoverEnabled:true
                        leftPadding:10*root.u;rightPadding:10*root.u
                        contentItem:Text {
                            text:displayOption.modelData.label;font:displaySelect.font
                            color:displayOption.index===displaySelect.currentIndex?root.accent:root.ink
                            verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight
                        }
                        background:Rectangle {
                            color:displayOption.highlighted || displayOption.hovered?root.tint(root.accent,.20):displayOption.index===displaySelect.currentIndex?root.tint(root.accent,.09):'transparent'
                            radius:2*root.u
                        }
                    }
                    popup:Popup {
                        y:displaySelect.height+4*root.u;width:displaySelect.width
                        height:Math.min(248*root.u,displaySelect.outputs.length*36*root.u+8*root.u)
                        padding:4*root.u;popupType:Popup.Item
                        closePolicy:Popup.CloseOnEscape | Popup.CloseOnPressOutside
                        background:Rectangle { color:root.tint(root.bg,.98);border.color:root.tint(root.accent,.85);radius:3*root.u }
                        contentItem:ListView {
                            clip:true;model:displaySelect.popup.visible?displaySelect.delegateModel:null
                            currentIndex:displaySelect.highlightedIndex;boundsBehavior:Flickable.StopAtBounds
                            ScrollBar.vertical:Basic.ScrollBar {
                                contentItem:Rectangle { implicitWidth:4*root.u;implicitHeight:25*root.u;color:root.tint(root.accent,.6);radius:2*root.u }
                            }
                        }
                    }
                }
                Txt {
                    width:parent.width;font.pixelSize:root.fontSize*.78;color:root.tint(root.ink,.7)
                    text:'Active: '+(root.monitorScreen?root.monitorScreen.name:'none')+'\nResolution shown in logical pixels. Selection saves automatically.'
                }
                // cyberdesk-edge-gaps-v26
                Txt { text:'Screen-edge gaps (px)';color:root.accent }
                Row {
                    width:settingsColumn.width;height:57*root.u;spacing:8*root.u
                    Column {
                        width:(parent.width-24*root.u)/4;spacing:4*root.u
                        Txt { text:'Left';font.pixelSize:root.fontSize*.85 }
                        Input { id:gapLeft;width:parent.width;inputMethodHints:Qt.ImhDigitsOnly;validator:IntValidator { bottom:0;top:500 }
                            text:String(root.cfg.left_margin===undefined?14:root.cfg.left_margin) }
                    }
                    Column {
                        width:(parent.width-24*root.u)/4;spacing:4*root.u
                        Txt { text:'Right';font.pixelSize:root.fontSize*.85 }
                        Input { id:gapRight;width:parent.width;inputMethodHints:Qt.ImhDigitsOnly;validator:IntValidator { bottom:0;top:500 }
                            text:String(root.cfg.right_margin===undefined?14:root.cfg.right_margin) }
                    }
                    Column {
                        width:(parent.width-24*root.u)/4;spacing:4*root.u
                        Txt { text:'Top';font.pixelSize:root.fontSize*.85 }
                        Input { id:gapTop;width:parent.width;inputMethodHints:Qt.ImhDigitsOnly;validator:IntValidator { bottom:0;top:500 }
                            text:String(root.cfg.top_margin===undefined?16:root.cfg.top_margin) }
                    }
                    Column {
                        width:(parent.width-24*root.u)/4;spacing:4*root.u
                        Txt { text:'Bottom';font.pixelSize:root.fontSize*.85 }
                        Input { id:gapBottom;width:parent.width;inputMethodHints:Qt.ImhDigitsOnly;validator:IntValidator { bottom:0;top:500 }
                            text:String(root.cfg.bottom_margin===undefined?16:root.cfg.bottom_margin) }
                    }
                }
                Btn {
                    text:'Apply edge gaps'
                    onClicked:{
                        if(!gapLeft.acceptableInput || !gapRight.acceptableInput || !gapTop.acceptableInput || !gapBottom.acceptableInput){root.error='Enter whole pixel values from 0 to 500.';return;}
                        let left=Number(gapLeft.text),right=Number(gapRight.text),top=Number(gapTop.text),bottom=Number(gapBottom.text);
                        if(root.monitorScreen && top+bottom>root.monitorScreen.height-600*root.u){root.error='Top + bottom gaps leave too little room for the panels.';return;}
                        if(root.monitorScreen && left+right>root.monitorScreen.width-2*root.panelWidth-40*root.u){root.error='Left + right gaps would overlap the side panels.';return;}
                        root.error='';root.send({op:'settings',values:{left_margin:left,right_margin:right,top_margin:top,bottom_margin:bottom}});
                    }
                }
                Txt {
                    width:parent.width;font.pixelSize:root.fontSize*.78;color:root.tint(root.ink,.7)
                    text:'Logical pixels, without height-based scaling. Left/right affect the side panels; top affects all three; bottom affects the side panels. The centered clock stays centered.'
                }
                // cyberdesk-chart-controls-v1
                Txt { text:'Hardware charts';color:root.accent;font.pixelSize:root.fontSize*1.2 }
                Row {
                    width:settingsColumn.width;height:57*root.u;spacing:8*root.u
                    Column {
                        width:(parent.width-16*root.u)/3;spacing:4*root.u
                        Txt { text:'Horizontal';font.pixelSize:root.fontSize*.85 }
                        Input {
                            id:chartColumnsInput
                            width:parent.width
                            inputMethodHints:Qt.ImhDigitsOnly
                            validator:IntValidator { bottom:4; top:120 }
                            text:String(root.chartColumns)
                        }
                    }
                    Column {
                        width:(parent.width-16*root.u)/3;spacing:4*root.u
                        Txt { text:'Vertical';font.pixelSize:root.fontSize*.85 }
                        Input {
                            id:chartRowsInput
                            width:parent.width
                            inputMethodHints:Qt.ImhDigitsOnly
                            validator:IntValidator { bottom:3; top:40 }
                            text:String(root.chartRows)
                        }
                    }
                    Column {
                        width:(parent.width-16*root.u)/3;spacing:4*root.u
                        Txt { text:'Seconds';font.pixelSize:root.fontSize*.85 }
                        Input {
                            id:chartSecondsInput
                            width:parent.width
                            inputMethodHints:Qt.ImhDigitsOnly
                            validator:IntValidator { bottom:30; top:3600 }
                            text:String(root.chartSeconds)
                        }
                    }
                }
                Btn {
                    text:'Apply chart settings'
                    onClicked:{
                        if(!chartColumnsInput.acceptableInput || !chartRowsInput.acceptableInput || !chartSecondsInput.acceptableInput){root.error='Use whole numbers: horizontal 4-120, vertical 3-40, seconds 30-3600.';return;}
                        let columns=Number(chartColumnsInput.text),rows=Number(chartRowsInput.text),seconds=Number(chartSecondsInput.text);
                        if(seconds<columns){root.error='Timeframe must be at least one second per horizontal block.';return;}
                        root.error='';
                        root.send({op:'settings',values:{chart_columns:columns,chart_rows:rows,chart_seconds:seconds}});
                    }
                }
                Txt {
                    width:parent.width;font.pixelSize:root.fontSize*.78;color:root.tint(root.ink,.7)
                    text:'Current: '+root.chartColumns+' × '+root.chartRows+' blocks, '+root.windowLabel(root.chartWindow).replace('-','')+' shown, '+(root.chartWindow/root.chartColumns).toFixed(2)+' s per block.\nA block appears after its time slice finishes and then never changes.'
                }
                Txt { text:'Side panel width: '+Math.round(root.cfg.panel_ratio*100)+'% of screen' }
                Slider { width:parent.width;from:.19;to:.34;value:root.cfg.panel_ratio;onMoved:root.set('panel_ratio',value) }
                Txt { text:'Text scale: '+Number(root.cfg.font_scale).toFixed(2) }
                Slider { width:parent.width;from:.75;to:1.5;value:root.cfg.font_scale;onMoved:root.set('font_scale',value) }
                CheckBox { text:'Show above normal windows';checked:root.cfg.layer==='top';palette.windowText:root.ink;font.pixelSize:root.fontSize;onClicked:root.set('layer',checked?'top':'bottom') }
                Txt { text:'GPU override: cardN or PCI address';font.pixelSize:root.fontSize*.9 }
                Input { width:parent.width;text:root.cfg.gpu_device || '';placeholderText:'Automatic: largest AMD VRAM';onEditingFinished:root.set('gpu_device',text) }
                Txt { width:parent.width;text:'Selected: '+root.stats.gpu.card+' · '+root.stats.gpu.pci+'\n'+root.stats.gpu.total.toFixed(1)+' GiB VRAM';font.pixelSize:root.fontSize*.8 }
                Txt { width:parent.width;text:root.info.devices.map(d=>d.card+'  '+d.pci+'  '+(d.total/1073741824).toFixed(1)+' GiB').join('\n');font.pixelSize:root.fontSize*.8 }
                Txt { width:parent.width;visible:root.error!=='';text:root.error;color:'#ff9e9e';font.pixelSize:root.fontSize*.85 }
                Txt { width:parent.width;text:'Saved automatically. Chats stay on this PC in plain text. No shell access or automatic system-data sharing.';font.pixelSize:root.fontSize*.8;color:root.tint(root.ink,.65) }
            }
        }
        Item {
            visible:root.page==='chat';x:22*root.u;anchors.bottom:parent.bottom;anchors.bottomMargin:24*root.u;width:parent.width-44*root.u;height:76*root.u
            Line { width:parent.width }
            Txt { y:8*root.u;width:parent.width;text:root.error || root.perf;font.pixelSize:root.fontSize*.72;color:root.error?'#ff9e9e':root.tint(root.ink,.65);maximumLineCount:2;elide:Text.ElideRight }
            Input { id:entry;y:34*root.u;width:parent.width-57*root.u;height:42*root.u;placeholderText:'Type a message…';enabled:!root.busy;onAccepted:root.submit() }
            Btn { anchors.right:parent.right;y:34*root.u;width:46*root.u;height:42*root.u;text:root.busy?'■':'➤';onClicked:root.busy?root.send({op:'stop'}):root.submit() }
        }
        Frame {
            visible:root.menuOpen;x:19*root.u;y:51*root.u;width:161*root.u;height:126*root.u;z:20
            Rectangle { anchors.fill:parent;anchors.margins:4*root.u;color:root.tint(root.bg,.98);z:-1 }
            Column {
                x:10*root.u;y:10*root.u;width:parent.width-20*root.u;spacing:4*root.u
                Repeater {
                    model:[{label:'New chat',page:'new'},{label:'Chat history',page:'history'},{label:'Settings',page:'settings'}]
                    delegate:Btn {
                        required property var modelData
                        width:parent.width;height:32*root.u;text:modelData.label;enabled:!root.busy || modelData.page==='settings'
                        onClicked:{if(modelData.page==='new'){root.send({op:'new'});root.page='chat';}else root.page=modelData.page;root.menuOpen=false;}
                    }
                }
            }
        }
    }
    PanelWindow {
        screen:root.monitorScreen
        anchors { top:true }
        margins.top:root.cfg.top_margin
        implicitWidth:260*root.u;implicitHeight:76*root.u
        color:'transparent';exclusionMode:ExclusionMode.Ignore
        WlrLayershell.namespace:'cyberdesk-clock'
        WlrLayershell.layer:root.cfg.layer==='top'?WlrLayer.Top:WlrLayer.Bottom
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        Frame { anchors.fill:parent }
        Column {
            width:parent.width
            anchors.verticalCenter:parent.verticalCenter
            spacing:0
            Txt { width:parent.width;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.NoWrap;text:Qt.formatDateTime(clock.date,'HH:mm');font.pixelSize:37*root.u;color:root.accent }
            // cyberdesk-layout-v23
            Txt { width:parent.width;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.NoWrap;text:Qt.formatDateTime(clock.date,'ddd, dd MMM');font.pixelSize:root.fontSize*.85;transform:Translate { y:-5*root.u } }
        }
    }
    PanelWindow {
        id:rightPanel
        screen:root.monitorScreen
        anchors { right:true;top:true;bottom:true }
        margins { right:root.cfg.right_margin===undefined?14:root.cfg.right_margin;top:root.cfg.top_margin;bottom:root.cfg.bottom_margin }
        implicitWidth:root.panelWidth
        color:'transparent';exclusionMode:ExclusionMode.Ignore
        WlrLayershell.namespace:'cyberdesk-stats'
        WlrLayershell.layer:root.cfg.layer==='top'?WlrLayer.Top:WlrLayer.Bottom
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.OnDemand
        Frame { anchors.fill:parent }
        Item {
            id:specs;x:22*root.u;y:17*root.u;width:parent.width-44*root.u;height:parent.height*.315
            Item {
            x:0;y:12*root.u;width:parent.width*.42;height:parent.height-24*root.u
            Txt {
                anchors.fill:parent
                text:root.info.logo || ''
                color:root.accent
                font.pixelSize:root.fontSize*.94
                minimumPixelSize:3
                fontSizeMode:Text.Fit
                wrapMode:Text.NoWrap
                lineHeight:1.12
                horizontalAlignment:Text.AlignLeft
                verticalAlignment:Text.AlignVCenter
            }
        }
            Txt { x:parent.width*.44;text:'CachyOS';font.pixelSize:25*root.u;color:root.accent }
            Line { x:parent.width*.44;y:35*root.u;width:parent.width*.56 }
            Column {
                x:parent.width*.44;y:44*root.u;width:parent.width*.56
                KV { width:parent.width;label:'OS:';value:root.info.os }
                KV { width:parent.width;label:'Host:';value:root.info.host }
                KV { width:parent.width;label:'Kernel:';value:root.info.kernel }
                KV { width:parent.width;label:'Uptime:';value:root.stats.uptime+' mins' }
                KV { width:parent.width;label:'Pkgs:';value:root.info.packages===null?'N/A':String(root.info.packages)+' (pacman)' }
                KV { width:parent.width;label:'WM:';value:'Hyprland' }
                KV { width:parent.width;label:'CPU:';value:root.info.cpu }
                KV { width:parent.width;label:'GPU:';value:root.info.gpu_name }
                KV { width:parent.width;label:'RAM:';value:root.stats.memory_text }
                KV { width:parent.width;label:'VRAM:';value:root.stats.gpu.used.toFixed(1)+' / '+root.stats.gpu.total.toFixed(1)+' GiB' }
                Repeater {
                    model:root.stats.disks
                    delegate:KV {
                        required property string modelData
                        width:parent.width
                        label:'Disk '+modelData.split(': ')[0]+':'
                        value:modelData.split(': ').slice(1).join(': ')
                    }
                }
            }
            Line { anchors.bottom:parent.bottom;width:parent.width }
        }
        DesktopControls {
            id:desktopBar
            x:specs.x;y:specs.y+specs.height+8*root.u
            width:specs.width;height:implicitHeight
            shell:root;panelWindow:rightPanel
        }
        // cyberdesk-hardware-order-v1
        Usage { id:cpuBlock;x:specs.x;y:desktopBar.y+desktopBar.height+12*root.u;width:specs.width;height:rightPanel.height*.145;title:'CPU';detail:root.percent(root.stats.cpu);values:root.cpuHistory }
        Usage { id:gpuBlock;x:specs.x;y:cpuBlock.y+cpuBlock.height+12*root.u;width:specs.width;height:rightPanel.height*.145;title:'GPU';detail:root.percent(root.stats.gpu.usage);values:root.gpuHistory }
        Usage { id:ramBlock;x:specs.x;y:gpuBlock.y+gpuBlock.height+12*root.u;width:specs.width;height:rightPanel.height*.145;title:'RAM';detail:root.stats.memory_text.replace(' / ',' GiB / ');values:root.memoryHistory }
        Item {
            x:specs.x;y:ramBlock.y+ramBlock.height+12*root.u;width:specs.width;height:parent.height-y-17*root.u
            Txt { text:'Temperatures (°C)';font.pixelSize:root.fontSize*.95 }
            Column {
                anchors.right:parent.right;spacing:3*root.u
                Txt { text:'● CPU  '+root.temp(root.stats.cpu_temp);color:root.accent;font.pixelSize:root.fontSize*.82 }
                Txt { text:'● GPU  '+root.temp(root.stats.gpu.temp);color:root.secondary;font.pixelSize:root.fontSize*.82 }
            }
            TempPlot { x:0;y:43*root.u;width:parent.width;height:Math.max(20*root.u,parent.height-y) }
        }
    }
}
