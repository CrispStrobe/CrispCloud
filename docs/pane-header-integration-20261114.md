# Pane navigation and sibling integration

Both pane headers expose Up, using the same source-bound navigation as the
existing command (including archive exit, search results and flat views). The
source selector now includes local volumes, Home, Computer and bookmarks. Closed
labels use their intrinsic width within 132 pixels, with a 15-character cap and
full-name tooltips. Open menus retain full labels. Account choices revalidate
identity; volume and bookmark choices capture the owning panel session and refuse
stale tabs, removed provider volumes and removed bookmarks.

The separate house/Volumes and Edit path buttons are removed. Path editing stays
in the breadcrumb context menu. Native macOS and Flutter wide toolbars omit
Terminal and synchronized browsing; F9, menu commands and touch overflow remain.
Synchronized browsing follows matching relative folders in the other pane and
can still be explicitly enabled when wanted.

The integration also retains the latest published storage-delta/verified S3 copy
work, Office recovery evidence, authored worksheet number formats, Word media
payload deduplication, symbol characters, text-box isolation, canonical legacy
built-in style names and opt-in auxiliary-feature recovery. Strict legacy parsing
remains the default. Source and validation pins are recorded after qualification.

No queued release workflow or existing release tag is changed by this work.
