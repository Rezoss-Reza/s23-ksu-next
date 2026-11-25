#!/usr/bin/env python3
# Copyright (c) 2026 Rezoss
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the reviewed stock-S23 cfg80211 overlay from the selected kernel header."""
import hashlib
from pathlib import Path
import subprocess
import sys

if len(sys.argv) != 4:
    raise SystemExit('usage: prepare-cfg80211.py KERNEL_HEADER PATCH_DIR OUTPUT_ROOT')
header, patches, output = map(Path, sys.argv[1:])
old_hash = 'ea18def5387ca567274f3a9c23105ed4f2dcfd3de6f4e822490eb6560ee9ac87'
old = b'const u8 *macaddr, const u8 *ie, u8 ie_len,'
new = b'const u8 *macaddr, const u8 *ie, size_t ie_len,'
data = header.read_bytes()
digest = lambda content: hashlib.sha256(content).hexdigest()
if digest(data) != old_hash:
    # Android 5.15.226 changed only this declaration in the audited Samsung
    # header. The ROM supplies the S23 vendor cfg80211 module, so retain its
    # historical API declaration and verify linked drivers do not import it.
    if data.count(new) != 1 or digest(data.replace(new, old)) != old_hash:
        raise SystemExit(f'Unreviewed cfg80211.h SHA-256: {digest(data)}')
    data = data.replace(new, old)
    print('Validated 5.15.226 peer-candidate declaration difference')
target = output / 'include/net/cfg80211.h'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(data)
for pattern in ('0009-*.patch', '0010-*.patch', '0011-*.patch'):
    matches = list(patches.glob(pattern))
    if len(matches) != 1:
        raise SystemExit(f'Missing or ambiguous compatibility patch: {pattern}')
    for mode in (['--dry-run'], []):
        subprocess.run(['patch', '--batch', '--fuzz=0', *mode, '-p1', '-i', str(matches[0].resolve())], cwd=output, check=True)
print('Generated reviewed Samsung cfg80211 compatibility header:', digest(target.read_bytes()))
