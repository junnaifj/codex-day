#!/usr/bin/env python3
"""Disable Codex Day background jobs; preserve user task data and Reminders."""
import os,pathlib,subprocess,shutil,plistlib
home=pathlib.Path.home();base=home/'Library/Application Support/Codex Day'
for label in ['local.codex.day.bridge','local.codex.day.helper','local.codex.day.midnight']:
 subprocess.run(['/bin/launchctl','bootout',f'gui/{os.getuid()}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 plist=home/'Library/LaunchAgents'/(label+'.plist')
 if plist.is_file() and not plist.is_symlink():plist.unlink()
runtime=base/'runtime'
if runtime.is_dir() and not runtime.is_symlink():shutil.rmtree(runtime)
print('Background jobs removed. To-dos and Apple Reminders are preserved. Quit and reopen Codex normally to close its debug port and restore its original appearance.')

launcher=home/'Applications/Codex with Day.app'
if launcher.is_dir() and not launcher.is_symlink():
 info=plistlib.loads((launcher/'Contents/Info.plist').read_bytes())
 if info.get('CFBundleIdentifier')=='local.codex.day.launcher':shutil.rmtree(launcher)
