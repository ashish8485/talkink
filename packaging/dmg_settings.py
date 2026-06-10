# dmgbuild settings — drag-to-install layout matching packaging/dmg-background.html
# Usage (via scripts/make_dmg.sh):
#   python3 -m dmgbuild -s packaging/dmg_settings.py -D app="dist/Söyle.app" "Söyle" dist/Soyle.dmg
import os.path
import unicodedata

app = defines.get("app", "dist/Söyle.app")  # noqa: F821
appname = os.path.basename(app)
# HFS+/APFS store names in NFD; Finder looks Iloc entries up by the on-disk
# form. Register both normalizations so the diacritic never breaks the layout.
appname_nfd = unicodedata.normalize("NFD", appname)
appname_nfc = unicodedata.normalize("NFC", appname)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

background = "packaging/dmg-background.tiff"
window_rect = ((200, 120), (660, 420))
icon_size = 110
text_size = 13
# Centers of the dashed slots drawn in the background.
icon_locations = {
    appname_nfd: (160, 232),
    appname_nfc: (160, 232),
    "Applications": (500, 232),
}

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
arrange_by = None
