#!/usr/bin/env python3
"""Offline, conservative checklist extraction. No model, network, or Codex CLI."""
import argparse, datetime, fcntl, hashlib, json, os, pathlib, re, sqlite3, tempfile

CHECK = re.compile(r'^\s*(?:[-*+]\s*)?\[([ xX])\]\s*(.+)$')
ACTION = re.compile(r'^\s*(?:[-*+]\s*|\d+[.)、]\s*)?(?:TODO|待办|待辦|下一步|需要完成|尚未完成)\s*[:：]\s*(.+)$', re.I)
HEADING = re.compile(r'^(?:#{1,6}\s*)?(?:待办(?:事项)?|待辦(?:事項)?|未完成(?:事项)?|下一步|剩余(?:任务)?|todo(?: list)?|next steps?|remaining tasks?|action items?)\s*[:：]?$', re.I)
BULLET = re.compile(r'^\s*(?:[-*+]\s+|\d+[.)、]\s*)(.+)$')
FINISHED = re.compile(r'^(?:done|completed|cancelled|canceled|已完成|已取消|完成了)\s*[:：]\s*(.+)$', re.I)
DATE = re.compile(r'\b(20\d{2}-\d{2}-\d{2})\b')

def conversations(home):
    databases=sorted(home.glob('state_*.sqlite'),key=lambda p:int(p.stem.split('_')[-1]),reverse=True)
    if not databases: raise RuntimeError('No local Codex conversation database was found.')
    conn=sqlite3.connect(databases[0].as_uri()+'?mode=ro',uri=True);conn.row_factory=sqlite3.Row
    rows=conn.execute("SELECT id,title,rollout_path,archived FROM threads WHERE agent_path IS NULL OR agent_path IN ('/root','') ORDER BY updated_at DESC").fetchall()
    result=[];unreadable=0
    for row in rows:
        messages=[]
        try:
            with open(row['rollout_path']) as stream:
                for line in stream:
                    if len(line)>2_000_000: continue
                    try: item=json.loads(line)
                    except ValueError: continue
                    p=item.get('payload',{})
                    if item.get('type')!='response_item' or p.get('type')!='message': continue
                    role=p.get('role')
                    if role not in ('user','assistant') or (role=='assistant' and p.get('channel') not in (None,'final')): continue
                    text='\n'.join(x.get('text','') for x in p.get('content',[]) if x.get('type') in ('input_text','output_text','text'))
                    if text.lstrip().startswith(('<environment_context>','<recommended_plugins>','<permissions instructions>','<system')):continue
                    if text:messages.append({'role':role,'text':text})
        except OSError:unreadable+=1
        result.append({'id':row['id'],'title':row['title'],'messages':messages,'archived':bool(row['archived'])})
    conn.close();return result,unreadable

def normalized(text):
    return re.sub(r'[\W_]+','',text.casefold())

def extract(chat):
    candidates={}
    for message in chat['messages']:
        section=False;code=False
        for raw in message['text'].splitlines():
            line=raw.strip()
            if line.startswith('```'):code=not code;continue
            if code:continue
            heading=line.strip('* ')
            if HEADING.match(heading):section=True;continue
            if line.startswith('#') or (line and not BULLET.match(line) and not CHECK.match(line) and not ACTION.match(line)):section=False
            checked=CHECK.match(line); action=ACTION.match(line); finished=FINISHED.match(line)
            if finished:
                candidates.pop(normalized(finished[1]),None);continue
            title=None;done=False
            if checked:title=checked[2];done=checked[1].lower()=='x'
            elif action:title=action[1]
            elif section:
                bullet=BULLET.match(line)
                if bullet:title=bullet[1]
            if not title:continue
            title=title.strip().strip('*').strip();key=normalized(title)
            if not key:continue
            if done:candidates.pop(key,None);continue
            if len(title)>300:continue
            date=None;match=DATE.search(title)
            if match:
                try:date=datetime.date.fromisoformat(match[1]).isoformat()
                except ValueError:pass
            candidates[key]={'id':hashlib.sha256((chat['id']+'|'+key).encode()).hexdigest(),'title':title,'notes':'Extracted locally from an explicit checklist or action section. Review whether it is still relevant.','date':date,'done':False,'sourceID':chat['id'],'sourceTitle':chat['title'],'evidence':raw.strip()}
    return list(candidates.values())

def summarize(home):
    chats,unreadable=conversations(home)
    return {'tasks':[t for chat in chats for t in extract(chat)],'conversationCount':len(chats),'unreadableCount':unreadable,'scope':'All readable local root Codex conversations, including archived. Explicit checklists/action sections only; cloud-only chats unavailable.','updatedDay':datetime.date.today().isoformat(),'updatedAt':datetime.datetime.now().astimezone().isoformat()}

def write_daily(home,output):
    output.parent.mkdir(parents=True,exist_ok=True)
    with open(output.with_suffix('.lock'),'a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        if output.exists():
            try:
                existing=json.loads(output.read_text())
                if existing.get('updatedDay')==datetime.date.today().isoformat():return existing
            except (ValueError,OSError):pass
        result=summarize(home)
        fd,path=tempfile.mkstemp(prefix='.suggestions-',dir=output.parent)
        try:
            with os.fdopen(fd,'w') as f:json.dump(result,f,ensure_ascii=False);f.flush();os.fsync(f.fileno())
            os.replace(path,output)
        finally:
            if os.path.exists(path):os.unlink(path)
        return result

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--daily',action='store_true');parser.add_argument('--output',type=pathlib.Path,default=pathlib.Path.home()/'Library/Application Support/Codex Day/suggestions.json');args=parser.parse_args()
    try:
        home=pathlib.Path(os.environ.get('CODEX_HOME',str(pathlib.Path.home()/'.codex')))
        result=write_daily(home,args.output) if args.daily else summarize(home)
        print(json.dumps(result,ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'error':str(e)}));raise SystemExit(1)
