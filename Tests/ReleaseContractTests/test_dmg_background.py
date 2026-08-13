from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "release" / "render_dmg_background.py"


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

        self.assertEqual(image.size, (1320, 840))
        for red, green, blue, _alpha in image.get_flattened_data():
            self.assertEqual(red, green)
            self.assertEqual(green, blue)


if __name__ == "__main__":
    unittest.main()
