from pathlib import Path
import re, plistlib, sys
root = Path(__file__).resolve().parents[1]
text = (root/'Sources/Shortcuts.swift').read_text()
actions_section = text.split('enum ShortcutAction:', 1)[1].split('var id:', 1)[0]
actions = []
for line in actions_section.splitlines():
    if line.strip().startswith('case '): actions += [v.strip() for v in line.strip()[5:].split(',')]
standard = text.split('var standard: ShortcutBinding', 1)[1].split('@MainActor', 1)[0]
defaults = {}
for action, key, flags in re.findall(r'case \.(\w+): return \.init\(key: "([^"]+)"([^\n]*)', standard):
    modifiers = tuple(flag for flag in ('command','option','control','shift') if flag+': true' in flags)
    defaults[action] = (key, modifiers)
assert set(actions) == set(defaults), (set(actions)-set(defaults))
assert len(set(defaults.values())) == len(defaults), 'duplicate default shortcut'
menus = (root/'Sources/LyricPlayerApp.swift').read_text()
bound = set(re.findall(r'\.appShortcut\(\.(\w+)\)', menus))
assert bound == set(actions), (set(actions)-bound, bound-set(actions))
project = (root/'MyPlayer.xcodeproj/project.pbxproj').read_text()
assert project.count('CURRENT_PROJECT_VERSION = 38;') == 2
assert 'PBXFileSystemSynchronizedRootGroup' in project
for p in (root/'Resources').rglob('*.plist'):
    with p.open('rb') as f: plistlib.load(f)
assert 'videoMorePinned' not in (root/'Sources/LayoutWorkspace.swift').read_text()
assert 'TableTransparency(bottomInset: bottomClearance, selectionIDs: selection' in (root/'Sources/ContentView.swift').read_text()
assert 'UserDataStore.shared.file("library.json")' in (root/'Sources/PlayerManager.swift').read_text()
assert 'LyricPlayer/collections.json' not in (root/'Sources/CollectionStore.swift').read_text()
print(f'PASS: {len(actions)} unique defaults, complete menu binding, user data paths, selection wiring, project version and plist structure')
try:
    from tree_sitter import Language, Parser
    import tree_sitter_swift
except ImportError:
    print('Swift grammar parser not installed; skipped (Xcode compilation remains required).')
else:
    parser = Parser(Language(tree_sitter_swift.language()))
    errors = []
    files = list(root.rglob('*.swift'))
    for file in files:
        tree = parser.parse(file.read_bytes())
        def walk(node):
            if node.type == 'ERROR' or node.is_missing: errors.append((str(file), node.start_point, node.type))
            for child in node.children: walk(child)
        walk(tree.root_node)
    assert not errors, errors
    print(f'PASS: Swift grammar parse for {len(files)} files (not a type check or native build)')
