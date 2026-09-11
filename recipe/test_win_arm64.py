"""Exercise the installed native core, including LAZ and GDAL/PROJ reprojection."""

import csv
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import tempfile


bin_dir = Path(os.environ["LIBRARY_BIN"])
pdal = bin_dir / "pdal.exe"
plugins = sorted(bin_dir.glob("libpdal_plugin_*.dll"))
# PDAL always installs its small faux kernel with the core build.
assert {p.name for p in plugins} <= {"libpdal_plugin_kernel_fauxplugin.dll"}, plugins
for binary in (pdal, bin_dir / "pdalcpp.dll", *plugins):
    with binary.open("rb") as stream:
        assert stream.read(2) == b"MZ", binary
        stream.seek(0x3C)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        assert stream.read(4) == b"PE\0\0", binary
        assert struct.unpack("<H", stream.read(2))[0] == 0xAA64, binary
    print(f"Verified native ARM64: {binary}", flush=True)

subprocess.run([pdal, "--version"], check=True)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    points = root / "points.csv"
    points.write_text("X,Y,Z\n0,0,10\n1,1,20\n2,2,30\n", encoding="utf-8")
    laz = root / "projected.laz"
    output = root / "projected.csv"

    def pipeline(stages):
        subprocess.run(
            [pdal, "pipeline", "--stdin"],
            input=json.dumps({"pipeline": stages}),
            text=True,
            check=True,
        )

    pipeline([
        {"type": "readers.text", "filename": str(points)},
        {"type": "filters.reprojection", "in_srs": "EPSG:4326", "out_srs": "EPSG:3857"},
        {"type": "writers.las", "filename": str(laz), "a_srs": "EPSG:3857", "compression": True,
         "scale_x": 0.001, "scale_y": 0.001, "scale_z": 0.001},
    ])
    assert laz.stat().st_size > 0
    pipeline([
        {"type": "readers.las", "filename": str(laz)},
        {"type": "writers.text", "filename": str(output), "order": "X,Y,Z",
         "keep_unspecified": False, "precision": 8},
    ])
    with output.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 3, rows
    for i, row in enumerate(rows):
        expected = (
            6378137.0 * math.radians(i),
            6378137.0 * math.log(math.tan(math.pi / 4 + math.radians(i) / 2)),
            (i + 1) * 10,
        )
        for axis, value in zip(("X", "Y", "Z"), expected):
            assert math.isclose(float(row[axis]), value, rel_tol=0, abs_tol=0.002), row

print("PASS: native core, LAZ round-trip, point count, and GDAL/PROJ coordinates")
