"""Author a native, ungrouped visual reference independently of Quds output.

This explicit maintenance command uses python-pptx. Normal test/validation
runs consume the committed fixture and never regenerate it from engine output.
"""

from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_AUTO_SHAPE_TYPE
from pptx.enum.text import PP_ALIGN
from pptx.util import Pt


def main():
    presentation = Presentation()
    presentation.slide_width = 9144000
    presentation.slide_height = 6858000
    slide = presentation.slides.add_slide(presentation.slide_layouts[6])
    for index in range(5):
        shape = slide.shapes.add_shape(
            MSO_AUTO_SHAPE_TYPE.RECTANGLE,
            254000 + index * 1700000,
            1000000,
            1400000,
            1000000,
        )
        shape.name = f"Card {index + 1}"
        shape.fill.solid()
        shape.fill.fore_color.rgb = RGBColor.from_string("4472C4")
        shape.line.color.rgb = RGBColor.from_string("223344")
        shape.line.width = Pt(1)
        shape.text = f"Card {index + 1}"
        paragraph = shape.text_frame.paragraphs[0]
        paragraph.alignment = PP_ALIGN.LEFT
        run = paragraph.runs[0]
        run.font.name = "Arial"
        run.font.size = Pt(18)
        run.font.color.rgb = RGBColor.from_string("FFFFFF")
        # Directly authored properties avoid inherited default theme effects.
        for style in list(shape._element):
            if style.tag.endswith("}style"):
                shape._element.remove(style)
    stream = BytesIO()
    presentation.save(stream)
    target = Path(__file__).resolve().parents[2] / "test/fixtures/fidelity/slide-arrange.pptx"
    with ZipFile(stream) as source, ZipFile(target, "w", ZIP_DEFLATED) as output:
        for name in sorted(source.namelist()):
            info = ZipInfo(name, (2024, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            output.writestr(info, source.read(name))
    print(target)


if __name__ == "__main__":
    main()
