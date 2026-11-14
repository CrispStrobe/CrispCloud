#!/usr/bin/env python3
import os,sys
from pathlib import Path
r=Path(__file__).resolve().parent.parent
t=r/'rustup/toolchains/1.100.0-x86_64-unknown-linux-gnu/bin'
os.environ['CARGO_HOME']=str(r/'cargo')
os.environ['RUSTUP_HOME']=str(r/'rustup')
os.environ['PATH']=str(t)+os.pathsep+os.environ.get('PATH','')
os.execv(str(t/'cargo'),['cargo',*sys.argv[1:]])
