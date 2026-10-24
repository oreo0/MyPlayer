#!/usr/bin/env python3
"""Stamp every Xcode build, including direct IDE builds, under a file lock."""
import fcntl, os, plistlib
from pathlib import Path
root = Path(os.environ['SRCROOT'])
with (root / 'BuildNumber.lock').open('a+') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    counter = root / 'BuildNumber.txt'
    number = int(counter.read_text().strip()) + 1 if counter.exists() else 1
    counter.write_text(str(number) + '\n')
    plist = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['INFOPLIST_PATH']
    values = plistlib.loads(plist.read_bytes())
    values.update(CFBundleVersion=str(number), CFBundleShortVersionString='4.0',
                  CFBundleDisplayName='MyPlayer Beta', CFBundleName='MyPlayer Beta')
    plist.write_bytes(plistlib.dumps(values))
    print(f'MyPlayer 4 ({number})')
