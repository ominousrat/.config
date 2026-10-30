import sys, json, time, threading, urllib.request, urllib.error, os, glob, colorsys, subprocess
from pathlib import Path
import psutil
from PIL import Image
BASE = Path(__file__).resolve().parent
STATE = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state'))) / 'cyberdesk'
STATE.mkdir(parents=True, exist_ok=True)
lock = threading.Lock()
config_lock = threading.RLock()
chat_lock = threading.Lock()
cfg = json.loads((BASE/'config.json').read_text())
if (STATE/'settings.json').exists():
    cfg.update(json.loads((STATE/'settings.json').read_text()))
history = []
if (STATE/'chat.json').exists():
    try: history = json.loads((STATE/'chat.json').read_text())
    except Exception: pass

def emit(kind, **kw):
    with lock:
        print(json.dumps({'type':kind, **kw}), flush=True)

def save_config():
    with config_lock:
        temp = STATE/'settings.tmp'
        temp.write_text(json.dumps(cfg, indent=2))
        temp.replace(STATE/'settings.json')

def save_history():
    temp = STATE/'chat.tmp'
    temp.write_text(json.dumps(history, ensure_ascii=False))
    temp.replace(STATE/'chat.json')

def request(path, data=None):
    url = cfg['ollama_url'].rstrip('/') + path
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, headers={'Content-Type':'application/json'})
    return urllib.request.urlopen(req, timeout=180 if data is not None else 5)

def models():
    try:
        with request('/api/tags') as r: names = [x['name'] for x in json.load(r)['models']]
        emit('models', models=names, error='')
    except Exception as e: emit('models', models=[], error=str(e))

def chat(text):
    if not chat_lock.acquire(False): return
    before = list(history)
    try:
        if not cfg.get('model'): raise ValueError('Select an installed model in Settings first.')
        history.append({'role':'user','content':text})
        emit('history', messages=history)
        emit('begin')
        answer = ''
        payload = {'model':cfg['model'], 'messages':[{'role':'system','content':cfg['system_prompt']}] + history, 'stream':True}
        with request('/api/chat', payload) as response:
            for raw in response:
                if not raw.strip(): continue
                data = json.loads(raw)
                if data.get('error'): raise RuntimeError(data['error'])
                chunk = data.get('message',{}).get('content','')
                answer += chunk
                if chunk: emit('delta', text=chunk)
                if data.get('done'):
                    duration = data.get('eval_duration',0)/1e9
                    emit('performance', text=f"{data.get('eval_count',0)} tokens · {data.get('eval_count',0)/duration:.1f} tok/s" if duration else '')
        history.append({'role':'assistant','content':answer})
        save_history()
        emit('history', messages=history)
    except Exception as e:
        history[:] = before
        emit('history', messages=history)
        emit('error', error=str(e))
    finally:
        emit('done')
        chat_lock.release()

def wallpaper_path():
    try:
        r = subprocess.run(['hyprctl','hyprpaper','listactive'],capture_output=True,text=True,timeout=2)
        if r.returncode == 0:
            pairs = [x.split(': ',1) for x in r.stdout.splitlines() if ': ' in x]
            preferred = cfg.get('monitor','')
            for mon, path in pairs:
                if mon == preferred and Path(path).is_file(): return path
            for mon, path in pairs:
                if Path(path).is_file(): return path
    except Exception: pass
    fallback = os.path.expanduser(cfg.get('wallpaper',''))
    return fallback if fallback and Path(fallback).is_file() else ''

def palette(path):
    with Image.open(path) as original:
        image = original.convert('RGB')
        image.thumbnail((180,180))
        q = image.quantize(colors=12)
        pal = q.getpalette()
        colors = []
        for count, idx in sorted(q.getcolors(), reverse=True):
            rgb = tuple(pal[idx*3:idx*3+3])
            h,s,v = colorsys.rgb_to_hsv(*(c/255 for c in rgb))
            colors.append((count, rgb, h,s,v))
        eligible = [x for x in colors if x[3] > .2 and x[4] > .28]
        chosen = max(eligible or colors, key=lambda x: x[0]*(.35+x[3])*(.3+x[4]))
        h,s,v = chosen[2:]
        accent = tuple(round(x*255) for x in colorsys.hsv_to_rgb(h,max(.45,s),max(.78,v)))
        hx = lambda rgb: '#'+''.join(f'{c:02x}' for c in rgb)
        return hx(accent), [hx(x[1]) for x in colors]

def apply_palette():
    path = wallpaper_path()
    if not path:
        emit('error',error='Cannot detect wallpaper. Set its absolute path in Settings.')
        return
    try:
        accent, swatches = palette(path)
        if cfg['auto_palette']:
            with config_lock:
                cfg['accent'] = accent
                save_config()
            emit('config', config=cfg)
        emit('palette', colors=swatches, path=path, accent=accent)
    except Exception as e: emit('error',error='Palette: '+str(e))

def pick():
    try:
        r = subprocess.run(['hyprpicker','-f','hex'],capture_output=True,text=True,timeout=60)
        color = r.stdout.strip()
        import re
        if r.returncode == 0 and re.fullmatch(r'#[0-9a-fA-F]{6}',color):
            with config_lock:
                cfg.update(accent=color,auto_palette=False)
                save_config()
            emit('config',config=cfg)
    except Exception as e: emit('error',error='Color picker: '+str(e))

def read(path, default=''):
    try: return Path(path).read_text().strip()
    except OSError: return default

def gpu_stats():
    for device in sorted(glob.glob('/sys/class/drm/card[0-9]*/device')):
        if read(device+'/vendor') != '0x1002': continue
        if not Path(device+'/gpu_busy_percent').exists(): continue
        hw = glob.glob(device+'/hwmon/hwmon*')
        temps = []
        for h in hw:
            for t in glob.glob(h+'/temp*_input'):
                label = read(t.replace('_input','_label')).lower()
                if label == 'edge' or not temps: temps.append(float(read(t,'0'))/1000)
        used = int(read(device+'/mem_info_vram_used','0'))/2**30
        total = int(read(device+'/mem_info_vram_total','0'))/2**30
        return {'usage':float(read(device+'/gpu_busy_percent','0')),'temp':temps[0] if temps else None,'vram':f'{used:.1f} / {total:.1f} GiB'}
    return {'usage':None,'temp':None,'vram':'Unavailable'}

def cpu_temp():
    sensors = psutil.sensors_temperatures()
    for key in ['k10temp','zenpower','coretemp']:
        if key in sensors and sensors[key]: return sensors[key][0].current
    return None

def metrics():
    last_palette = None
    tick = 0
    psutil.cpu_percent()
    while True:
        try:
            mem = psutil.virtual_memory()
            disks=[]
            for path in ['/', '/ssd']:
                if Path(path).exists():
                    d=psutil.disk_usage(path)
                    disks.append(f'{path}: {d.used/2**30:.0f} / {d.total/2**30:.0f} GiB')
            emit('metrics', cpu=psutil.cpu_percent(), memory=mem.percent,
                 memory_text=f'{mem.used/2**30:.2f} / {mem.total/2**30:.2f} GiB',
                 cpu_temp=cpu_temp(), gpu=gpu_stats(), disks=disks,
                 uptime=int((time.time()-psutil.boot_time())/60))
            if tick % 5 == 0:
                path = wallpaper_path()
                stamp = (path, Path(path).stat().st_mtime_ns if path else 0, cfg['auto_palette'])
                if stamp != last_palette:
                    last_palette = stamp
                    if path: apply_palette()
        except Exception as e: emit('error',error='Metrics: '+str(e))
        tick += 1
        time.sleep(1)

def main():
    emit('config',config=cfg)
    emit('history',messages=history)
    threading.Thread(target=metrics,daemon=True).start()
    for line in sys.stdin:
        try:
            cmd=json.loads(line)
            op=cmd.get('op')
            if op=='chat' and cmd.get('text','').strip():
                threading.Thread(target=chat,args=(cmd['text'].strip(),),daemon=True).start()
            elif op=='models': threading.Thread(target=models,daemon=True).start()
            elif op=='palette': threading.Thread(target=apply_palette,daemon=True).start()
            elif op=='pick': threading.Thread(target=pick,daemon=True).start()
            elif op=='new' and not chat_lock.locked():
                history.clear(); save_history(); emit('history',messages=history)
            elif op=='settings':
                allowed={'ollama_url','model','monitor','accent','background','text','opacity','auto_palette','wallpaper','panel_width','top_margin','bottom_margin'}
                with config_lock:
                    cfg.update({k:v for k,v in cmd['values'].items() if k in allowed})
                    save_config()
                emit('config',config=cfg)
        except Exception as e: emit('error',error=str(e))

if __name__=='__main__': main()
