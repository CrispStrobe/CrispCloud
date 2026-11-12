#!/usr/bin/env python3
"""Reproduce the independent FID-029 fixture from its authored XML contract.

No Quds model or serializer supplies any source member. Normal deliberately uses
builtinId=0, a localized name, style xf 1 and font 2; misleading first entries
exercise lookup provenance. Width pairs 8.7109375/8.72 collapse under MDW=7 but
separate under the loaded Liberation Mono 24pt MDW=19.
"""
import argparse
import io
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

PARTS = {
  "[Content_Types].xml": "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>",
  "_rels/.rels": "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
  "xl/workbook.xml": "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><bookViews><workbookView/></bookViews><sheets><sheet name=\"Normal metrics\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
  "xl/_rels/workbook.xml.rels": "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>",
  "xl/worksheets/sheet1.xml": "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetViews><sheetView workbookViewId=\"0\"/></sheetViews><sheetFormatPr baseColWidth=\"8\" defaultColWidth=\"10.25\" defaultRowHeight=\"18\"/><cols><col min=\"1\" max=\"1\" width=\"8.7109375\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"8.72\" customWidth=\"1\"/><col min=\"3\" max=\"3\" width=\"22\" customWidth=\"1\"/></cols><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\" s=\"0\"><is><t>Normal-font column widths</t></is></c></row></sheetData></worksheet>",
  "xl/styles.xml": "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"3\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><sz val=\"14\"/><name val=\"Arial\"/></font><font><b val=\"0\"/><i val=\"false\"/><sz val=\"24\"/><name val=\"Liberation Mono\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/><xf numFmtId=\"0\" fontId=\"2\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"1\" applyFont=\"1\"/></cellXfs><cellStyles count=\"2\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"1\" iLevel=\"0\"/><cellStyle name=\"Standard\" xfId=\"1\" builtinId=\"0\" customBuiltin=\"1\"/></cellStyles></styleSheet>"
}


def generate():
    output = io.BytesIO()
    with ZipFile(output, "w") as archive:
        for name, xml in PARTS.items():
            entry = ZipInfo(name, (2026, 11, 12, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            archive.writestr(entry, xml)
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2] /
                        "test/fixtures/fidelity/sheet-normal-font-native.xlsx")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = generate()
    if args.check:
        if args.output.read_bytes() != data:
            raise SystemExit("Fixture differs from its independently authored contract")
        print("Independent Normal-font fixture matches its source contract")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(data)
        print(args.output)


if __name__ == "__main__":
    main()
