# File Viewer formats and effective licenses

Review date: 2026-11-13. Repository: [flyfish-dev/file-viewer](https://github.com/flyfish-dev/file-viewer).
The reviewed upstream version is 3.3.3 at
[`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/commit/d264009ca6efb3daed79a39d1ae63133e0f25558),
also confirmed as upstream main during this review. CrispCloud's implemented
binary and LRC extraction checkpoint is
[`98b39f2`](https://github.com/CrispStrobe/CrispCloud/commit/98b39f21a528375165822e38c4ff4fcfa75575e2).

## User-approved policy

The user's updated instruction is: “mit or bsd or similar are ok for crispcloud.
mpl too.” Future candidates may therefore include Apache-2.0, MIT/MIT-0,
BSD-family and comparable permissive code licenses, and MPL. The existing
Apache-only extracted files and their provenance guards stay unchanged.

An effective-license entry describes the components distributed for a route:
File Viewer's wrapper, parser, runtime, and relevant bundled assets. It is not
a new license applied to the entire combination. A dual license offering a
permissive or MPL option can use that option; an Apache wrapper does not change
the license of its engine or assets. LGPL, GPL/AGPL, EPL, custom restrictions and
unresolved binary provenance require separate treatment.

MPL is accepted with its source and notice obligations: preserve the applicable
license and provide the corresponding covered source and modifications when
distributing compiled code. The [Mozilla FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
explains the file-level boundary and executable-distribution requirements.
Fonts and data have their own grants, such as OFL, GUST/LPPL or CC0, and are
listed separately from software licenses.

The format matrix and rendering-path evidence are being recorded in the next
review checkpoint. No additional runtime, code or assets are imported by this
policy-documentation change.
