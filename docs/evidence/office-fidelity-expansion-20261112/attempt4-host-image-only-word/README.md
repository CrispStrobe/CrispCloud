# Host image-only Word native failure

At app `561f486b9f13248f90dba679bdbf60bf8dc8ffcf` and shared source `1d19150ff35e95374fa3c11e0b6a43d187d24024`, the complete producer passed 1,147 engine and 180 host cases, and all 468 declared packages passed SDK validation. The full 122-file native phase failed for six intentionally image-only Word captures: three GIF and three JPEG saves. They contain an authored 80 × 40 image displayed at 60 × 30 points and no authored text. The renderer required extractable text for these files, so the two repeated-save groups were incomplete.

The report retains 116 successful native renders, 152 pages and the precise six file failures plus two resulting cycle-group failures. This is an incomplete native acceptance, not a passing final result. All original and frozen input hashes remained unchanged.

The six inputs, full input manifest, full schema receipt, native report and log are preserved here. The complete original 468-file snapshot and successful native output artifacts remain outside the checkout. The following correction must add an independent, exact Word picture geometry/raster oracle; the meaningful image-only fixtures must remain unchanged.
