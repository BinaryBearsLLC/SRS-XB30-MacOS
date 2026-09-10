#!/usr/bin/env python3
"""Copy native labels/help into the local web demo; no Bluetooth operations."""
import json, re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
s = (root / 'Sources/XB30Control.swift').read_text()
help_block = s.split('enum ControlHelp {', 1)[1].split('\n}', 1)[0]
help_text = dict(re.findall(r'static let (\w+) = "([^"]+)"', help_block))
names = json.loads(re.search(r'static let names = (\[.*?\])', s).group(1))
(root / 'website/app/native-controls.json').write_text(json.dumps({'help': help_text, 'lightNames': names}, indent=2) + '\n')
