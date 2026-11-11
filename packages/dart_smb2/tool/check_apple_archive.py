"""Exercise the install_name_tool operation that failed in long checkout paths."""
import pathlib
import subprocess
import sys
import tempfile
import zipfile

for archive in sys.argv[1:]:
    checked = 0
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                if not (entry.filename.endswith("/libsmb2.framework/libsmb2") or entry.filename.endswith("/Versions/A/libsmb2")):
                    continue
                if entry.external_attr >> 16 & 0o170000 == 0o120000:
                    continue  # macOS framework's top-level symlink
                binary = pathlib.Path(temp) / str(checked)
                binary.write_bytes(bundle.read(entry))
                name = "@rpath/" + "long_checkout_segment/" * 20 + "libdart_smb2.dylib"
                subprocess.run(["xcrun", "install_name_tool", "-id", name, str(binary)], check=True)
                subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True)
                info = subprocess.check_output(["xcrun", "otool", "-D", str(binary)], text=True)
                assert name in info, info
                checked += 1
    assert checked > 0, f"No framework binaries checked: {archive}"
    print(f"Verified {checked} Apple framework slices with a long install name")
