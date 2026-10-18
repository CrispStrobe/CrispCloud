"""Isolated read-only SFTP fixture. Requires paramiko; never uses OS accounts."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import threading
import paramiko

root = Path(sys.argv[1]).resolve()
key = paramiko.RSAKey.generate(2048)
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen(8)
auth_requests = 0
lock = threading.Lock()

class Auth(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        global auth_requests
        with lock:
            auth_requests += 1
            (root / 'auth-count').write_text(str(auth_requests))
        return paramiko.AUTH_SUCCESSFUL if username == 'reader' and password == 'fixture-password' else paramiko.AUTH_FAILED
    def get_allowed_auths(self, username):
        return 'password'
    def check_channel_request(self, kind, channel_id):
        return paramiko.OPEN_SUCCEEDED if kind == 'session' else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

class ReadHandle(paramiko.SFTPHandle):
    def __init__(self, path):
        super().__init__()
        self.readfile = open(path, 'rb')
    def stat(self):
        return paramiko.SFTPAttributes.from_stat(os.fstat(self.readfile.fileno()))

class Files(paramiko.SFTPServerInterface):
    def canonicalize(self, path):
        # SFTP virtual root intentionally contains a symlink to test root checks.
        try:
            return '/' + str((root / path.lstrip('/')).resolve().relative_to(root))
        except ValueError:
            return '/outside-fixture'
    def local(self, path):
        candidate = root / path.lstrip('/')
        if not candidate.resolve().is_relative_to(root):
            raise PermissionError('outside fixture')
        return candidate
    def list_folder(self, path):
        try:
            rows = []
            for item in self.local(path).iterdir():
                row = paramiko.SFTPAttributes.from_stat(item.lstat())
                row.filename = item.name
                rows.append(row)
            return rows
        except OSError as error:
            return paramiko.SFTPServer.convert_errno(error.errno or 13)
    def stat(self, path):
        try: return paramiko.SFTPAttributes.from_stat(self.local(path).stat())
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno or 13)
    def lstat(self, path):
        try: return paramiko.SFTPAttributes.from_stat(self.local(path).lstat())
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno or 13)
    def open(self, path, flags, attr):
        if flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC): return paramiko.SFTP_PERMISSION_DENIED
        try: return ReadHandle(self.local(path))
        except OSError as error: return paramiko.SFTPServer.convert_errno(error.errno or 13)

connections = []
def serve(client):
    transport = paramiko.Transport(client)
    connections.append(transport)
    transport.add_server_key(key)
    transport.set_subsystem_handler('sftp', paramiko.SFTPServer, Files)
    try:
        transport.start_server(server=Auth())
        while transport.is_active(): threading.Event().wait(0.1)
    except (EOFError, OSError, paramiko.SSHException): pass
    finally: transport.close()

fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip('=')
print(json.dumps({'port': listener.getsockname()[1], 'hostKey': fingerprint}), flush=True)
while True:
    client, _ = listener.accept()
    threading.Thread(target=serve, args=(client,), daemon=True).start()
