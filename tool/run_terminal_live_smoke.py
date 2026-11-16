#!/usr/bin/env python3
"""Run production SSH tests against disposable loopback OpenSSH servers.

Requires sshd, ssh-keygen and the repository's pinned Flutter toolchain. All
keys, host trust records and servers are temporary. Nothing connects externally.
"""

import argparse
import getpass
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--with-pty", action="store_true", help="Also exercise interactive PTY; sshd must have login-record permissions.")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    sshd = shutil.which("sshd")
    keygen = shutil.which("ssh-keygen")
    if not sshd or not keygen:
        parser.error("Install OpenSSH server/client tools before running this check.")
    project = args.project.resolve()
    scratch = project / ".dart_tool" / "terminal-live-smoke"
    scratch.mkdir(parents=True, exist_ok=True)
    processes = []
    logs = []
    with tempfile.TemporaryDirectory(prefix="route-", dir=scratch) as directory:
        root = Path(directory)
        username = getpass.getuser()
        try:
            for name in ("client", "jump", "target"):
                subprocess.run([keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(root / name)], check=True)
            ports = {}
            for name in ("jump", "target"):
                port = free_port()
                ports[name] = port
                configuration = root / f"{name}.conf"
                configuration.write_text(f"""Port {port}
ListenAddress 127.0.0.1
HostKey "{root / name}"
PidFile "{root / (name + '.pid')}"
AuthorizedKeysFile "{root / 'client.pub'}"
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
StrictModes no
AllowUsers {username}
AllowTcpForwarding yes
PermitTTY yes
X11Forwarding no
PrintMotd no
LogLevel VERBOSE
""")
                subprocess.run([sshd, "-t", "-f", str(configuration)], check=True)
                log = open(root / f"{name}.log", "w+")
                logs.append(log)
                process = subprocess.Popen([sshd, "-D", "-e", "-f", str(configuration)], stdout=log, stderr=log)
                processes.append(process)
                for _ in range(100):
                    if process.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(f"OpenSSH fixture exited: {log.read()}")
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                            break
                    except OSError:
                        time.sleep(0.05)
                else:
                    raise RuntimeError("OpenSSH fixture did not start within five seconds")
            environment = dict(os.environ)
            environment.update({
                "CRISPCLOUD_LIVE_SSH_KEY": str(root / "client"),
                "CRISPCLOUD_LIVE_SSH_USER": username,
                "CRISPCLOUD_LIVE_SSH_JUMP_PORT": str(ports["jump"]),
                "CRISPCLOUD_LIVE_SSH_TARGET_PORT": str(ports["target"]),
                "CRISPCLOUD_LIVE_SSH_PTY": "1" if args.with_pty else "0",
            })
            result = subprocess.run([
                args.flutter, "test", "--no-pub", "--concurrency=1", "--reporter=expanded",
                "test/ssh_terminal_live_test.dart",
                "test/ssh_port_forwarding_live_test.dart",
            ], cwd=project, env=environment)
            if result.returncode:
                for name, log in zip(("jump", "target"), logs):
                    log.flush()
                    log.seek(0)
                    print(f"OpenSSH {name} fixture log:\n{log.read()}", flush=True)
            return result.returncode
        finally:
            for process in reversed(processes):
                process.terminate()
            for process in reversed(processes):
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for log in logs:
                log.close()


if __name__ == "__main__":
    raise SystemExit(main())
