#!/usr/bin/env python3
"""Write the deterministic Finder layout into an already mounted DMG."""

from __future__ import annotations

import argparse
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias


def write_layout(mount_point: Path) -> None:
    background = mount_point / ".background.tiff"
    if not background.is_file():
        raise FileNotFoundError(f"DMG background is missing: {background}")

    browser_window = {
        "ShowStatusBar": False,
        "WindowBounds": "{{100, 100}, {660, 500}}",
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 180,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    icon_view = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundImageAlias": Alias.for_file(str(background)).to_bytes(),
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 12.0,
        "iconSize": 112.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }

    with DSStore.open(str(mount_point / ".DS_Store"), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = browser_window
        store["."]["icvp"] = icon_view
        store["."]["icvl"] = (b"type", b"icnv")
        store["Cadence.app"]["Iloc"] = (180, 220)
        store["Applications"]["Iloc"] = (480, 220)


def verify_layout(mount_point: Path) -> None:
    """Reject an image whose Finder presentation drifted from the contract."""
    with DSStore.open(str(mount_point / ".DS_Store"), "r") as store:
        icon_view = store["."]["icvp"]
        if store["."]["icvl"] != (b"type", b"icnv"):
            raise ValueError("DMG does not open in icon view")
        if icon_view["backgroundType"] != 2 or icon_view["iconSize"] != 112.0:
            raise ValueError("DMG background or icon size does not match the contract")
        if store["Cadence.app"]["Iloc"] != (180, 220):
            raise ValueError("Cadence.app icon position does not match the contract")
        if store["Applications"]["Iloc"] != (480, 220):
            raise ValueError("Applications icon position does not match the contract")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mount_point", type=Path)
    parser.add_argument("--verify", action="store_true")
    arguments = parser.parse_args()
    if arguments.verify:
        verify_layout(arguments.mount_point)
    else:
        write_layout(arguments.mount_point)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
