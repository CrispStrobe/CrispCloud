"""Isolated, authenticated SMB2 fixture; never registers an OS file share."""
import json
import logging
import os
import time
import sys
from impacket.smbserver import SimpleSMBServer
from impacket.ntlm import compute_lmhash, compute_nthash
from impacket import smb3structs as smb2

logging.disable(logging.CRITICAL)
server = SimpleSMBServer(listenAddress='127.0.0.1',
                        listenPort=int(sys.argv[2]) if len(sys.argv) > 2 else 0)
server.setSMB2Support(True)
server.addShare('books', sys.argv[1], readOnly='no')
server.addCredential('reader', 0, compute_lmhash('fixture-password'), compute_nthash('fixture-password'))

# Impacket returns success-shaped bodies for some failed file commands. A
# strict SMB client correctly rejects those malformed replies. Normalize only
# the error body; retain the handler's actual status and authentication result.
def normalize_errors(handler, command):
    def run(*args):
        existed = False
        disposition = None
        if command == smb2.SMB2_CREATE:
            request = smb2.SMB2Create(args[2]['Data'])
            name = request['Buffer'][:request['NameLength']].decode('utf-16le').replace('\\', '/')
            existed = os.path.exists(os.path.join(sys.argv[1], name))
            disposition = request['CreateDisposition']
        commands, packets, status = handler(*args)
        # Impacket copies request CreateDisposition into response CreateAction,
        # but these are different enums (OVERWRITE_IF=5 is not a valid action).
        if status == 0 and disposition is not None and packets is None:
            action = {0: 0 if existed else 2, 1: 1, 2: 2,
                      3: 1 if existed else 2, 4: 3, 5: 3 if existed else 2}[disposition]
            for response in commands:
                response['CreateAction'] = action
                # The fixture also writes the SMB1 field name into an SMB2
                # CREATE reply; copy it to the actual wire field.
                if 'LastChangeTime' in response.fields:
                    response['ChangeTime'] = response['LastChangeTime']
        if status != 0 and packets is None:
            commands = [smb2.SMB2Error()]
        return commands, packets, status
    return run

for command in (smb2.SMB2_CREATE, smb2.SMB2_CLOSE, smb2.SMB2_QUERY_INFO,
                smb2.SMB2_SET_INFO, smb2.SMB2_READ, smb2.SMB2_WRITE,
                smb2.SMB2_QUERY_DIRECTORY, smb2.SMB2_FLUSH):
    handler = server.getServer().hookSmb2Command(command, None)
    if command == smb2.SMB2_READ and os.environ.get('CRISP_SMB_FIXTURE_DELAY'):
        def delayed(*args, original=handler):
            time.sleep(float(os.environ['CRISP_SMB_FIXTURE_DELAY']))
            return original(*args)
        handler = delayed
    server.getServer().hookSmb2Command(command, normalize_errors(handler, command))
print(json.dumps({'port': server.getServer().socket.getsockname()[1]}), flush=True)
server.start()
