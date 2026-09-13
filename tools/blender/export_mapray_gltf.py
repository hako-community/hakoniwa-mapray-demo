"""Build and audit Mapray Cloud glTF assets from the Hakoniwa drone GLBs.

Run this file with Blender, not the system Python. Arguments are supplied after
Blender's ``--`` separator; see ``scripts/windows/build_mapray_model_assets.ps1``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

import bpy
from mathutils import Vector


ASSETS = (
    {
        "role": "airframe",
        "source": "origin_01_body.glb",
        "output": "origin-01-airframe.gltf",
    },
    {
        "role": "propeller",
        "source": "propeller_origin_01.glb",
        "output": "origin-01-propeller.gltf",
    },
)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--license", type=Path, required=True)
    return parser.parse_args(argv)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_gltf(path: Path) -> None:
    result = bpy.ops.import_scene.gltf(filepath=str(path))
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender import failed: {path} ({result})")


def scene_audit() -> dict[str, object]:
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    points = [
        obj.matrix_world @ Vector(corner)
        for obj in mesh_objects
        for corner in obj.bound_box
    ]
    if not points:
        raise RuntimeError("Imported scene has no mesh bounds")
    minimum = [min(point[index] for point in points) for index in range(3)]
    maximum = [max(point[index] for point in points) for index in range(3)]
    dimensions = [maximum[index] - minimum[index] for index in range(3)]
    materials = {material.name for obj in mesh_objects for material in obj.data.materials if material}
    images = {image.name for image in bpy.data.images}
    object_bounds = []
    for obj in mesh_objects:
        object_points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        object_minimum = [min(point[index] for point in object_points) for index in range(3)]
        object_maximum = [max(point[index] for point in object_points) for index in range(3)]
        object_bounds.append({
            "name": obj.name,
            "origin": list(obj.matrix_world.translation),
            "center": [
                (object_minimum[index] + object_maximum[index]) / 2 for index in range(3)
            ],
            "dimensions": [
                object_maximum[index] - object_minimum[index] for index in range(3)
            ],
        })
    return {
        "objects": len(bpy.context.scene.objects),
        "meshes": len(mesh_objects),
        "materials": len(materials),
        "images": len(images),
        "objectBounds": object_bounds,
        "boundsMeters": {
            "minimum": minimum,
            "maximum": maximum,
            "dimensions": dimensions,
        },
    }


def export_gltf(path: Path) -> None:
    result = bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLTF_SEPARATE",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender export failed: {path} ({result})")


def validate_uri(uri: str, gltf_path: Path) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme or parsed.netloc or uri.startswith(("/", "\\")):
        raise RuntimeError(f"External or absolute URI is not allowed: {uri}")
    uri_path = Path(uri)
    if ".." in uri_path.parts or uri_path.drive:
        raise RuntimeError(f"URI escapes the dataset directory: {uri}")
    target = (gltf_path.parent / uri_path).resolve()
    if target.parent != gltf_path.parent.resolve():
        raise RuntimeError(f"URI escapes the dataset directory: {uri}")
    if not target.is_file():
        raise RuntimeError(f"Referenced resource is missing: {target}")
    return target


def inspect_gltf(path: Path) -> dict[str, object]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("asset", {}).get("version") != "2.0":
        raise RuntimeError(f"Not a glTF 2.0 asset: {path}")
    for forbidden in ("animations", "cameras"):
        if document.get(forbidden):
            raise RuntimeError(f"Unexpected {forbidden} in {path}")
    if document.get("extensions", {}).get("KHR_lights_punctual"):
        raise RuntimeError(f"Unexpected lights in {path}")

    resources: list[dict[str, object]] = []
    for record in (*document.get("buffers", []), *document.get("images", [])):
        uri = record.get("uri")
        if not uri:
            continue
        target = validate_uri(str(uri), path)
        resources.append(
            {
                "path": target.name,
                "bytes": target.stat().st_size,
                "sha256": sha256(target),
            }
        )
    return {
        "path": path.name,
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "version": "2.0",
        "scenes": len(document.get("scenes", [])),
        "nodes": len(document.get("nodes", [])),
        "meshes": len(document.get("meshes", [])),
        "materials": len(document.get("materials", [])),
        "resources": resources,
    }


def assert_bounds_equal(before: dict[str, object], after: dict[str, object]) -> None:
    before_bounds = before["boundsMeters"]
    after_bounds = after["boundsMeters"]
    assert isinstance(before_bounds, dict) and isinstance(after_bounds, dict)
    tolerance = 1.0e-5
    for key in ("minimum", "maximum", "dimensions"):
        left = before_bounds[key]
        right = after_bounds[key]
        if any(abs(float(a) - float(b)) > tolerance for a, b in zip(left, right)):
            raise RuntimeError(f"Bounds changed after re-import ({key}): {left} != {right}")


def safe_replace_directory(staged: Path, destination: Path, output_root: Path) -> None:
    output_root = output_root.resolve()
    destination = destination.resolve()
    if destination.parent != output_root or destination.name not in {"airframe", "propeller"}:
        raise RuntimeError(f"Refusing to replace unexpected directory: {destination}")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.move(str(staged), str(destination))


def main() -> None:
    args = parse_args()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    license_path = args.license.resolve()
    if not source_root.is_dir() or not license_path.is_file():
        raise FileNotFoundError("Source model directory or license file is missing")
    if output_root == Path(output_root.anchor):
        raise RuntimeError("Output root must not be a drive root")

    output_root.mkdir(parents=True, exist_ok=True)
    staging_root = output_root / f".staging-{os.getpid()}"
    if staging_root.exists():
        raise RuntimeError(f"Staging directory already exists: {staging_root}")
    staging_root.mkdir()

    manifest_assets: list[dict[str, object]] = []
    try:
        for asset in ASSETS:
            source_path = source_root / str(asset["source"])
            if not source_path.is_file():
                raise FileNotFoundError(source_path)
            role_dir = staging_root / str(asset["role"])
            role_dir.mkdir()
            output_path = role_dir / str(asset["output"])

            reset_scene()
            import_gltf(source_path)
            source_audit = scene_audit()
            export_gltf(output_path)
            gltf_audit = inspect_gltf(output_path)

            reset_scene()
            import_gltf(output_path)
            reimport_audit = scene_audit()
            assert_bounds_equal(source_audit, reimport_audit)

            manifest_assets.append(
                {
                    "role": asset["role"],
                    "source": source_path.name,
                    "sourceBytes": source_path.stat().st_size,
                    "sourceSha256": sha256(source_path),
                    "sourceAudit": source_audit,
                    "gltf": gltf_audit,
                    "reimportAudit": reimport_audit,
                }
            )

        staged_license = staging_root / "LICENSE.txt"
        shutil.copy2(license_path, staged_license)
        manifest = {
            "schemaVersion": 2,
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "purpose": "Mapray JS 0.9.6 ModelEntity assets",
            "generator": {
                "name": "Blender",
                "version": bpy.app.version_string,
                "exportFormat": "GLTF_SEPARATE",
                "animations": False,
                "cameras": False,
                "lights": False,
            },
            "license": {
                "path": license_path.name,
                "sha256": sha256(license_path),
            },
            "assets": manifest_assets,
        }
        staged_manifest = staging_root / "manifest.json"
        staged_manifest.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

        for asset in ASSETS:
            role = str(asset["role"])
            safe_replace_directory(staging_root / role, output_root / role, output_root)
        os.replace(staged_license, output_root / "LICENSE.txt")
        os.replace(staged_manifest, output_root / "manifest.json")
    finally:
        if staging_root.exists():
            shutil.rmtree(staging_root)

    print(json.dumps({"status": "pass", "manifest": str(output_root / "manifest.json")}))


if __name__ == "__main__":
    main()
