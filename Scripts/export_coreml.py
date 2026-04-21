#!/usr/bin/env python3
"""
One-time export: yolo11s.pt → VeloYOLO.mlpackage

Usage (from repo root, with the velo-films Python venv active):
    python Scripts/export_coreml.py

Output:
    Shared/ML/VeloYOLO.mlpackage   — add this to the Xcode project

Requirements:
    pip install ultralytics coremltools

Notes:
- nms=False: Vision framework handles NMS natively; baking it in bloats the model
- int8 quantisation cuts the package from ~12MB to ~3MB with negligible accuracy loss
  on the 11 object classes we care about (person, bicycle, car, motorcycle, bus, truck,
  traffic light, stop sign)
- imgsz=640 matches YOLO_IMAGE_SIZE in config.py
"""

from pathlib import Path
import sys

try:
    from ultralytics import YOLO
except ImportError:
    sys.exit("ultralytics not found — run: pip install ultralytics coremltools")

YOLO_PT = Path(__file__).parent.parent.parent / "velo-films" / "yolo11s.pt"
OUT_DIR = Path(__file__).parent.parent / "Shared" / "ML"

if not YOLO_PT.exists():
    sys.exit(f"Model not found at {YOLO_PT}")

OUT_DIR.mkdir(parents=True, exist_ok=True)

print(f"Loading {YOLO_PT} ...")
model = YOLO(str(YOLO_PT))

print("Exporting to Core ML (int8, nms=False, imgsz=640) ...")
exported = model.export(
    format="coreml",
    imgsz=640,
    nms=False,
    int8=True,
)

# ultralytics exports alongside the .pt file; move to project location
exported_path = Path(exported)
dest = OUT_DIR / "VeloYOLO.mlpackage"
if dest.exists():
    import shutil
    shutil.rmtree(dest)
exported_path.rename(dest)

print(f"\nDone: {dest}")
print("Next steps:")
print("  1. Open VeloFilms.xcodeproj in Xcode")
print("  2. Drag Shared/ML/VeloYOLO.mlpackage into the Xcode project navigator")
print("  3. Set target membership: both VeloFilms (macOS) and VeloFilms (iOS)")
