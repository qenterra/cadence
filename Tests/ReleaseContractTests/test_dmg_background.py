from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "release" / "render_dmg_background.py"
SETTINGS = ROOT / "release" / "dmgbuild-settings.py"


class DMGBackgroundTests(unittest.TestCase):
    def load_renderer(self):
        spec = importlib.util.spec_from_file_location("render_dmg_background", SCRIPT)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_rendered_background_includes_real_retina_representation(self) -> None:
        module = self.load_renderer()

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "background.png"
            module.render(output)
            retina_output = output.with_name("background@2x.png")

            self.assertTrue(retina_output.is_file())
            with Image.open(output) as image:
                self.assertEqual(image.size, (660, 420))
                self.assertAlmostEqual(image.info["dpi"][0], 72, delta=0.2)
                self.assertAlmostEqual(image.info["dpi"][1], 72, delta=0.2)
            with Image.open(retina_output) as retina_image:
                self.assertEqual(retina_image.size, (1320, 840))
                self.assertAlmostEqual(retina_image.info["dpi"][0], 144, delta=0.2)
                self.assertAlmostEqual(retina_image.info["dpi"][1], 144, delta=0.2)

    def test_rendered_background_is_exactly_monochrome_at_every_scale(self) -> None:
        module = self.load_renderer()

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "background.png"
            module.render(output)

            for path in (output, output.with_name("background@2x.png")):
                self.assertTrue(path.is_file())
                image = Image.open(path).convert("RGBA")
                for red, green, blue, _alpha in image.get_flattened_data():
                    self.assertEqual(red, green)
                    self.assertEqual(green, blue)

    def test_light_canvas_keeps_finder_labels_legible_without_backplates(self) -> None:
        module = self.load_renderer()

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "background.png"
            module.render(output)
            image = Image.open(output).convert("RGB")

        for bounds in ((104, 252, 256, 306), (404, 252, 556, 306)):
            label_region = image.crop(bounds)
            luminance = [pixel[0] for pixel in label_region.get_flattened_data()]
            self.assertGreaterEqual(min(luminance), 238)
            self.assertLessEqual(
                max(luminance) - min(luminance),
                6,
            )

    def test_semibold_system_type_has_more_ink_than_regular(self) -> None:
        module = self.load_renderer()

        regular = Image.new("L", (320, 80))
        semibold = Image.new("L", (320, 80))
        ImageDraw.Draw(regular).text(
            (8, 8),
            "Cadence",
            font=module.font(28, "regular"),
            fill=255,
        )
        ImageDraw.Draw(semibold).text(
            (8, 8),
            "Cadence",
            font=module.font(28, "semibold"),
            fill=255,
        )

        self.assertGreater(
            sum(semibold.get_flattened_data()),
            sum(regular.get_flattened_data()) * 1.08,
        )

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
        self.assertEqual(namespace["text_size"], 12)
        self.assertEqual(
            namespace["icon_locations"],
            {"Cadence.app": (180, 220), "Applications": (480, 220)},
        )
        self.assertEqual(namespace["filesystem"], "APFS")
        self.assertEqual(namespace["format"], "UDZO")


if __name__ == "__main__":
    unittest.main()
