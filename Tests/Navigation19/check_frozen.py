from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[2]
for name, expected in json.loads((Path(__file__).parent/'frozen18.json').read_text()).items():
    if name == 'ContentView.background-contract':
        text=(root/'Sources/ContentView.swift').read_text()
        data='\n'.join(line.strip() for line in text.splitlines() if '.sharedBackgroundVisibility(' in line or '.toolbarBackground(' in line or '.background(PlaybackToolbarPresentation(' in line).encode()
    else: data=(root/'Sources'/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==expected, f'v4.0.18 frozen background implementation changed: {name}'
print('PASS: v4.0.18 fullscreen background implementation and toolbar background modifiers unchanged')
