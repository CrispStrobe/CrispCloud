#!/usr/bin/env python3
"""Optional local native signing probe after prepare; creates only temporary test keychain items.
Requires the prepared environment, macOS and an unlocked user session.
This does not build the complete CrispCloud application or submit it to App Store Connect.
"""
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import macos_public_signing as signing
runner=Path(signing.required('RUNNER_TEMP'))
runner=Path(tempfile.mkdtemp(prefix='crisp-public-signing-live-',dir=runner))
app=runner/'CrispCloud Signing Probe.app'
assert runner.name.startswith('crisp-public-signing-live-')
macos=app/'Contents/MacOS';macos.mkdir(parents=True)
source=signing.ROOT/'test/native/developer_id_keychain_probe.m'
subprocess.run(['clang','-fobjc-arc',str(source),'-framework','Foundation','-framework','Security','-o',str(macos/'Probe')],check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Probe','CFBundleIdentifier':signing.BUNDLE,'CFBundleName':'CrispCloud Signing Probe','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.0.0','CFBundleVersion':'1','LSMinimumSystemVersion':'12.0'}))
extension=app/'Contents/PlugIns/FinderExtension.appex';(extension/'Contents/MacOS').mkdir(parents=True)
stub=runner/'extension.c';stub.write_text('int main(void) { return 0; }\n')
subprocess.run(['clang',str(stub),'-o',str(extension/'Contents/MacOS/ProbeExtension')],check=True)
(extension/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'ProbeExtension','CFBundleIdentifier':signing.EXTENSION,'CFBundlePackageType':'XPC!','CFBundleVersion':'1','CFBundleShortVersionString':'0.0.0','NSExtension':{'NSExtensionPointIdentifier':'com.apple.FinderSync','NSExtensionPrincipalClass':'FIFinderSync'}}))
# Exercise the exact optional universal helper and direct entitlement selection.
import base64
os.environ.update(SRCROOT=str(signing.ROOT/'macos'),TARGET_BUILD_DIR=str(runner),UNLOCALIZED_RESOURCES_FOLDER_PATH=app.name+'/Contents/Resources',CRISP_BUILD_PROFILE='github',DART_DEFINES=','.join(base64.b64encode(v.encode()).decode() for v in ['CRISP_DISTRIBUTION=github','CRISP_ENABLE_FUSE=true']),EXPANDED_CODE_SIGN_IDENTITY='-')
subprocess.run(['sh',str(signing.ROOT/'macos/build_fuse_bridge.sh')],check=True)
# Probe Data Protection access with the same identity/profile before notarization.
shutil.copyfile(os.environ['APP_DEVID_PROFILE'],app/'Contents/embedded.provisionprofile')
ent=runner/'probe-entitlements.plist';signing.entitlements(signing.ROOT/'macos/Runner/Direct.entitlements',signing.BUNDLE,os.environ['APPLE_TEAM_ID'],ent)
subprocess.run(['codesign','--force','--timestamp','--options','runtime','--keychain',os.environ['CRISP_SIGNING_KEYCHAIN'],'--sign',os.environ['DEVELOPER_ID_SHA1'],'--entitlements',str(ent),str(app)],check=True)
subprocess.run([str(macos/'Probe')],check=True)
signing.sign(app,runner/'artifacts')
(runner/'live-acceptance.json').write_text(json.dumps({'dataProtectionKeychain':'passed','notarizedApp':'passed','notarizedDmg':'passed','source':'native signing probe, not the complete CrispCloud application'},indent=2)+'\n')
print('Live native signing/notarization fixture completed; no existing credentials were read or changed.')
