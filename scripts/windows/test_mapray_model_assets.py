from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_ROOT = REPOSITORY_ROOT.parent
OUTPUT_ROOT = REPOSITORY_ROOT / "runtime/windows/generated/mapray-model-phase0"


class MaprayModelAssetTest(unittest.TestCase):
    def test_pipeline_contract(self) -> None:
        script = (REPOSITORY_ROOT / "tools/blender/export_mapray_gltf.py").read_text(
            encoding="utf-8"
        )
        wrapper = (
            REPOSITORY_ROOT / "scripts/windows/build_mapray_model_assets.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn('export_format="GLTF_SEPARATE"', script)
        self.assertIn("assert_bounds_equal", script)
        self.assertIn("sha256", script)
        self.assertIn("gltf validator", wrapper.lower())
        self.assertIn("numErrors", wrapper)

    def test_generated_assets_are_self_contained(self) -> None:
        manifest = json.loads((OUTPUT_ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["schemaVersion"], 2)
        self.assertTrue((OUTPUT_ROOT / "LICENSE.txt").is_file())
        self.assertEqual({asset["role"] for asset in manifest["assets"]}, {"airframe", "propeller"})
        for asset in manifest["assets"]:
            role_root = OUTPUT_ROOT / asset["role"]
            self.assertFalse((role_root / "LICENSE.txt").exists())
            gltf_path = role_root / asset["gltf"]["path"]
            document = json.loads(gltf_path.read_text(encoding="utf-8"))
            self.assertEqual(document["asset"]["version"], "2.0")
            self.assertNotIn("animations", document)
            self.assertNotIn("cameras", document)
            for record in [*document.get("buffers", []), *document.get("images", [])]:
                uri = record.get("uri")
                if not uri:
                    continue
                relative = PurePosixPath(uri)
                self.assertFalse(relative.is_absolute())
                self.assertNotIn("..", relative.parts)
                self.assertTrue((role_root / Path(*relative.parts)).is_file())


if __name__ == "__main__":
    unittest.main()
