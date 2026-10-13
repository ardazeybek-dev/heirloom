"""Decode every symbol from qr-dump.mjs with OpenCV and compare the text."""
import json, subprocess, sys
import cv2
import numpy as np

raw = subprocess.run(["node", "scripts/qr-dump.mjs"], capture_output=True, check=True).stdout
cases = json.loads(raw.decode("utf-8"))
# OpenCV's classic detector struggles to *locate* large symbols (v19+), so a
# case passes when either detector decodes it at any of a few scales.
detectors = [cv2.QRCodeDetector(), cv2.QRCodeDetectorAruco()]


def decode(base):
    for scale in (4, 6, 8):
        img = cv2.resize(base, None, fx=scale, fy=scale, interpolation=cv2.INTER_NEAREST)
        for detector in detectors:
            text, _, _ = detector.detectAndDecode(img)
            if text:
                return text
    return ""

failures = 0
versions = set()
for c in cases:
    if c.get("error"):
        print("encode error", c["lvl"], len(c["text"])); failures += 1; continue
    m = np.array(c["modules"], dtype=np.uint8)
    img = np.where(m == 1, 0, 255).astype(np.uint8)
    img = np.pad(img, 4, constant_values=255)
    text = decode(img)
    versions.add(c["version"])
    if text != c["text"]:
        failures += 1
        print(f"FAIL v{c['version']} {c['ecl']} mask{c['mask']} len={len(c['text'])} got={text[:30]!r}")
print(f"{len(cases) - failures}/{len(cases)} decoded; versions covered: {sorted(versions)}")
sys.exit(1 if failures else 0)
