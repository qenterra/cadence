from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "release" / "render_dmg_background.py"
SETTINGS = ROOT / "release" / "dmgbuild-settings.py"


class DMGBackgroundTests(unittest.TestCase):
    def test_rendered_background_is_exactly_monochrome(self) -> None:
        spec = importlib.util.spec_from_file_location("render_dmg_background", SCRIPT)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "background.png"
            module.render(output)
            image = Image.open(output).convert("RGBA")

        self.assertEqual(image.size, (660, 420))
        for red, green, blue, _alpha in image.get_flattened_data():
            self.assertEqual(red, green)
            self.assertEqual(green, blue)

    def test_dmgbuild_settings_keep_the_approved_layout(self) -> None:
        namespace = {
            "defines": {
                "app": "/tmp/Cadence.app",
                "background": "/tmp/dmg-background.png",
            }
        }
        exec(compile(SETTINGS.read_text(), SETTINGS, "exec"), namespace)

        self.assertEqual(namespace["files"], [("/tmp/Cadence.app", "Cadence.app")])
        self.assertEqual(namespace["symlinks"], {"Applications": "/Applications"})
        self.assertNotIn("hide_extensions", namespace)
        self.assertEqual(namespace["background"], "/tmp/dmg-background.png")
        self.assertEqual(namespace["window_rect"], ((100, 100), (660, 500)))
        self.assertEqual(
            namespace["icon_locations"],
            {"Cadence.app": (180, 220), "Applications": (480, 220)},
        )
        self.assertEqual(namespace["filesystem"], "APFS")
        self.assertEqual(namespace["format"], "UDZO")


if __name__ == "__main__":
    unittest.main()
