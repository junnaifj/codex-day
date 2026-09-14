import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
const exec=promisify(execFile), root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const base=path.join(os.homedir(),'Library/Application Support/Codex Day'),port=9341;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const allowed=new Set(['state','calendar.connect','reminders.connect','daily.check','task.save','task.delete','suggestion.dismiss','error.dismiss']);
export async function nativeRequest(input){
  if(!allowed.has(input.op))throw Error('Unsupported operation');
  const id=crypto.randomUUID();const request=path.join(base,'requests',id+'.json'),response=path.join(base,'responses',id+'.json');
  await fs.mkdir(path.dirname(request),{recursive:true,mode:0o700});
  await fs.writeFile(request+'.tmp',JSON.stringify(input),{mode:0o600});await fs.rename(request+'.tmp',request);
  try{for(let n=0;n<100;n++){try{return JSON.parse(await fs.readFile(response,'utf8'))}catch(e){if(e.code!=='ENOENT')throw e}await sleep(150)}throw Error('Background helper is unavailable. Run the plugin installer again.')}finally{await fs.unlink(response).catch(()=>{});await fs.unlink(request).catch(()=>{})}
}
async function verifyListener(){
  const {stdout}=await exec('/usr/sbin/lsof',['-nP',`-iTCP:${port}`,'-sTCP:LISTEN','-FpFn'],{timeout:3000});
  const lines=stdout.trim().split('\n');const pids=[...new Set(lines.filter(l=>/^p\d+$/.test(l)).map(l=>l.slice(1)))];
  if(pids.length!==1 || lines.filter(l=>l.startsWith('n')).some(l=>!/^n127\.0\.0\.1:9341$/.test(l)))throw Error('Refusing an unverified debug listener.');
  const {stdout:command}=await exec('/bin/ps',['-p',pids[0],'-o','comm='],{timeout:3000});
  const executable=command.trim();
  if(!/^\/.*\/(ChatGPT|Codex)\.app\/Contents\/MacOS\/(ChatGPT|Codex)$/.test(executable))throw Error('Listener does not belong to Codex.');
  await exec('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2"',executable],{timeout:5000});
}
export function validTarget(t){
  if(t.type!=='page'||typeof t.id!=='string'||!/^[A-Za-z0-9-]{1,100}$/.test(t.id))return false;
  try{const page=new URL(t.url),ws=new URL(t.webSocketDebuggerUrl);return page.protocol==='app:'&&page.hostname==='-'&&ws.protocol==='ws:'&&['127.0.0.1','localhost'].includes(ws.hostname)&&ws.port===String(port)&&ws.pathname===`/devtools/page/${t.id}`}catch{return false}
}
class Session {
  constructor(target){this.ws=new WebSocket(target.webSocketDebuggerUrl);this.pending=new Map();this.seq=0;this.context=null;this.inflight=0;this.closed=false;}
  async start(){
    await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{this.ws.close();reject(Error('Connection timeout'))},5000);this.ws.onopen=()=>{clearTimeout(timer);resolve()};this.ws.onerror=()=>{clearTimeout(timer);reject(Error('Connection failed'))}});
    this.ws.onclose=()=>{this.closed=true;for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Connection closed'))}this.pending.clear()};
    this.ws.onmessage=e=>{let m;try{m=JSON.parse(e.data)}catch{return}if(m.id){const p=this.pending.get(m.id);if(p){clearTimeout(p.timer);this.pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result)}return}if(m.method==='Runtime.bindingCalled')this.binding(m.params).catch(()=>{});if(m.method==='Page.domContentEventFired')this.inject().catch(()=>{});if(m.method==='Page.frameNavigated'&&!m.params.frame.parentId)this.context=null};
    await this.send('Runtime.enable');await this.send('Page.enable');await this.send('Runtime.addBinding',{name:'__codexDayNative',executionContextName:'codex-day'});await this.inject();
  }
  send(method,params={}){return new Promise((resolve,reject)=>{const id=++this.seq,timer=setTimeout(()=>{this.pending.delete(id);reject(Error('CDP timeout'))},8000);this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({id,method,params}))})}
  async inject(){
    if(this.injecting)return;this.injecting=true;
    try{const {frameTree}=await this.send('Page.getFrameTree');const {executionContextId}=await this.send('Page.createIsolatedWorld',{frameId:frameTree.frame.id,worldName:'codex-day'});this.context=executionContextId;
      const panel=await fs.readFile(path.join(root,'assets/panel.js'),'utf8');const theme=await fs.readFile(path.join(root,'assets/theme.css'),'utf8');
      const result=await this.send('Runtime.evaluate',{contextId:this.context,expression:`(()=>{let s=document.getElementById('codex-day-theme');if(!s){s=document.createElement('style');s.id='codex-day-theme';document.head.append(s)}s.textContent=${JSON.stringify(theme)}})();\n${panel}`,returnByValue:true});if(result.exceptionDetails)throw Error('Panel injection failed');
    }finally{this.injecting=false}
  }
  async ensure(){
    if(!this.context){await this.inject();return}
    try{const result=await this.send('Runtime.evaluate',{contextId:this.context,expression:'globalThis.__codexDayUI?.verify()',returnByValue:true});
      if(result.exceptionDetails||result.result?.value?.version!=='0.3.0')await this.inject();
    }catch{await this.inject()}
  }
  async binding(params){
    if(params.name!=='__codexDayNative'||params.executionContextId!==this.context||params.payload.length>131072||this.inflight>=8)return;
    let input;try{input=JSON.parse(params.payload)}catch{return}if(typeof input.id!=='string'||!/^\d{1,9}$/.test(input.id)||!allowed.has(input.op))return;
    this.inflight++;const context=this.context;
    try{let result;try{result=await nativeRequest(input)}catch(e){result={error:e.message,tasks:[],suggestions:[],events:[]}}await this.send('Runtime.evaluate',{contextId:context,expression:`globalThis.__codexDayReply?.(${JSON.stringify(input.id)},${JSON.stringify(result)})`})}finally{this.inflight--}
  }
  async remove(){try{await this.send('Runtime.evaluate',{contextId:this.context,expression:"globalThis.__codexDayUI?.destroy();document.getElementById('codex-day-theme')?.remove()"})}catch{}this.ws.close()}
}
async function main(){
  const sessions=new Map();let stopping=false;
  for(const signal of ['SIGTERM','SIGINT'])process.on(signal,async()=>{if(stopping)return;stopping=true;await Promise.all([...sessions.values()].map(s=>s.remove()));process.exit(0)});
  let previous='';
  while(!stopping){try{
    await verifyListener();const response=await fetch(`http://127.0.0.1:${port}/json/list`,{signal:AbortSignal.timeout(3000)});if(!response.ok)throw Error('Target discovery failed');const raw=await response.text();if(raw.length>1000000)throw Error('Invalid target list');const targets=JSON.parse(raw).filter(validTarget);
    for(const [id,s] of sessions)if(s.closed||!targets.some(t=>t.id===id)){s.ws.close();sessions.delete(id)}
    for(const target of targets)if(!sessions.has(target.id)){const s=new Session(target);try{await s.start();sessions.set(target.id,s)}catch(e){s.ws.close();throw e}}
    for(const session of sessions.values())await session.ensure();
    await fs.writeFile(path.join(base,'connection.json'),JSON.stringify({phase:'connected',windows:sessions.size,version:'0.3.0',checkedAt:new Date().toISOString()}),{mode:0o600});
    previous='';
  }catch(e){for(const session of sessions.values())session.ws.close();sessions.clear();await fs.writeFile(path.join(base,'connection.json'),JSON.stringify({phase:'waiting-for-extension-launch',version:'0.3.0',checkedAt:new Date().toISOString()}),{mode:0o600}).catch(()=>{});const message='Waiting for Codex local extension connection.';if(previous!==message){console.log(message);previous=message}}
  await sleep(5000)}
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(()=>process.exit(1));
