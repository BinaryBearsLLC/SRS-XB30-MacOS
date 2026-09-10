"""BinaryBears v1.0 layout, written headlessly so CI never needs Finder automation."""
import json
from pathlib import Path
root = Path(defines['layout']).resolve().parent
layout = json.loads((root / 'layout.json').read_text())
app = defines['app']
files = [(app, 'XB30 Controller.app'), defines['website']]
symlinks = {'Applications': '/Applications'}
background = defines['background']
icon = str(Path(app) / 'Contents/Resources/AppIcon.icns')
format = 'UDZO'
filesystem = 'HFS+'
# Preserve the 720×460 artwork plus Finder title/scroller chrome.
window_rect = ((180, 120), (736, 504))
icon_size = layout['finder']['iconSize']
text_size = layout['finder']['textSize']
icon_locations = {
 'XB30 Controller.app': tuple(layout['finder']['items']['application']),
 'Applications': tuple(layout['finder']['items']['applicationsFolder']),
 '\u2063.webloc': tuple(layout['finder']['items']['website']),
}
hide_extensions = ['\u2063.webloc']
default_view = 'icon-view'
include_icon_view_settings = True
show_status_bar = show_toolbar = show_pathbar = show_sidebar = False
arrange_by = None
