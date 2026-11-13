"""Record scoped local audit commands; no production repository writes."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, time

parser = argparse.ArgumentParser()
parser.add_argument('--name', required=True)
parser.add_argument('--cwd', type=Path, required=True)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
base = Path(__file__).resolve().parent
toolchain = base.parent / 'toolchains/rust-1.100.0/bin'
env = os.environ.copy()
env.update(PATH=str(toolchain) + os.pathsep + env['PATH'],
           CARGO_HOME=str(base.parent / 'toolchains/cargo-crisp-docx'),
           TMPDIR=str(base.parent / 'tmp'))
command = args.command[1:] if args.command[0] == '--' else args.command
start = time.time()
log = base / (args.name + '.log')
with log.open('wb') as handle:
    result = subprocess.run(command, cwd=args.cwd, env=env,
                            stdout=handle, stderr=subprocess.STDOUT)
receipt = dict(argv=command, cwd=str(args.cwd), exitCode=result.returncode,
               seconds=time.time() - start, log=log.name,
               logBytes=log.stat().st_size,
               logSha256=hashlib.sha256(log.read_bytes()).hexdigest(),
               environment={k: env[k] for k in ['PATH','CARGO_HOME','TMPDIR']})
(base / (args.name + '.command.json')).write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
print(log.read_text(errors='replace')[-2000:])
raise SystemExit(result.returncode)
