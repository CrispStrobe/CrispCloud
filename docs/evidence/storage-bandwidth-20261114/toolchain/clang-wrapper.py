#!/usr/bin/env python3
import os,sys
from pathlib import Path
r=Path(__file__).resolve().parent.parent/'debian/root'
os.environ['LD_LIBRARY_PATH']=str(r/'usr/lib/x86_64-linux-gnu')+os.pathsep+str(r/'usr/lib/llvm-19/lib')+(os.pathsep+os.environ['LD_LIBRARY_PATH'] if os.environ.get('LD_LIBRARY_PATH') else '')
os.execv(str(r/'usr/lib/llvm-19/bin/clang'),['clang',*sys.argv[1:]])
