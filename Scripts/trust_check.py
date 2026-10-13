#!/usr/bin/env python3
"""The trust inventory (docs/release/TRUST.md) against the code. Fails when the code can reach
something the inventory doesn't list, or the inventory lists something the code no longer has,
so a new bridge op, entitlement, permission prompt, external hand-off, URL or dependency can't
land without a row (the review). Also fails on the rules TRUST.md lists under "Checked rules".

  python3 Scripts/trust_check.py          # exit 1 on any mismatch; runs on Linux (CI: design handoff)
"""
import glob, os, plistlib, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DOC = os.path.join(ROOT, 'docs/release/TRUST.md')
FAILS = []


def read(rel):
    return open(os.path.join(ROOT, rel), encoding='utf-8').read()


def table(section):
    """First-column code spans of the table under `### <section>` in TRUST.md."""
    doc = read('docs/release/TRUST.md')
    m = re.search(r'^### ' + re.escape(section) + r'.*?\n(.*?)(?=^#{2,3} |\Z)', doc, re.S | re.M)
    if not m:
        FAILS.append('TRUST.md has no section "### %s"' % section)
        return set()
    rows = set()
    for line in m.group(1).split('\n'):
        c = re.match(r'\|\s*`([^`]+)`\s*\|', line)
        if c:
            rows.add(c.group(1))
    return rows


def compare(section, doc, code, what):
    for x in sorted(code - doc):
        FAILS.append('%s: `%s` is in the code but not in TRUST.md "%s": add a row (what it reaches and why)' % (what, x, section))
    for x in sorted(doc - code):
        FAILS.append('%s: `%s` is in TRUST.md "%s" but not in the code: remove the row' % (what, x, section))
    print(('ok   ' if code == doc else 'FAIL ') + '%s: %d' % (what, len(code)))


def app_swift():
    """App sources (not tests, not tools): path → text without comment lines."""
    out = {}
    for f in sorted(glob.glob(os.path.join(ROOT, 'Lumina/**/*.swift'), recursive=True)):
        lines = [l for l in open(f, encoding='utf-8').read().split('\n') if not re.match(r'\s*//', l)]
        out[os.path.relpath(f, ROOT)] = '\n'.join(lines)
    return out


SWIFT = app_swift()

# Entitlements
ents = set()
for f in glob.glob(os.path.join(ROOT, 'Config/*.entitlements')):
    ents |= set(plistlib.load(open(f, 'rb')).keys())
compare('Entitlements', table('Entitlements'), ents, 'entitlements')

# Permission prompts: generated Info.plist keys
usage = set(re.findall(r'INFOPLIST_KEY_(NS\w+UsageDescription)', read('Lumina.xcodeproj/project.pbxproj')))
for f in glob.glob(os.path.join(ROOT, 'Config/*.xcconfig')):
    usage |= set(re.findall(r'INFOPLIST_KEY_(NS\w+UsageDescription)', open(f, encoding='utf-8').read()))
compare('Permission prompts', table('Permission prompts'), usage, 'permission prompts')

# Bridge ops: the cases of the page → native switch
bridge = SWIFT['Lumina/Sets/Core/SetsBridge.swift']
m = re.search(r'didReceive message: WKScriptMessage\).*?switch op \{(.*?)\n        default:', bridge, re.S)
ops = set(re.findall(r'^        case "([^"]+)"', m.group(1), re.M)) if m else set()
if not m:
    FAILS.append('SetsBridge.swift: the page → native switch was not found (trust_check.py needs updating)')
compare('Bridge ops', table('Bridge ops'), ops, 'bridge ops')

# lumina:// hosts
scheme = SWIFT['Lumina/Sets/Core/SetsSchemeHandler.swift']
m = re.search(r'switch host \{(.*?)\n        default:', scheme, re.S)
hosts = set(re.findall(r'^        case "([^"]+)"', m.group(1), re.M)) if m else set()
compare('`lumina://` hosts', table('`lumina://` hosts'), hosts, 'lumina:// hosts')

# Places the app sends the user
opens = {f for f, t in SWIFT.items() if 'NSWorkspace.shared.open(' in t}
compare('Places the app sends the user', table('Places the app sends the user'), opens, 'NSWorkspace.open call sites')

# URLs in the app's code
urls = set()
for t in SWIFT.values():
    urls |= set(re.findall(r'(?:https?|wss?|ftp)://([A-Za-z0-9.-]+)', t))
compare("URLs in the app's code", table("URLs in the app's code"), urls, 'URL hosts in Swift')

# Privacy manifest
pm = plistlib.load(open(os.path.join(ROOT, 'Lumina/Resources/PrivacyInfo.xcprivacy'), 'rb'))
cats = {a.get('NSPrivacyAccessedAPIType') for a in pm.get('NSPrivacyAccessedAPITypes', [])}
compare('Privacy manifest', table('Privacy manifest'), cats, 'required-reason APIs')
for k, want in (('NSPrivacyTracking', False), ('NSPrivacyTrackingDomains', []), ('NSPrivacyCollectedDataTypes', [])):
    if pm.get(k, want) != want:
        FAILS.append('PrivacyInfo.xcprivacy: %s is %r; TRUST.md says Lumina collects and tracks nothing' % (k, pm.get(k)))

# Bundled third-party code
vendor = {os.path.basename(f) for f in glob.glob(os.path.join(ROOT, 'design/handoff/vendor/*.js'))}
compare('Bundled third-party code', table('Bundled third-party code'), vendor, 'vendored files')

# Checked rules
NET = r'\b(URLSession|NSURLConnection|NSURLDownload|NWConnection|NWListener|NWBrowser|CFSocket\w*|CFStreamCreatePairWithSocket\w*|getaddrinfo|gethostbyname)\b|\bsocket\(|WKWebsiteDataStore\.default\(\)'
for f, t in SWIFT.items():
    for n, line in enumerate(t.split('\n'), 1):
        if re.search(NET, line):
            FAILS.append('%s: a networking API (%s): Lumina makes no network request (TRUST.md I5)' % (f, re.search(NET, line).group(0)))
        if re.search(r'\bNSLog\(|(?<![\w.])print\(|debugPrint\(', line):
            FAILS.append('%s: NSLog or print: log through LuminaLog, names and paths private (TRUST.md I8): %s' % (f, line.strip()[:100]))
plumbing = read('Lumina/Sets/Web/plumbing.js')
for n, line in enumerate(plumbing.split('\n'), 1):
    if re.search(r'(?:https?|wss?|ftp)://|\b(WebSocket|EventSource|XMLHttpRequest|RTCPeerConnection|importScripts)\b|sendBeacon', line):
        FAILS.append('plumbing.js:%d reaches for the network: %s' % (n, line.strip()[:100]))
for f in glob.glob(os.path.join(ROOT, '.github/workflows/*.yml')):
    for n, line in enumerate(open(f, encoding='utf-8'), 1):
        u = re.match(r'\s*-?\s*uses:\s*([^\s#]+)', line)
        if u and not u.group(1).startswith('./') and not re.search(r'@[0-9a-f]{40}$', u.group(1)):
            FAILS.append('%s:%d: an Action not pinned by commit: %s (TRUST.md I9)' % (os.path.relpath(f, ROOT), n, u.group(1)))
if 'XCRemoteSwiftPackageReference' in read('Lumina.xcodeproj/project.pbxproj'):
    FAILS.append('Lumina.xcodeproj: a Swift package reference; TRUST.md I9 says the build fetches nothing')
print(('ok   ' if not any('networking API' in x or 'NSLog' in x or 'plumbing.js' in x or 'Action' in x or 'package' in x for x in FAILS) else 'FAIL ') + 'checked rules: no networking API, no NSLog/print, plumbing offline, Actions pinned, no packages')

for x in FAILS:
    print('FAIL ' + x)
print('%d FAIL' % len(FAILS) if FAILS else 'all ok')
sys.exit(1 if FAILS else 0)
