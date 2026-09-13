"""Build normalized Mapray assets from the complete origin-01 drone model.

The propeller mesh is baked relative to the motor parent pivot.  This preserves
the rotation centre which is lost in the independently exported propeller GLB.
Run with Blender's Python interpreter.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys

import bpy
from mathutils import Matrix, Vector


AIRFRAME_MESHES = (
    "body", "Cube", "D1", "Front", "D2", "D3", "D4", "D4 (1)", "D4 (2)", "frame",
)
MOTOR_NAMES = ("motor_0", "motor_1", "motor_3", "motor_2")
PROPELLER_MESH = "Visual.002"


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--license", type=Path, required=True)
    return parser.parse_args(argv)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(source: Path) -> None:
    result = bpy.ops.import_scene.gltf(filepath=str(source))
    if "FINISHED" not in result:
        raise RuntimeError(f"Could not import {source}: {result}")


def baked_copy(source: bpy.types.Object, name: str, origin: Vector) -> bpy.types.Object:
    mesh = source.data.copy()
    result = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(result)
    for vertex in mesh.vertices:
        vertex.co = source.matrix_world @ vertex.co - origin
    result.matrix_world = Matrix.Identity(4)
    return result


def retain_only(objects: list[bpy.types.Object]) -> None:
    keep = set(objects)
    for obj in list(bpy.context.scene.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def export_selected(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Could not export {path}: {result}")


def build_airframe(source: Path, destination: Path) -> None:
    reset_scene()
    import_model(source)
    missing = [name for name in AIRFRAME_MESHES if bpy.data.objects.get(name) is None]
    if missing:
        raise RuntimeError(f"Missing airframe meshes: {missing}")
    baked = [baked_copy(bpy.data.objects[name], f"airframe-{index:02d}", Vector())
             for index, name in enumerate(AIRFRAME_MESHES)]
    retain_only(baked)
    export_selected(destination)


def build_propeller(source: Path, destination: Path) -> tuple[Vector, list[Vector]]:
    reset_scene()
    import_model(source)
    source_mesh = bpy.data.objects.get(PROPELLER_MESH)
    motor = bpy.data.objects.get("motor_0")
    if source_mesh is None or motor is None:
        raise RuntimeError("Complete model does not contain the reference propeller or motor_0")
    pivot = motor.matrix_world.translation.copy()
    motor_positions = []
    for name in MOTOR_NAMES:
        node = bpy.data.objects.get(name)
        if node is None:
            raise RuntimeError(f"Complete model does not contain {name}")
        motor_positions.append(node.matrix_world.translation.copy())
    propeller = baked_copy(source_mesh, "propeller-motor-pivot", pivot)
    retain_only([propeller])
    export_selected(destination)
    return pivot, motor_positions


def add_camera_and_light() -> None:
    camera_data = bpy.data.cameras.new("ReferenceCamera")
    camera = bpy.data.objects.new("ReferenceCamera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = (4.0, -6.0, 5.0)
    camera.rotation_euler = ((Vector((0.0, 0.0, 0.32)) - camera.location)
                             .to_track_quat("-Z", "Y").to_euler())
    camera_data.lens = 65
    bpy.context.scene.camera = camera

    light_data = bpy.data.lights.new("ReferenceLight", "AREA")
    light = bpy.data.objects.new("ReferenceLight", light_data)
    bpy.context.scene.collection.objects.link(light)
    light.location = (2.0, -3.0, 7.0)
    light_data.energy = 1200
    light_data.shape = "DISK"
    light_data.size = 5


def render_reference(airframe: Path, propeller: Path, motor_positions: list[Vector], path: Path) -> None:
    reset_scene()
    import_model(airframe)
    airframe_objects = list(bpy.context.scene.objects)
    for obj in airframe_objects:
        obj.scale = (0.6, 0.6, 0.6)

    import_model(propeller)
    propeller_source = next(
        obj for obj in bpy.context.scene.objects
        if obj not in airframe_objects and obj.type == "MESH"
    )
    propeller_source.name = "reference-propeller-0"
    propeller_source.scale = (0.6, 0.6, 0.6)
    propeller_source.location = motor_positions[0] * 0.6
    for index, motor_position in enumerate(motor_positions[1:], start=1):
        duplicate = propeller_source.copy()
        duplicate.data = propeller_source.data.copy()
        duplicate.name = f"reference-propeller-{index}"
        duplicate.location = motor_position * 0.6
        bpy.context.scene.collection.objects.link(duplicate)

    add_camera_and_light()
    world = bpy.data.worlds.new("ReferenceWorld")
    bpy.context.scene.world = world
    world.color = (0.15, 0.15, 0.15)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    camera = bpy.data.objects["ReferenceCamera"]
    camera.location = (0.0, 0.0, 7.0)
    camera.rotation_euler = ((Vector((0.0, 0.0, 0.32)) - camera.location)
                             .to_track_quat("-Z", "Y").to_euler())
    scene.render.filepath = str(path.with_name("normalized-reference-top.png"))
    bpy.ops.render.render(write_still=True)


def main() -> None:
    args = parse_args()
    source = args.source.resolve()
    output_root = args.output_root.resolve()
    license_path = args.license.resolve()
    if not source.is_file() or not license_path.is_file():
        raise FileNotFoundError("Complete model or license is missing")
    output_root.mkdir(parents=True, exist_ok=True)

    airframe = output_root / "airframe" / "origin-01-airframe-normalized.gltf"
    propeller = output_root / "propeller" / "origin-01-propeller-motor-pivot.gltf"
    build_airframe(source, airframe)
    pivot, motor_positions = build_propeller(source, propeller)
    shutil.copy2(license_path, output_root / license_path.name)
    reference = output_root / "normalized-reference.png"
    render_reference(airframe, propeller, motor_positions, reference)

    manifest = {
        "source": str(source),
        "airframe": str(airframe),
        "propeller": str(propeller),
        "propellerPivotSourceNode": "motor_0",
        "referenceMeshSourceNode": PROPELLER_MESH,
        "referencePivot": list(pivot),
        "motorOrder": list(MOTOR_NAMES),
        "motorPositions": [list(position) for position in motor_positions],
        "runtimeUniformScale": 0.6,
        "referenceImage": str(reference),
        "referenceTopImage": str(reference.with_name("normalized-reference-top.png")),
    }
    (output_root / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
