#!/usr/bin/env python3
"""Advance the internal build counter; keep the public release version stable."""
import fcntl, os, plistlib, re
from pathlib import Path
root = Path(os.environ['SRCROOT'])
version = (root / 'Version.txt').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise ValueError('Version.txt must contain MAJOR.MINOR.PATCH')
with (root / 'BuildNumber.lock').open('a+') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    counter = root / 'BuildNumber.txt'
    number = int(counter.read_text().strip()) + 1 if counter.exists() else 1
    counter.write_text(str(number) + '\n')
    plist = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['INFOPLIST_PATH']
    values = plistlib.loads(plist.read_bytes())
    values.update(CFBundleVersion=str(number), CFBundleShortVersionString=version,
                  CFBundleDisplayName='MyPlayer', CFBundleName='MyPlayer')
    plist.write_bytes(plistlib.dumps(values))
    print(f'MyPlayer v{version} (internal build {number})')
