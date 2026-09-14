#!/usr/bin/env python3
"""Install only Codex Day-owned support files and LaunchAgents. Never restart Codex."""
import os,pathlib,plistlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
home=pathlib.Path.home();base=home/'Library/Application Support/Codex Day';agents=home/'Library/LaunchAgents'
app=root/'build/Codex Day Helper.app'
launcher=root/'build/Codex with Day.app'
if not app.is_dir() or not launcher.is_dir():raise SystemExit('Run ./scripts/build.sh first.')
if base.is_symlink():raise SystemExit('Refusing a symlinked application support directory.')
base.mkdir(parents=True,exist_ok=True,mode=0o700);agents.mkdir(parents=True,exist_ok=True)
node=pathlib.Path('/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node')
if not node.exists():node=pathlib.Path('/Applications/Codex.app/Contents/Resources/cua_node/bin/node')
subprocess.run(['/usr/bin/codesign','--verify','--strict','--test-requirement','=anchor apple generic and certificate leaf[subject.OU] = "2DC432GLL2"',str(node)],check=True)
labels=['local.codex.day.helper','local.codex.day.bridge','local.codex.day.midnight']
for label in labels:subprocess.run(['/bin/launchctl','bootout',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
# Install in private staging first; retain previous install for rollback during the swap.
staging=pathlib.Path(tempfile.mkdtemp(prefix='.install-',dir=base))
try:
 shutil.copytree(root/'codex-day',staging/'plugin',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
 subprocess.run(['/usr/bin/ditto','--noextattr','--norsrc',str(app),str(staging/'Codex Day Helper.app')],check=True)
 subprocess.run(['/usr/bin/codesign','--verify','--strict',str(staging/'Codex Day Helper.app')],check=True)
 target=base/'runtime';previous=base/'runtime.previous'
 if previous.exists():raise SystemExit('Previous runtime backup exists; inspect it before updating.')
 if target.exists():target.rename(previous)
 try:staging.rename(target)
 except BaseException:
  if previous.exists():previous.rename(target)
  raise
 if previous.exists():shutil.rmtree(previous)
finally:
 if staging.exists():shutil.rmtree(staging)
helper=base/'runtime/Codex Day Helper.app/Contents/MacOS/CodexDayHelper';plugin=base/'runtime/plugin'
jobs=[
 {'Label':labels[0],'ProgramArguments':[str(helper)],'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False}},
 {'Label':labels[1],'ProgramArguments':[str(node),str(plugin/'scripts/bridge.mjs')],'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False}},
 {'Label':labels[2],'ProgramArguments':['/usr/bin/python3',str(plugin/'scripts/summarize.py'),'--daily','--output',str(base/'suggestions.json')],'StartCalendarInterval':{'Hour':0,'Minute':0},'RunAtLoad':True}
]
for job in jobs:
 job['ProcessType']='Background';job['Umask']=0o077
 # Suppress private result JSON and unbounded log growth.
 job['StandardOutPath']='/dev/null';job['StandardErrorPath']='/dev/null'
 path=agents/(job['Label']+'.plist')
 if path.is_symlink():raise SystemExit('Refusing symlinked LaunchAgent.')
 path.write_bytes(plistlib.dumps(job));path.chmod(0o600)
 subprocess.run(['/bin/launchctl','bootstrap',f'gui/{os.getuid()}',str(path)],check=True)
applications=home/'Applications';applications.mkdir(exist_ok=True)
launcher_target=applications/'Codex with Day.app'
if launcher_target.exists():
 existing=plistlib.loads((launcher_target/'Contents/Info.plist').read_bytes())
 if existing.get('CFBundleIdentifier')!='local.codex.day.launcher':raise SystemExit('A different app already uses the launcher path.')
 shutil.rmtree(launcher_target)
subprocess.run(['/usr/bin/ditto','--noextattr','--norsrc',str(launcher),str(launcher_target)],check=True)
print('Installed Codex Day runtime and the persistent ~/Applications/Codex with Day.app launcher. Codex was not restarted.')
