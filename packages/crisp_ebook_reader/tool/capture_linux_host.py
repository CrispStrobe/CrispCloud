"""Capture the real X11 framebuffer and count independently colored markers."""
from pathlib import Path
import json
import sys
from PIL import Image
from Xlib import X, display

target = Path(sys.argv[1])
target.parent.mkdir(parents=True, exist_ok=True)
connection = display.Display()
root = connection.screen().root
geometry = root.get_geometry()
shot = root.get_image(0, 0, geometry.width, geometry.height, X.ZPixmap, 0xFFFFFFFF)
image = Image.frombytes("RGB", (geometry.width, geometry.height), shot.data, "raw", "BGRX")
image.save(target)
colors = image.getcolors(geometry.width * geometry.height) or []
counts = {color: count for count, color in colors}
print(json.dumps({"greenBookPixels": counts.get((31, 89, 71), 0),
                  "magentaFlutterPixels": counts.get((255, 0, 255), 0),
                  "width": geometry.width, "height": geometry.height}))
connection.close()
