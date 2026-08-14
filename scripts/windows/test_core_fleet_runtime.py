from __future__ import annotations

import json
import math
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from core_fleet_scenario import CoreFleetScenario, geo_to_ros  # noqa: E402


class CoreFleetRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.operations = (
            ROOT
            / "hakoniwa-geo-viewer"
            / "config"
            / "operations"
            / "shibuya-wide-area-5km.geojson"
        )
        self.origin = {"latitude": 35.6625, "longitude": 139.70625}
        self.scenario = CoreFleetScenario(
            self.operations,
            fleet_size=30,
            seed=20260811,
            origin=self.origin,
        )

    def test_supported_locations_have_deterministic_core_fleets(self) -> None:
        cases = (
            (
                "shibuya",
                self.operations,
                {"latitude": 35.6625, "longitude": 139.70625},
            ),
            (
                "tokyo-tower",
                ROOT
                / "hakoniwa-geo-viewer"
                / "config"
                / "operations"
                / "tokyo-tower-wide-area-5km.geojson",
                {"latitude": 35.658581, "longitude": 139.745433},
            ),
        )
        for name, operations, origin in cases:
            with self.subTest(name=name):
                scenario = CoreFleetScenario(
                    operations,
                    fleet_size=30,
                    seed=20260811,
                    origin=origin,
                )
                first = scenario.sample(12.0)
                second = scenario.sample(12.0)
                self.assertEqual(first, second)
                self.assertEqual(30, len(first))
                self.assertEqual(3, len({state["route_id"] for state in first}))
                self.assertTrue(
                    all(math.isfinite(value) for state in first for value in state["position_ros"])
                )

    def test_deterministic_three_route_fleet(self) -> None:
        first = self.scenario.sample(12.0)
        second = self.scenario.sample(12.0)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 30)
        self.assertEqual(len({state["id"] for state in first}), 30)
        self.assertEqual(len({state["route_id"] for state in first}), 3)
        self.assertTrue(all(state["status"] == "NORMAL" for state in first))

    def test_incident_target_reaches_configured_site(self) -> None:
        before = self.scenario.sample(self.scenario.trigger_seconds - 0.1)
        after = self.scenario.sample(
            self.scenario.trigger_seconds + self.scenario.diversion_seconds + 1.0
        )
        self.assertEqual(before[self.scenario.target_index]["status"], "NORMAL")
        target = after[self.scenario.target_index]
        self.assertEqual(target["status"], "HIGH")
        expected = geo_to_ros(self.origin, self.scenario.incident_coordinate)
        for actual_value, expected_value in zip(target["position_ros"], expected):
            self.assertTrue(math.isclose(actual_value, expected_value, abs_tol=1e-9))

    def test_fleet_pdudef_contract(self) -> None:
        pdu_root = ROOT / "runtime" / "windows" / "core-fleet" / "config" / "pdudef"
        definition = json.loads((pdu_root / "drone-visual-state.json").read_text(encoding="utf-8"))
        types = json.loads((pdu_root / "drone-visual-state-pdutypes.json").read_text(encoding="utf-8"))
        self.assertEqual(definition["robots"][0]["name"], "DroneVisualStatePublisher")
        self.assertEqual(types[0]["channel_id"], 0)
        self.assertEqual(types[0]["pdu_size"], 32768)
        self.assertEqual(types[0]["type"], "hako_msgs/DroneVisualStateArray")

    def test_launcher_labels_kinematic_source(self) -> None:
        launcher = (ROOT / "scripts" / "windows" / "start_core_fleet_demo.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("core_fleet_conductor.py", launcher)
        self.assertIn('source = "hakoniwa-core-kinematic"', launcher)
        self.assertIn("liveProfile=kinematic", launcher)
        self.assertIn('"--profile", "fleets"', launcher)
        self.assertIn('[ValidateSet("shibuya", "tokyo-tower")]', launcher)
        self.assertIn('viewer-config-$ScenarioName.json', launcher)
        self.assertIn('"--origin-latitude", $originLatitude', launcher)
        self.assertIn('"--origin-longitude", $originLongitude', launcher)


if __name__ == "__main__":
    unittest.main()
