"""Isolated, authenticated SMB2 fixture; never registers an OS file share."""
import json
import logging
import sys
from impacket.smbserver import SimpleSMBServer
from impacket.ntlm import compute_lmhash, compute_nthash
from impacket import smb3structs as smb2

logging.disable(logging.CRITICAL)
server = SimpleSMBServer(listenAddress='127.0.0.1', listenPort=0)
server.setSMB2Support(True)
server.addShare('books', sys.argv[1], readOnly='no')
server.addCredential('reader', 0, compute_lmhash('fixture-password'), compute_nthash('fixture-password'))

# Impacket returns success-shaped bodies for some failed file commands. A
# strict SMB client correctly rejects those malformed replies. Normalize only
# the error body; retain the handler's actual status and authentication result.
def normalize_errors(handler):
    def run(*args):
        commands, packets, status = handler(*args)
        if status != 0 and packets is None:
            commands = [smb2.SMB2Error()]
        return commands, packets, status
    return run

for command in (smb2.SMB2_CREATE, smb2.SMB2_CLOSE, smb2.SMB2_QUERY_INFO,
                smb2.SMB2_SET_INFO, smb2.SMB2_READ, smb2.SMB2_WRITE,
                smb2.SMB2_QUERY_DIRECTORY, smb2.SMB2_FLUSH):
    handler = server.getServer().hookSmb2Command(command, None)
    server.getServer().hookSmb2Command(command, normalize_errors(handler))
print(json.dumps({'port': server.getServer().socket.getsockname()[1]}), flush=True)
server.start()
