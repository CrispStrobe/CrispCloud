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
remains the app import route: the new recovery option is available in the
vendored parser API but has no new app control in this increment. Source and
validation pins are recorded after qualification.

No queued release workflow or existing release tag is changed by this work.


## Qualification

The final production-configuration run passed **339 tests across 16 suites**,
with no failures or skips. The broader 56-suite run passed 1,003 cases with 23
platform-conditional skips; its one pending-timer fixture failure is corrected
and covered by the final run. Source-sync controls passed 27 tests and Apple
policy controls passed 38. Focused application and Word analyzers are clean.

The standalone parser passed all 4,072 tests. Quds' complete engine run passed
1,756 tests with three existing conditional skips and two CLI timeouts under
heavy concurrent compilation; the two-suite CLI rerun passed all 20 tests.
The subsequent VML/provenance/Word regression passed all 16 cases. These cohorts
overlap and should not be added together.

All **2,194 managed Office files** match Quds
`5133ce0343cb7c9456f852a4e760c771294ae6de` and independent legacy parser
`f9d10b5a5e68b4216892d64622caa8b0a15c7afd`. CrisperBooks, CrispSorter and Catfish
had no unmerged fetched branch heads. Other sessions' unfinished Excel-import
files in a separate Quds checkout are preserved, outside this qualified source.

Runtime checkpoint **af7a3752** builds for both macOS architectures. Local signing
is waiting for the build keychain to be unlocked: the native signing attempt
returned `errSecInternalComponent`, and Security.framework refused its unlock
dialog with `-60008`. The built bundle is not claimed as a signed installation.
The existing installed 8556c11d build remains intact. No queued release job was
cancelled, and no existing release tag was moved.

[Acceptance receipt and compressed logs](evidence/pane-header-integration-20261114/acceptance.json)
retain exact results and the final source pins.
