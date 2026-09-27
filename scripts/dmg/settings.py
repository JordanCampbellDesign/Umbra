# dmgbuild layout for Umbra's installer window.
# Run through scripts/make-dmg.sh, which passes the app path with -D app=...
import os

app = defines.get("app", "build/Umbra.app")
here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "scripts/dmg"

format = "ULMO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = ["Umbra.app"]
icon_locations = {"Umbra.app": (180, 215), "Applications": (480, 215)}
background = "scripts/dmg/background.png"
window_rect = ((200, 120), (660, 420))
icon_size = 112
text_size = 13
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
