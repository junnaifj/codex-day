import {test} from 'node:test';import assert from 'node:assert/strict';import {validTarget} from '../codex-day/scripts/bridge.mjs';
test('only Codex app renderer targets on the expected local endpoint',()=>{
 const valid={id:'123-ABC',type:'page',url:'app://-/index.html',webSocketDebuggerUrl:'ws://127.0.0.1:9341/devtools/page/123-ABC'};
 assert.equal(validTarget(valid),true);
 for(const change of [{url:'https://example.com'},{webSocketDebuggerUrl:'ws://evil.example:9341/devtools/page/123-ABC'},{webSocketDebuggerUrl:'ws://127.0.0.1:1234/devtools/page/123-ABC'},{id:'../escape'},{type:'iframe'}])assert.equal(validTarget({...valid,...change}),false);
});
import fs from 'node:fs';
test('host reading surfaces cannot receive a blur or opacity filter',()=>{
 const css=fs.readFileSync(new URL('../codex-day/assets/theme.css',import.meta.url),'utf8').replace(/\/\*[\s\S]*?\*\//g,'');
 assert(!/(?:^|[;{])\s*(?:filter|backdrop-filter|-webkit-backdrop-filter|opacity)\s*:/.test(css));
});
