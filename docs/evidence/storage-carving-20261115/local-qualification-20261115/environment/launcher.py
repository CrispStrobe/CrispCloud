#!/usr/bin/env python3
import os, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
env=os.environ.copy()
env.update({
 'PUB_CACHE':str(ROOT/'pub-cache'), 'TMPDIR':str(ROOT/'tmp'),
 'XDG_CACHE_HOME':str(ROOT/'cache'), 'XDG_CONFIG_HOME':str(ROOT/'config'),
 'CARGO_HOME':str(ROOT/'cargo-home'), 'RUSTUP_HOME':str(ROOT/'rustup-home'),
 'FLUTTER_ROOT':str(ROOT/'flutter'),
 'DART_DISABLE_ANALYTICS':'true', 'FLUTTER_SUPPRESS_ANALYTICS':'true', 'CI':'true',
 'PATH':os.pathsep.join([str(ROOT/'bin'),str(ROOT/'cargo-home/bin'),str(ROOT/'flutter/bin'),env.get('PATH','')]),
 'LD_LIBRARY_PATH':os.pathsep.join([str(ROOT/'lib'),str(ROOT/'debian/root/usr/lib/x86_64-linux-gnu'),str(ROOT/'debian/root/usr/lib/llvm-19/lib'),env.get('LD_LIBRARY_PATH','')]),
})
command=sys.argv[1:]
if not command:raise SystemExit('Usage: run.py flutter|dart|command ...')
if command[0]=='flutter':command[0]=str(ROOT/'flutter/bin/flutter')
elif command[0]=='dart':command[0]=str(ROOT/'flutter/bin/cache/dart-sdk/bin/dart')
raise SystemExit(subprocess.call(command, env=env))
