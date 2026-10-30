import os, sys, json, time, threading, subprocess, glob, re, platform, colorsys, urllib.request
from pathlib import Path
from datetime import datetime
import psutil
from PIL import Image
BASE=Path(__file__).resolve().parent
STATE=Path(os.environ.get('XDG_STATE_HOME',str(Path.home()/'.local/state')))/'cyberdesk'
STATE.mkdir(parents=True,exist_ok=True)
CFG=json.loads((BASE/'defaults.json').read_text())
try: old=json.loads((STATE/'settings.json').read_text())
except (OSError,ValueError): old={}
if 'panel_ratio' not in old:
    old={k:v for k,v in old.items() if k in ['ollama_url','model','monitor','auto_palette','wallpaper','gpu_device']}
CFG.update({k:v for k,v in old.items() if k in CFG})
# Previous version stored panel width in pixels. This release uses display-relative widths.
lock=threading.Lock(); state_lock=threading.RLock(); busy=threading.Lock()
cancel=threading.Event()
try: chats=json.loads((STATE/'conversations.json').read_text())
except (OSError,ValueError): chats=[]
if not chats:
    try: legacy=json.loads((STATE/'chat.json').read_text())
    except (OSError,ValueError): legacy=[]
    chats=[{'id':str(time.time_ns()),'title':'Previous chat' if legacy else 'New chat','messages':legacy}]
active=chats[0]['id']

def emit(kind,**values):
    with lock: print(json.dumps(dict(type=kind,**values)),flush=True)
def atomic(name,data):
    p=STATE/name; temp=p.with_suffix('.tmp');temp.write_text(json.dumps(data,ensure_ascii=False,indent=2));temp.replace(p)
def current(): return next(c for c in chats if c['id']==active)
def snapshot():
    emit('history',messages=current()['messages'],chats=[{'id':c['id'],'title':c['title']} for c in chats],active=active)
def persist(): atomic('conversations.json',chats)
def update(values):
    with state_lock:
        for k,v in values.items():
            if k not in CFG: continue
            if k in ['accent','secondary','background','text'] and not re.fullmatch(r'#[0-9A-Fa-f]{6}',str(v)): continue
            if k in ['opacity','panel_ratio','font_scale']:
                lo,hi={'opacity':(.15,1),'panel_ratio':(.19,.34),'font_scale':(.75,1.5)}[k]
                v=max(lo,min(hi,float(v)))
            CFG[k]=v
        atomic('settings.json',CFG)
        emit('config',config=CFG)
def run(args):
    try:
        r=subprocess.run(args,capture_output=True,text=True,timeout=3)
        return r.stdout.strip() if r.returncode==0 else ''
    except (OSError,subprocess.TimeoutExpired): return ''
def read(p,default=''):
    try: return Path(p).read_text().strip()
    except OSError: return default
def number(p):
    try: return int(read(p))
    except ValueError:return 0

def gpu_devices():
    devices=[]
    for d in glob.glob('/sys/class/drm/card[0-9]*/device'):
        card=Path(d).parent.name
        if not re.fullmatch(r'card\d+',card) or read(d+'/vendor')!='0x1002':continue
        if not Path(d+'/gpu_busy_percent').exists():continue
        pci=Path(d).resolve().name
        vram=number(d+'/mem_info_vram_total')
        devices.append(dict(card=card,path=d,pci=pci,total=vram))
    return devices

def select_gpu(devices):
    wanted=CFG.get('gpu_device','')
    for d in devices:
        if wanted in [d['card'],d['pci']] and wanted:return d
    # A 16-GiB dGPU must win over the CPU's small UMA framebuffer.
    return max(devices,key=lambda d:d['total'],default=None)

def gpu_info(device):
    if not device:return dict(usage=None,temp=None,total=0,used=0,card='',pci='',name='AMD GPU unavailable')
    d=device['path'];temps={}
    for p in glob.glob(d+'/hwmon/hwmon*/temp*_input'):
        val=number(p)/1000
        if val:temps[read(p.replace('_input','_label'),Path(p).stem)]=val
    temp=temps.get('edge',next(iter(temps.values()),None))
    return dict(usage=number(d+'/gpu_busy_percent'),temp=temp,total=device['total']/2**30,
                used=number(d+'/mem_info_vram_used')/2**30,card=device['card'],pci=device['pci'])

def cpu_temp():
    for key,items in psutil.sensors_temperatures().items():
        if key in ['k10temp','zenpower','coretemp'] and items:
            return next((x.current for x in items if x.label in ['Tctl','Tdie','Package id 0']),items[0].current)
    return None

def static_info():
    cpu=next((x.split(':',1)[1].strip() for x in read('/proc/cpuinfo').splitlines() if x.startswith('model name')),'Unknown CPU')
    cpu=cpu.replace('AMD ','').replace(' 6-Core Processor','').replace(' Processor','')
    host=read('/sys/class/dmi/id/board_name',platform.node())
    version=run(['hyprctl','version']).splitlines()
    packages=run(['pacman','-Qq'])
    devices=gpu_devices();selected=select_gpu(devices)
    label=''
    if selected:
        label=run(['lspci','-s',selected['pci']])
        label=re.sub(r'^.*?: (?:Advanced Micro Devices, Inc\. \[AMD/ATI\] )?','',label)
        label=re.sub(r' \(rev .*','',label)
    return dict(logo=read(BASE/'terminal-logo.txt',''),cpu=cpu,host=host,kernel=platform.release(),os='CachyOS '+platform.machine(),
                wm=version[0] if version else 'Hyprland',packages=len(packages.splitlines()) if packages else None,
                gpu_name=label or ('AMD Radeon · '+str(round(selected['total']/2**30))+' GiB' if selected else 'Unavailable'),
                devices=[{k:d[k] for k in ['card','pci','total']} for d in devices])

def wallpaper():
    result=run(['hyprctl','hyprpaper','listactive'])
    found=[]
    for line in result.splitlines():
        if ': ' not in line:continue
        mon,path=line.split(': ',1)
        if Path(path).is_file():found.append((mon,path))
    for mon,path in found:
        if mon==CFG['monitor']:return path
    if found:return found[0][1]
    fallback=os.path.expanduser(CFG.get('wallpaper',''))
    return fallback if fallback and Path(fallback).is_file() else ''

def extract_palette(path):
    with Image.open(path) as im:
        image=im.convert('RGB');image.thumbnail((160,160));q=image.quantize(colors=12)
        table=q.getpalette();colors=[]
        for count,index in sorted(q.getcolors(),reverse=True):
            rgb=tuple(table[index*3:index*3+3]);h,s,v=colorsys.rgb_to_hsv(*(c/255 for c in rgb))
            colors.append((count,rgb,h,s,v))
        eligible=[c for c in colors if c[3]>.2 and c[4]>.25] or colors
        c=max(eligible,key=lambda x:x[0]*(.3+x[3])*(.3+x[4]))
        h,s,v=c[2:];rgb=colorsys.hsv_to_rgb(h,max(.40,s),max(.85,v))
        hx=lambda a:'#'+''.join(f'{round(x):02x}' for x in a)
        accent=hx([x*255 for x in rgb])
        secondary=hx([x*255 for x in colorsys.hsv_to_rgb((h+.09)%1,.8,.9)])
        return accent,secondary,[hx(c[1]) for c in colors]

def palette():
    path=wallpaper()
    if not path:emit('error',error='Wallpaper not detected. Enter its absolute path in Setup.');return
    try:
        a,b,colors=extract_palette(path)
        if CFG['auto_palette']:update(dict(accent=a,secondary=b))
        emit('palette',colors=colors,path=path)
    except Exception as e:emit('error',error='Palette: '+str(e))
def pick():
    try:
        r=subprocess.run(['hyprpicker','-f','hex'],capture_output=True,text=True,timeout=90)
        c=r.stdout.strip()
        if re.fullmatch(r'#[0-9A-Fa-f]{6}',c):update(dict(accent=c,auto_palette=False))
    except Exception as e:emit('error',error=str(e))
def http(path,data=None):
    req=urllib.request.Request(CFG['ollama_url'].rstrip('/')+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'})
    return urllib.request.urlopen(req,timeout=180 if data else 5)
def models():
    try:
        with http('/api/tags') as r:names=[x['name'] for x in json.load(r)['models']]
        emit('models',models=names,connected=True)
    except Exception as e:emit('models',models=[],connected=False);emit('error',error='Ollama: '+str(e))

def chat(text):
    if not busy.acquire(False):return
    cancel.clear();conversation=current();messages=conversation['messages'];old=list(messages)
    try:
        if not CFG['model']:raise ValueError('Open menu → Settings; connect and select an Ollama model.')
        messages.append(dict(role='user',content=text,time=datetime.now().strftime('%H:%M')))
        snapshot();emit('begin');answer=''
        payload=dict(model=CFG['model'],stream=True,messages=[dict(role='system',content='You are a helpful local AI assistant. You have no tools or computer access. Never claim you inspected the system.')]+[{k:m[k] for k in ['role','content']} for m in messages])
        with http('/api/chat',payload) as response:
            for raw in response:
                if cancel.is_set():break
                if not raw.strip():continue
                data=json.loads(raw)
                if data.get('error'):raise RuntimeError(data['error'])
                token=data.get('message',{}).get('content','');answer+=token
                if token:emit('delta',text=token)
                if data.get('done'):
                    seconds=data.get('eval_duration',0)/1e9
                    emit('performance',text=f"{data.get('eval_count',0)/seconds:.1f} tok/s · {data.get('eval_count',0)} tokens" if seconds else '')
        if answer:messages.append(dict(role='assistant',content=answer,time=datetime.now().strftime('%H:%M')))
        else:messages[:]=old
        if conversation['title']=='New chat':conversation['title']=text[:45]
        persist();snapshot()
    except Exception as e:messages[:]=old;snapshot();emit('error',error=str(e))
    finally:emit('done');busy.release()

def metrics_loop():
    tick=0;last=None;psutil.cpu_percent()
    emit('system',info=static_info())
    while True:
        try:
            mem=psutil.virtual_memory();devices=gpu_devices();gpu=gpu_info(select_gpu(devices))
            disks=[]
            for p in ['/','/ssd']:
                if Path(p).exists():
                    d=psutil.disk_usage(p);disks.append(f'{p}: {d.used/2**30:.0f} / {d.total/2**30:.0f} GiB')
            emit('metrics',cpu=psutil.cpu_percent(),cpu_temp=cpu_temp(),memory=mem.percent,
                 memory_text=f'{mem.used/2**30:.2f} / {mem.total/2**30:.2f} GiB',gpu=gpu,disks=disks,uptime=int((time.time()-psutil.boot_time())/60))
            if tick%5==0:
                path=wallpaper();key=(path,Path(path).stat().st_mtime_ns if path else 0,CFG['auto_palette'])
                if key!=last:
                    last=key
                    if path:palette()
            if tick%30==0:emit('system',info=static_info())
        except Exception as e:emit('error',error='Monitor: '+str(e))
        tick+=1;time.sleep(1)

def main():
    global active
    emit('config',config=CFG);snapshot()
    threading.Thread(target=metrics_loop,daemon=True).start()
    threading.Thread(target=models,daemon=True).start()
    for line in sys.stdin:
        try:
            c=json.loads(line);op=c.get('op')
            if op in ['models','palette','pick']:threading.Thread(target=globals()[op],daemon=True).start()
            elif op=='settings':update(c['values'])
            elif op=='chat' and c.get('text','').strip():threading.Thread(target=chat,args=(c['text'].strip(),),daemon=True).start()
            elif op=='stop':cancel.set()
            elif op=='new' and not busy.locked():
                active=str(time.time_ns());chats.insert(0,dict(id=active,title='New chat',messages=[]));persist();snapshot()
            elif op=='switch' and not busy.locked() and any(x['id']==c['id'] for x in chats):active=c['id'];snapshot()
        except Exception as e:emit('error',error=str(e))
if __name__=='__main__':main()
