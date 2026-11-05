# PDF fork transfer

This directory preserves the general-purpose editor extensions as one complete,
binary-safe patch against the immutable upstream commit recorded in
`manifest.json`. The target repository is **CrispStrobe/dart-pdf**, on
`feature/crispcloud-pdf-operations`. Fork creation is pending authenticated
GitHub access; this directory does not imply that the remote fork exists.

The patch includes the new Apache-2.0 `pdf_operations` package, core extraction,
Unicode OCR and annotation-flattening fixes, password-aware editor insertion,
tests, test-font notices, and workspace registration. CrispCloud-specific UI,
storage and redaction restrictions stay in this application repository.

## Apply to the fork

After creating the fork, clone it and create a feature branch from the recorded
base commit. Set `CRISPCLOUD_CHECKOUT` to this application's absolute path:

```sh
git clone https://github.com/CrispStrobe/dart-pdf.git
cd dart-pdf
git switch -c feature/crispcloud-pdf-operations \
  87adaa022c5ed6b22ca3232b6cae4a03e8389e98
git apply --index \
  "$CRISPCLOUD_CHECKOUT/packages/pdf_fork_transfer/fork.patch"
git write-tree
```

The resulting tree must match `expectedTree` in `manifest.json`. The patch was
applied to an isolated temporary index and checked against that exact tree.
Review, commit and push that feature branch; no default-branch update is needed.

The binary patch preserves the test font exactly. Its adjacent original notices
remain part of the package. Test output PDFs are generated in CI, not committed.

## Maintaining this transfer

Changes to shared engine source, tests or package code must be synchronized into
the pinned upstream checkout and the transfer regenerated before publishing it.
After staging the synchronized extension checkout,
`tool/export_pdf_fork_patch.py --upstream PATH` regenerates and verifies this
transfer. The application runtime patches can be independently rebuilt and
checked with `tool/update_pdf_vendor_patches.py`. The application and CLI currently resolve
the maintained source snapshots locally; switching to a remote fork pin follows
creation and verification of that fork.
