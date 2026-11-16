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
    parser.add_argument("--with-unix-agent", action="store_true", help="Also use a disposable real ssh-agent and remote ssh-add when Unix sockets are permitted.")
    parser.add_argument("--agent-only", action="store_true", help="Run only agent authentication and rekey acceptance.")
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
    log_names = []
    with tempfile.TemporaryDirectory(prefix="route-", dir=scratch) as directory:
        root = Path(directory)
        username = getpass.getuser()
        try:
            for name in ("client", "jump", "target"):
                subprocess.run([keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(root / name)], check=True)
            subprocess.run([keygen, "-q", "-t", "rsa", "-b", "2048", "-N", "", "-f", str(root / "client_rsa")], check=True)
            (root / "authorized_keys").write_text(
                (root / "client.pub").read_text() + (root / "client_rsa.pub").read_text()
            )
            ports = {}
            for name in ("jump", "target"):
                port = free_port()
                ports[name] = port
                configuration = root / f"{name}.conf"
                configuration.write_text(f"""Port {port}
ListenAddress 127.0.0.1
HostKey "{root / name}"
PidFile "{root / (name + '.pid')}"
AuthorizedKeysFile "{root / 'authorized_keys'}"
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PubkeyAcceptedAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
UsePAM no
StrictModes no
AllowUsers {username}
AllowTcpForwarding yes
AllowAgentForwarding yes
PermitTTY yes
X11Forwarding no
PrintMotd no
LogLevel VERBOSE
""")
                subprocess.run([sshd, "-t", "-f", str(configuration)], check=True)
                log = open(root / f"{name}.log", "w+")
                logs.append(log)
                log_names.append(name)
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
            unix_agent = False
            unix_agent_reason = "Use --with-unix-agent on a host that permits Unix sockets."
            if args.with_unix_agent:
                agent = shutil.which("ssh-agent")
                add = shutil.which("ssh-add")
                if not agent or not add or not hasattr(socket, "AF_UNIX"):
                    unix_agent_reason = "Unix ssh-agent/ssh-add prerequisites are unavailable."
                else:
                    try:
                        with socket.socket(socket.AF_UNIX) as probe:
                            probe.bind(str(root / "agent-probe.sock"))
                        (root / "agent-probe.sock").unlink()
                    except OSError as error:
                        unix_agent_reason = f"Host rejected Unix-socket creation: {error}"
                    else:
                        agent_socket = root / "agent.sock"
                        log = open(root / "agent.log", "w+")
                        logs.append(log)
                        log_names.append("agent")
                        process = subprocess.Popen([agent, "-D", "-a", str(agent_socket)], stdout=log, stderr=log)
                        processes.append(process)
                        for _ in range(100):
                            if process.poll() is not None:
                                log.seek(0)
                                raise RuntimeError(f"ssh-agent fixture exited: {log.read()}")
                            if agent_socket.exists():
                                break
                            time.sleep(0.05)
                        else:
                            raise RuntimeError("ssh-agent fixture did not start within five seconds")
                        environment.update({"SSH_AUTH_SOCK": str(agent_socket), "SSH_ASKPASS_REQUIRE": "never"})
                        subprocess.run([add, "-t", "120", str(root / "client")], env=environment, stdin=subprocess.DEVNULL, check=True)
                        unix_agent = True
                        unix_agent_reason = ""
                if not unix_agent:
                    print(f"Optional real Unix-agent acceptance skipped: {unix_agent_reason}", flush=True)
            environment.update({
                "CRISPCLOUD_LIVE_SSH_KEY": str(root / "client"),
                "CRISPCLOUD_LIVE_SSH_RSA_KEY": str(root / "client_rsa"),
                "CRISPCLOUD_LIVE_SSH_USER": username,
                "CRISPCLOUD_LIVE_SSH_JUMP_PORT": str(ports["jump"]),
                "CRISPCLOUD_LIVE_SSH_TARGET_PORT": str(ports["target"]),
                "CRISPCLOUD_LIVE_SSH_PTY": "1" if args.with_pty else "0",
                "CRISPCLOUD_LIVE_UNIX_AGENT": "1" if unix_agent else "0",
                "CRISPCLOUD_LIVE_UNIX_AGENT_REASON": unix_agent_reason,
            })
            suites = ["test/ssh_agent_live_test.dart"] if args.agent_only else [
                "test/ssh_terminal_live_test.dart",
                "test/ssh_port_forwarding_live_test.dart",
                "test/ssh_agent_live_test.dart",
            ]
            result = subprocess.run([
                args.flutter, "test", "--no-pub", "--concurrency=1", "--reporter=expanded",
                *suites,
            ], cwd=project, env=environment)
            if result.returncode:
                for name, log in zip(log_names, logs):
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
