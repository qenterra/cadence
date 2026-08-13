"""Deterministic Finder layout for the Cadence release disk image."""

app_path = defines["app"]
background_path = defines["background"]

files = [(app_path, "Cadence.app")]
symlinks = {"Applications": "/Applications"}

format = "UDZO"
filesystem = "APFS"
background = background_path
window_rect = ((100, 100), (660, 500))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = True
include_icon_view_settings = True

icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {
    "Cadence.app": (180, 220),
    "Applications": (480, 220),
}
