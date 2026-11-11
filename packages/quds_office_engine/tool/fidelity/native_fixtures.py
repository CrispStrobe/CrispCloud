"""Explicit fixture regeneration with independent openpyxl/python-pptx producers.
Normal verification consumes the committed files; it never regenerates them.
"""
from io import BytesIO
from pathlib import Path
import json
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
import openpyxl
import pptx
from PIL import Image
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE
from pptx.oxml.xmlchemy import OxmlElement
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.chart import BarChart, Reference
from openpyxl.pivot.table import TableDefinition, Location, RowColField, DataField, PivotField
from openpyxl.pivot.cache import CacheDefinition, CacheSource, WorksheetSource, CacheField, SharedItems
from openpyxl.pivot.fields import Text, Number
from openpyxl.pivot.record import RecordList

OUT = Path('test/fixtures/fidelity')

def save(obj, name):
    stream = BytesIO(); obj.save(stream)
    with ZipFile(stream) as source, ZipFile(OUT / name, 'w', ZIP_DEFLATED) as dest:
        for path in sorted(source.namelist()):
            info = ZipInfo(path, (2024, 1, 1, 0, 0, 0)); info.compress_type = ZIP_DEFLATED
            dest.writestr(info, source.read(path))


def slides():
    deck = Presentation()
    for index, color in enumerate(((210, 30, 40), (20, 60, 210))):
        slide = deck.slides.add_slide(deck.slide_layouts[5])
        slide.shapes.title.text = f'Native slide {index + 1}'
        slide.shapes.title.text_frame.paragraphs[0].runs[0].font.size = Pt(24)
        pic = BytesIO(); Image.new('RGB', (6, 4), color).save(pic, 'PNG'); pic.seek(0)
        slide.shapes.add_picture(pic, Inches(.5), Inches(1.5), Inches(1), Inches(.75))
        data = CategoryChartData(); data.categories = ['North', 'South']
        data.add_series(f'Series {index + 1}', [index + 2, index + 5])
        slide.shapes.add_chart(XL_CHART_TYPE.COLUMN_CLUSTERED, Inches(2), Inches(1.5), Inches(5), Inches(3), data)
        slide.notes_slide.notes_text_frame.text = f'Speaker note {index + 1}'
        transition = OxmlElement('p:transition'); transition.set('spd', 'slow')
        transition.append(OxmlElement('p:fade')); slide._element.append(transition)
    save(deck, 'native.pptx')


def sheets():
    book = openpyxl.Workbook(); sheet = book.active; sheet.title = 'Data'
    for row in [['Region', 'Value', 'Total'], ['North', 2, '=B2*3'], ['South', 5, '=B3*3']]: sheet.append(row)
    sheet['A1'].font = Font(name='Arial', bold=True, color='FFFFFFFF', size=14)
    sheet['A1'].fill = PatternFill('solid', fgColor='FF224466')
    sheet['B2'].number_format = '0.00'
    sheet['B2'].alignment = Alignment(horizontal='right')
    sheet['B2'].border = Border(bottom=Side(style='thin', color='FF224466'))
    sheet['A2'].hyperlink = 'https://example.com/north'
    sheet.freeze_panes = 'B2'; sheet.merge_cells('A5:C5'); sheet['A5'] = 'Native workbook'
    sheet.column_dimensions['A'].width = 22
    chart = BarChart(); chart.title = 'Regional values'
    chart.add_data(Reference(sheet,min_col=2,min_row=1,max_row=3),titles_from_data=True)
    chart.set_categories(Reference(sheet,min_col=1,min_row=2,max_row=3)); sheet.add_chart(chart, 'E2')
    summary = book.create_sheet('Summary'); summary.append(['Region','Sum']); summary.append(['North',2]); summary.append(['South',5])
    cache = CacheDefinition(cacheSource=CacheSource(type='worksheet',worksheetSource=WorksheetSource(ref='A1:B3',sheet='Data')),cacheFields=[CacheField(name='Region'),CacheField(name='Value')],refreshOnLoad=True,recordCount=2)
    pivot = TableDefinition(name='NativePivot',cacheId=1,dataCaption='Values',location=Location(ref='A1:B4',firstHeaderRow=1,firstDataRow=1,firstDataCol=1),pivotFields=[PivotField(axis='axisRow'),PivotField(dataField=True)],rowFields=[RowColField(x=0)],dataFields=[DataField(name='Sum of Value',fld=1)])
    pivot.cache = cache; summary.add_pivot(pivot)
    save(book, 'native.xlsx')

if __name__ == '__main__':
    slides(); sheets()
    (OUT / 'native-producers.json').write_text(json.dumps({'python-pptx':pptx.__version__,'openpyxl':openpyxl.__version__,'purpose':'Independent import fixtures. Expected values are authored in native_oracle.py.'},indent=2)+'\n')
