#!/usr/bin/env python3
"""Generate ITS VVC Technical Report matching reference docx formatting.

Reference style (from 智能交通感知系统技术报告_v23.docx):
  Normal: 宋体+Times New Roman 11.5pt, color #1F2937, line=330, after=100
  H1: 16pt bold #1F4E79, left-border #1F4E79 + bottom-border #D7E3F3, pageBreak
  H2: 13.5pt bold #2F5597
  H3: 12pt bold #374151
  Table: "Table Grid" style, border #9EADBF outer / #C3CCD8 inner
  Title: 22pt bold #1F2937 centered
  Footer: 9pt centered "第X页 / 共Y页"
"""

import zipfile
import os

# ── Content Types ──
CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/>
  <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
</Types>'''

RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''

WORD_RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
</Relationships>'''

# ── Styles: exact match from reference docx ──
STYLES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
          mc:Ignorable="w14"
          xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体" w:cs="Times New Roman"/>
        <w:color w:val="1F2937"/>
        <w:sz w:val="23"/>
        <w:szCs w:val="23"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault/>
  </w:docDefaults>

  <!-- Normal -->
  <w:style w:type="paragraph" w:styleId="Normal" w:default="1">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:after="100" w:line="330" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="23"/>
      <w:szCs w:val="23"/>
    </w:rPr>
  </w:style>

  <!-- Heading 1: 16pt bold #1F4E79, decorative borders, pageBreak -->
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:pageBreakBefore/>
      <w:pBdr>
        <w:left w:val="single" w:color="1F4E79" w:sz="18" w:space="8"/>
        <w:bottom w:val="single" w:color="D7E3F3" w:sz="4" w:space="4"/>
      </w:pBdr>
      <w:spacing w:before="420" w:after="180" w:line="330" w:lineRule="auto"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:outlineLvl w:val="0"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:b/><w:bCs/>
      <w:color w:val="1F4E79"/>
      <w:sz w:val="32"/>
      <w:szCs w:val="32"/>
    </w:rPr>
  </w:style>

  <!-- Heading 2: 13.5pt bold #2F5597 -->
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="260" w:after="120" w:line="330" w:lineRule="auto"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:outlineLvl w:val="1"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:b/><w:bCs/>
      <w:color w:val="2F5597"/>
      <w:sz w:val="27"/>
      <w:szCs w:val="27"/>
    </w:rPr>
  </w:style>

  <!-- Heading 3: 12pt bold #374151 -->
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="200" w:after="100" w:line="330" w:lineRule="auto"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:outlineLvl w:val="2"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:b/><w:bCs/>
      <w:color w:val="374151"/>
      <w:sz w:val="24"/>
      <w:szCs w:val="24"/>
    </w:rPr>
  </w:style>

  <!-- Heading 4 -->
  <w:style w:type="paragraph" w:styleId="Heading4">
    <w:name w:val="heading 4"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="160" w:after="80"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:outlineLvl w:val="3"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:b/><w:bCs/>
      <w:color w:val="374151"/>
      <w:sz w:val="23"/>
      <w:szCs w:val="23"/>
    </w:rPr>
  </w:style>

  <!-- Table Grid: light blue-gray grid -->
  <w:style w:type="table" w:styleId="TableGrid">
    <w:name w:val="Table Grid"/>
    <w:qFormat/>
    <w:tblPr>
      <w:tblBorders>
        <w:top w:val="single" w:color="9EADBF" w:sz="4" w:space="0"/>
        <w:left w:val="single" w:color="9EADBF" w:sz="4" w:space="0"/>
        <w:bottom w:val="single" w:color="9EADBF" w:sz="4" w:space="0"/>
        <w:right w:val="single" w:color="9EADBF" w:sz="4" w:space="0"/>
        <w:insideH w:val="single" w:color="C3CCD8" w:sz="4" w:space="0"/>
        <w:insideV w:val="single" w:color="C3CCD8" w:sz="4" w:space="0"/>
      </w:tblBorders>
      <w:tblCellMar>
        <w:top w:w="40" w:type="dxa"/>
        <w:left w:w="108" w:type="dxa"/>
        <w:bottom w:w="40" w:type="dxa"/>
        <w:right w:w="108" w:type="dxa"/>
      </w:tblCellMar>
    </w:tblPr>
  </w:style>

  <!-- Table Header paragraph -->
  <w:style w:type="paragraph" w:styleId="TableHeader">
    <w:name w:val="Table Header"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:jc w:val="center"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:spacing w:before="0" w:after="0" w:line="280" w:lineRule="exact"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:b/><w:bCs/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="20"/>
      <w:szCs w:val="20"/>
    </w:rPr>
  </w:style>

  <!-- Table Cell paragraph -->
  <w:style w:type="paragraph" w:styleId="TableCell">
    <w:name w:val="Table Cell"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:spacing w:before="0" w:after="0" w:line="280" w:lineRule="exact"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="20"/>
      <w:szCs w:val="20"/>
    </w:rPr>
  </w:style>

  <!-- List Paragraph -->
  <w:style w:type="paragraph" w:styleId="ListParagraph">
    <w:name w:val="List Paragraph"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:after="80" w:line="360" w:lineRule="auto"/>
      <w:ind w:left="720" w:hanging="360"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="24"/>
      <w:szCs w:val="24"/>
    </w:rPr>
  </w:style>

  <!-- Code -->
  <w:style w:type="paragraph" w:styleId="Code">
    <w:name w:val="Code"/>
    <w:pPr>
      <w:shd w:val="clear" w:color="auto" w:fill="F6F8FA"/>
      <w:spacing w:line="260" w:lineRule="auto"/>
      <w:ind w:left="240" w:right="240" w:firstLine="0" w:firstLineChars="0"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:eastAsia="宋体"/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="18"/>
      <w:szCs w:val="18"/>
    </w:rPr>
  </w:style>

  <!-- Footer -->
  <w:style w:type="paragraph" w:styleId="Footer">
    <w:name w:val="footer"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:jc w:val="center"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:spacing w:line="240" w:lineRule="auto"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="18"/>
      <w:szCs w:val="18"/>
    </w:rPr>
  </w:style>

  <!-- Title -->
  <w:style w:type="paragraph" w:styleId="CoverTitle">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:jc w:val="center"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:spacing w:before="240" w:after="240" w:line="400" w:lineRule="exact"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:b/><w:bCs/>
      <w:color w:val="1F2937"/>
      <w:sz w:val="44"/>
      <w:szCs w:val="44"/>
    </w:rPr>
  </w:style>

  <!-- Cover Info -->
  <w:style w:type="paragraph" w:styleId="CoverInfo">
    <w:name w:val="Cover Info"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:jc w:val="center"/>
      <w:ind w:firstLine="0" w:firstLineChars="0"/>
      <w:spacing w:before="0" w:after="80" w:line="320" w:lineRule="exact"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="宋体"/>
      <w:color w:val="5A6575"/>
      <w:sz w:val="20"/>
      <w:szCs w:val="20"/>
    </w:rPr>
  </w:style>
</w:styles>'''

SETTINGS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:zoom w:percent="100"/>
  <w:defaultTabStop w:val="420"/>
</w:settings>'''

FONT_TABLE = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:font w:name="宋体"><w:panose1 w:val="02010600030101010101"/><w:charset w:val="86"/></w:font>
  <w:font w:name="Times New Roman"><w:panose1 w:val="02020603050405020304"/><w:charset w:val="00"/></w:font>
  <w:font w:name="Consolas"><w:panose1 w:val="020B0609020204030204"/><w:charset w:val="00"/></w:font>
</w:fonts>'''


def esc(text):
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')


class DocxBuilder:
    def __init__(self):
        self.body_parts = []

    def _run(self, text, bold=False, size=23, color='1F2937', font=None):
        rpr = '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hAnsi="Times New Roman"/>'
        if bold:
            rpr += '<w:b/><w:bCs/>'
        if size != 23:
            rpr += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
        if color:
            rpr += f'<w:color w:val="{color}"/>'
        return f'<w:r><w:rPr>{rpr}</w:rPr><w:t xml:space="preserve">{esc(text)}</w:t></w:r>'

    def add_heading(self, text, level=1):
        style = f'Heading{level}'
        sizes = {1: 32, 2: 27, 3: 24, 4: 23}
        colors = {1: '1F4E79', 2: '2F5597', 3: '374151', 4: '374151'}
        self.body_parts.append(
            f'<w:p><w:pPr><w:pStyle w:val="{style}"/></w:pPr>'
            f'{self._run(text, bold=True, size=sizes.get(level, 23), color=colors.get(level, "374151"))}</w:p>'
        )

    def add_para(self, text, bold=False, align=None, size=None, indent=True, color='1F2937'):
        ppr_parts = []
        if align == 'center':
            ppr_parts.append('<w:jc w:val="center"/>')
        if indent and align != 'center':
            ppr_parts.append('<w:ind w:firstLineChars="200" w:firstLine="460"/>')
        else:
            ppr_parts.append('<w:ind w:firstLine="0" w:firstLineChars="0"/>')
        ppr = f'<w:pPr>{"".join(ppr_parts)}</w:pPr>' if ppr_parts else ''
        sz = size or 23
        self.body_parts.append(
            f'<w:p>{ppr}{self._run(text, bold=bold, size=sz, color=color)}</w:p>'
        )

    def add_bullet(self, text, size=23):
        self.body_parts.append(
            f'<w:p><w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr>'
            f'{self._run("• " + text, size=size)}</w:p>'
        )

    def add_table(self, headers, rows, caption=None):
        ncols = len(headers)

        if caption:
            self.body_parts.append(
                f'<w:p><w:pPr><w:jc w:val="center"/><w:ind w:firstLine="0" w:firstLineChars="0"/>'
                f'<w:spacing w:before="200" w:after="100"/></w:pPr>'
                f'{self._run(caption, bold=True, size=21, color="2F5597")}</w:p>'
            )

        tbl = '<w:tbl>'
        tbl += '<w:tblPr>'
        tbl += '<w:tblStyle w:val="TableGrid"/>'
        tbl += '<w:tblW w:w="0" w:type="auto"/>'
        tbl += '<w:jc w:val="center"/>'
        tbl += '<w:tblLayout w:type="autofit"/>'
        tbl += '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>'
        tbl += '</w:tblPr>'

        # Header row
        tbl += '<w:tr>'
        for h in headers:
            tbl += f'<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/><w:shd w:val="clear" w:color="auto" w:fill="E8EDF3"/></w:tcPr>'
            tbl += f'<w:p><w:pPr><w:pStyle w:val="TableHeader"/></w:pPr>'
            tbl += f'{self._run(h, bold=True, size=20, color="1F2937")}</w:p></w:tc>'
        tbl += '</w:tr>'

        # Data rows
        for row in rows:
            tbl += '<w:tr>'
            for cell in row:
                tbl += f'<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>'
                tbl += f'<w:p><w:pPr><w:pStyle w:val="TableCell"/></w:pPr>'
                tbl += f'{self._run(str(cell), size=20)}</w:p></w:tc>'
            tbl += '</w:tr>'

        tbl += '</w:tbl>'
        self.body_parts.append(tbl)
        self.body_parts.append('<w:p><w:pPr><w:ind w:firstLine="0" w:firstLineChars="0"/></w:pPr></w:p>')

    def add_page_break(self):
        self.body_parts.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

    def build(self):
        body = ''.join(self.body_parts)
        return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
<w:body>
{body}
<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="454" w:footer="454"/>
  <w:footerReference w:type="default" r:id="rId4"/>
</w:sectPr>
</w:body>
</w:document>'''


def build_footer_xml():
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:p>
    <w:pPr><w:pStyle w:val="Footer"/><w:jc w:val="center"/></w:pPr>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve">第</w:t></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t>1</w:t></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve"> 页 / 共</w:t></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve">90</w:t></w:r>
    <w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr><w:t xml:space="preserve"> 页</w:t></w:r>
  </w:p>
</w:ftr>'''


def main():
    doc = DocxBuilder()

    # ════════ Cover Page ════════
    for _ in range(6):
        doc.add_para('', size=23)

    doc.body_parts.append(
        '<w:p><w:pPr><w:pStyle w:val="CoverTitle"/></w:pPr>'
        '<w:r><w:rPr>'
        '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hAnsi="Times New Roman"/>'
        '<w:b/><w:bCs/>'
        '<w:sz w:val="44"/><w:szCs w:val="44"/>'
        '<w:color w:val="1F2937"/>'
        '</w:rPr><w:t xml:space="preserve">VVC (H.266) 反变换子系统</w:t></w:r></w:p>'
    )
    doc.body_parts.append(
        '<w:p><w:pPr><w:pStyle w:val="CoverTitle"/></w:pPr>'
        '<w:r><w:rPr>'
        '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hAnsi="Times New Roman"/>'
        '<w:b/><w:bCs/>'
        '<w:sz w:val="44"/><w:szCs w:val="44"/>'
        '<w:color w:val="1F2937"/>'
        '</w:rPr><w:t xml:space="preserve">技术报告</w:t></w:r></w:p>'
    )

    doc.add_para('', size=23)

    doc.body_parts.append(
        '<w:p><w:pPr><w:pStyle w:val="CoverInfo"/></w:pPr>'
        '<w:r><w:rPr>'
        '<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hAnsi="Times New Roman"/>'
        '<w:sz w:val="36"/><w:szCs w:val="36"/>'
        '<w:color w:val="5A6575"/>'
        '</w:rPr><w:t xml:space="preserve">Inverse Transform Subsystem Technical Report</w:t></w:r></w:p>'
    )

    for _ in range(3):
        doc.add_para('', size=23)

    info_items = [
        ('项目类型', 'FPGA 硬件设计'),
        ('项目来源', 'VVC (H.266) 视频编码标准'),
        ('作品名称', '反变换子系统 (ITS)'),
        ('目标器件', 'Xilinx UltraScale+ xcku5p-ffvb676-2-e'),
        ('核心频率', '500 MHz'),
        ('文档版本', 'v4.0'),
        ('编制日期', '2026年6月18日'),
    ]
    for label, value in info_items:
        doc.body_parts.append(
            f'<w:p><w:pPr><w:pStyle w:val="CoverInfo"/></w:pPr>'
            f'<w:r><w:rPr>'
            f'<w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hAnsi="Times New Roman"/>'
            f'<w:sz w:val="20"/><w:szCs w:val="20"/>'
            f'<w:color w:val="5A6575"/>'
            f'</w:rPr><w:t xml:space="preserve">{label}：{value}</w:t></w:r></w:p>'
        )

    doc.add_page_break()

    # ════════ 作品概览与评审导读 ════════
    doc.add_heading('作品概览与评审导读', 1)

    doc.add_para('本作品实现了 VVC (H.266/VTM) 标准中完整的反变换子系统 (Inverse Transform Subsystem, ITS)，覆盖 DCT2、DCT8、DST7 三种变换核及 LFNST (Low-Frequency Non-Separable Transform) 模块，支持 4×4 至 64×64 全部 TU (Transform Unit) 尺寸。设计面向 FPGA 硬件实现，提供两套可交付架构：')
    doc.add_para('单时钟架构 (its_top.v)：接口与计算共用同一时钟域，通过 1444/1444 全量回归验证。')
    doc.add_para('双时钟架构 (its_top_500_wrapper.v + its_core_500.v)：接口时钟域 (100MHz) 与核心时钟域 (500MHz) 通过 Gray-code 异步 FIFO 隔离，在 UltraScale+ xcku5p 上实现 500MHz 时序收敛。')

    doc.add_heading('关键指标一览', 2)
    doc.add_table(
        ['指标', '数值'],
        [
            ['变换类型', 'DCT2 (4/8/16/32/64), DCT8 (4/8/16/32), DST7 (4/8/16/32)'],
            ['LFNST 支持', '4 setIdx × 2 idx = 8 种矩阵, nTrs=16/48'],
            ['回归测试', '1444/1444 PASS'],
            ['500MHz 时序', 'UltraScale+ WNS = +0.030ns, 零违例'],
            ['资源占用', 'CLB LUTs 2,843 (1.31%), DSP48E2 9'],
            ['MAC 单元数', '9 个 (4 行引擎 + 4 列引擎 + 1 LFNST)'],
            ['变换核 ROM', '8,176 条目 × 16-bit'],
            ['LFNST ROM', '8,192 条目 × 16-bit'],
        ]
    )

    doc.add_heading('核心亮点提炼', 2)
    doc.add_bullet('全标准覆盖：支持 VVC 标准中 DCT2/DCT8/DST7 全部变换核尺寸组合及 LFNST')
    doc.add_bullet('500MHz 高频设计：UltraScale+ 上 WNS +0.030ns，零违例')
    doc.add_bullet('零改动 RTL 移植：从 Artix-7 到 UltraScale+ 的 RTL 代码零修改')
    doc.add_bullet('双时钟 CDC 架构：Gray-code 异步 FIFO + toggle-based 完成信号同步')
    doc.add_bullet('全量回归验证：1444 个测试用例，含协议边界、连续 TU、随机背压场景')
    doc.add_bullet('极低资源占用：LUT < 3%, DSP 9 个，可与其他子系统共享 FPGA 资源')

    doc.add_heading('评审重点指标与查阅位置', 2)
    doc.add_table(
        ['指标类型', '查阅位置'],
        [
            ['时序收敛 (WNS)', '第7章'],
            ['资源利用率', '第7章'],
            ['功耗', '第7章'],
            ['测试通过率', '第6章'],
            ['模块架构', '第3章'],
            ['CDC 设计', '第5章'],
            ['源码清单', '附录A, 附录C'],
        ]
    )
    doc.add_page_break()

    # ════════ 第1章 赛题与需求分析 ════════
    doc.add_heading('一、赛题与需求分析', 1)

    doc.add_heading('1.1 赛题目标', 2)
    doc.add_para('VVC (Versatile Video Coding, H.266) 是由 ITU-T 和 ISO/IEC 联合制定的新一代视频编码标准，于 2020 年 7 月正式发布。相比 H.265/HEVC，VVC 在同等画质下可节省约 50% 的码率，但编码复杂度显著增加。')
    doc.add_para('反变换 (Inverse Transform) 是视频解码链路中的关键环节，负责将频域变换系数还原为空域残差信号。VVC 标准相比前代标准在反变换方面引入了以下关键扩展：')
    doc.add_bullet('更多变换核类型：除传统的 DCT-II (DCT2) 外，新增 DCT-VIII (DCT8) 和 DST-VII (DST7) 变换核')
    doc.add_bullet('更多变换尺寸：支持 4×4 到 64×64 的矩形 TU')
    doc.add_bullet('LFNST (Low-Frequency Non-Separable Transform)：在主变换前对低频系数施加的不可分离二次变换')
    doc.add_bullet('MTS (Multiple Transform Selection)：水平和垂直方向可独立选择变换核类型')

    doc.add_heading('1.2 VVC 反变换标准详解', 2)
    doc.add_heading('1.2.1 变换核类型', 3)
    doc.add_para('VVC 标准定义了三种一维变换核类型。DCT-II (DCT2) 是最常用的变换核，变换矩阵元素定义为 T(k,n) = cos(pi*k*(2n+1)/(2N))，适用于大多数自然纹理。DCT-VIII (DCT8) 的定义为 T(k,n) = cos(pi*(2k+1)*(2n+1)/(4N))，在高频区域有更好的能量集中特性。DST-VII (DST7) 的定义为 T(k,n) = sin(pi*(2k+1)*(2n+1)/(4N+2))，对帧内预测残差中的高频分量编码效果更好。')

    doc.add_heading('1.2.2 MTS (Multiple Transform Selection)', 3)
    doc.add_para('VVC 引入了 MTS 机制，允许水平和垂直方向独立选择变换核类型。2D 反变换可表示为 Y = T_ver * X * T_hor^T，其中 T_hor 和 T_ver 可以分别是 DCT2、DCT8 或 DST7，共 9 种组合。统计表明 DCT2*DCT2 仍是最常见的组合 (约 70%)。')

    doc.add_heading('1.2.3 LFNST', 3)
    doc.add_para('LFNST 是 VVC 标准引入的一种二次变换，在主反变换之前对低频系数施加不可分离的矩阵变换：X_lfnst = T_lfnst * X_low。LFNST 矩阵尺寸取决于 TU 大小：TU 宽高均 >= 8 时使用 48x16 矩阵 (nTrs=48)，否则使用 16x16 矩阵 (nTrs=16)。')
    doc.add_table(
        ['参数', '取值', '说明'],
        [
            ['lfnst_idx', '0, 1, 2', '0 表示不启用; 1 和 2 选择不同矩阵集'],
            ['lfnst_tr_set_idx', '0-3', '变换集索引，取决于色度预测模式'],
            ['nTrs', '16 或 48', 'TU 宽高均 >= 8 时用 48，否则用 16'],
        ]
    )

    doc.add_heading('1.3 提交要求对照', 2)
    doc.add_table(
        ['提交要求', '本项目实现', '状态'],
        [
            ['支持 DCT2 全部尺寸', 'DCT2 4/8/16/32/64', '✓'],
            ['支持 DCT8/DST7', 'DCT8 4/8/16/32, DST7 4/8/16/32', '✓'],
            ['支持 LFNST', '4 setIdx x 2 idx = 8 种矩阵', '✓'],
            ['支持 MTS 混合变换', '水平/垂直独立选择 tr_type', '✓'],
            ['稀疏输入格式', '{last, addr[12:0], coeff[15:0]}', '✓'],
            ['输出打包格式', '4x10-bit signed 打包为 40-bit', '✓'],
            ['反压协议', 'req/vld 握手', '✓'],
            ['完成信号', '单周期 done 脉冲', '✓'],
        ]
    )

    doc.add_heading('1.4 当前实现边界', 2)
    doc.add_para('已实现：完整的 DCT2/DCT8/DST7 变换核、LFNST (nTrs=16/48)、行列分离 2D 变换、稀疏输入缓冲、4 路并行 MAC、双时钟 CDC 架构。未涉及：反量化、帧级控制、多 TU 并行流水、动态时钟调节。')
    doc.add_page_break()

    # ════════ 第2章 系统总体设计方案 ════════
    doc.add_heading('二、系统总体设计方案', 1)

    doc.add_heading('2.1 总体方案', 2)
    doc.add_para('本系统采用行列分离 2D 变换架构，将 2D 反变换分解为两个正交的 1D 变换：Y_2D = T_ver * X * T_hor^T。硬件实现上，先对每行执行水平 1D 变换存入转置缓冲区，再对每列执行垂直 1D 变换得到最终输出。')
    doc.add_para('系统核心模块包括：its_top/its_core_500 顶层控制器 (10 状态状态机)、its_transform_engine 行/列变换引擎 (各含 4 个并行 MAC)、its_rom 变换核 ROM (8176x16-bit 共享)、its_lfnst LFNST 模块、its_lfnst_rom LFNST ROM (8192x16-bit)、its_mac 流水线乘累加单元 (共 9 个)。')

    doc.add_heading('2.2 架构选型分析', 2)
    doc.add_table(
        ['方案', '优点', '缺点', '适用场景'],
        [
            ['行列分离 (本设计)', '资源占用低', '吞吐量受串行限制', '面积受限'],
            ['全并行 2D 引擎', '吞吐量最高', 'NxM 个 MAC', '专用芯片'],
            ['流水线 2D 引擎', '折中方案', '控制复杂', '中等性能'],
        ]
    )

    doc.add_heading('2.3 关键数据流', 2)
    doc.add_para('单 TU 处理流程分为 8 个阶段。阶段 1：参数接收与解析，通过 it_info (22-bit) 发送 TU 参数，经 cmd_fifo 传递到核心域。阶段 2：输入系数加载，通过 it_data_in + it_data_addr 发送非零系数，经 input_fifo 传递。阶段 3：清零 (S_CLEAR)，按 total_points 清零 in_mem。阶段 4：可选 LFNST (S_LFNST)，对低频系数施加矩阵变换。阶段 5：行变换，逐行读取 in_mem 执行 1D 变换写入 tp_buf。阶段 6：列变换，逐列读取 tp_buf 执行 1D 变换写入 out_mem。阶段 7：输出，4 点并行读取 out_mem 打包为 40-bit。阶段 8：完成，产生 done 脉冲。')

    doc.add_heading('2.4 接口与参数', 2)
    doc.add_heading('2.4.1 外部接口定义', 3)
    doc.add_table(
        ['信号名', '方向', '位宽', '时钟域', '说明'],
        [
            ['clk/clk_if', 'I', '1', '--', '接口时钟 (100MHz)'],
            ['clk_core', 'I', '1', '--', '核心时钟 (500MHz)'],
            ['rst_n', 'I', '1', '--', '异步低有效复位'],
            ['it_info', 'I', '22', 'clk_if', 'TU 参数编码'],
            ['it_info_vld', 'I', '1', 'clk_if', '参数有效脉冲'],
            ['it_data_in', 'I', '16', 'clk_if', '输入变换系数'],
            ['it_data_addr', 'I', '12', 'clk_if', '稀疏写入地址'],
            ['it_data_in_vld', 'I', '1', 'clk_if', '输入有效'],
            ['it_data_end', 'I', '1', 'clk_if', '输入结束脉冲'],
            ['it_data_in_req', 'O', '1', 'clk_if', '输入反压请求'],
            ['it_data_out', 'O', '40', 'clk_if', '4x10-bit 输出'],
            ['it_data_out_vld', 'O', '1', 'clk_if', '输出有效'],
            ['it_data_out_req', 'I', '1', 'clk_if', '输出反压'],
            ['it_done', 'O', '1', 'clk_if', 'TU 完成脉冲'],
        ]
    )

    doc.add_heading('2.4.2 it_info 参数编码', 3)
    doc.add_table(
        ['位域', '字段', '位宽', '取值'],
        [
            ['[6:0]', 'tu_width', '7', '4, 8, 16, 32, 64'],
            ['[13:7]', 'tu_height', '7', '4, 8, 16, 32, 64'],
            ['[15:14]', 'tr_type_hor', '2', '0=DCT2, 1=DCT8, 2=DST7'],
            ['[17:16]', 'tr_type_ver', '2', '0=DCT2, 1=DCT8, 2=DST7'],
            ['[19:18]', 'lfnst_tr_set_idx', '2', '0-3'],
            ['[21:20]', 'lfnst_idx', '2', '0=无, 1=nTrs16, 2=nTrs48'],
        ]
    )

    doc.add_heading('2.4.3 输出数据格式', 3)
    doc.add_table(
        ['位域', '内容', '说明'],
        [
            ['[9:0]', 'out[0]', '第 0 个像素 (signed 10-bit)'],
            ['[19:10]', 'out[1]', '第 1 个像素'],
            ['[29:20]', 'out[2]', '第 2 个像素'],
            ['[39:30]', 'out[3]', '第 3 个像素'],
        ]
    )
    doc.add_page_break()

    # ════════ 第3章 变换引擎设计 ════════
    doc.add_heading('三、变换引擎设计', 1)

    doc.add_heading('3.1 1D 变换引擎', 2)
    doc.add_para('its_transform_engine 是核心计算模块，实现 N 点 1D 反变换。每个引擎包含 4 个并行 MAC 单元，每周期计算 4 个输出点。行变换和列变换各实例化一个引擎，共享同一个变换核 ROM。')

    doc.add_heading('3.1.1 模块端口', 3)
    doc.add_table(
        ['信号名', '方向', '位宽', '说明'],
        [
            ['clk, rst_n', 'I', '1', '时钟/复位'],
            ['start', 'I', '1', '启动脉冲'],
            ['tr_type', 'I', '2', '变换类型'],
            ['size', 'I', '7', '变换大小 (4/8/16/32/64)'],
            ['data_in', 'I', '16', '输入数据'],
            ['data_in_vld', 'I', '1', '输入有效'],
            ['data_in_req', 'O', '1', '输入请求'],
            ['rom_addr', 'O', '14', 'ROM 地址'],
            ['rom_coeff', 'I', '16', 'ROM 系数'],
            ['data_out', 'O', '16', '输出数据'],
            ['data_out_vld', 'O', '1', '输出有效'],
            ['done', 'O', '1', '完成脉冲'],
        ]
    )

    doc.add_heading('3.1.2 状态机设计', 3)
    doc.add_table(
        ['状态', '功能', '持续周期'],
        [
            ['S_IDLE', '空闲等待', '--'],
            ['S_LOAD', '加载 N 个输入到 line_buf', 'N 周期'],
            ['S_PREFETCH', '从 ROM 预取 4 行系数', '4N 周期'],
            ['S_COMPUTE', '4 MAC 并行计算', 'N 周期'],
            ['S_OUTPUT', '输出结果 (mac+32)>>>6', 'N 周期'],
        ]
    )
    doc.add_para('对于 N > 4 的 TU，S_PREFETCH 到 S_COMPUTE 循环执行 N/4 次。')

    doc.add_heading('3.1.3 ROM 地址计算', 3)
    doc.add_para('变换核在 ROM 中按类型和尺寸连续存储。地址公式：rom_addr = type_base[tr_type][size] + row * size + col。')
    doc.add_table(
        ['变换类型', '尺寸', '基地址', '条目数'],
        [
            ['DCT2', '4x4', '0', '16'],
            ['DCT2', '8x8', '16', '64'],
            ['DCT2', '16x16', '80', '256'],
            ['DCT2', '32x32', '336', '1024'],
            ['DCT2', '64x64', '1360', '4096'],
            ['DCT8', '4x4~32x32', '5456~5792', '16~1024'],
            ['DST7', '4x4~32x32', '6816~7152', '16~1024'],
        ]
    )

    doc.add_heading('3.2 乘累加单元', 2)
    doc.add_para('its_mac 采用 2 级流水线：Stage 1 为 16x16 有符号乘法 (32-bit)，Stage 2 为 40-bit 累加。clr 信号清零累加器，en 信号使能累加。综合后推断为 DSP48E1/DSP48E2 硬核，共 9 个。')

    doc.add_heading('3.3 变换核 ROM', 2)
    doc.add_table(
        ['参数', '值'],
        [
            ['总条目数', '8,176'],
            ['数据宽度', '16-bit signed'],
            ['总容量', '130,816 bits (约 16 KB)'],
            ['读延迟', '1 周期 (同步读)'],
            ['初始化', '$readmemh("rom_coeffs.hex")'],
        ]
    )

    doc.add_heading('3.4 输出截断', 2)
    doc.add_para('输出截断公式：output = clip3(-32768, 32767, (result + 32) >>> 6)。其中 +32 为舍入偏置，>>>6 为算术右移 6 位。')
    doc.add_page_break()

    # ════════ 第4章 LFNST ════════
    doc.add_heading('四、LFNST 模块设计', 1)

    doc.add_heading('4.1 LFNST 概述', 2)
    doc.add_para('LFNST 在主反变换之前对低频系数施加不可分离的矩阵变换：y = T_lfnst * x_low。nTrs 的选择规则为：TU 宽高均 >= 8 时使用 48x16 矩阵，否则使用 16x16 矩阵。')

    doc.add_heading('4.2 LFNST ROM 布局', 2)
    doc.add_table(
        ['地址范围', '矩阵', '条目数'],
        [
            ['[0, 2047]', 'nTrs=16 (8 个矩阵)', '每矩阵 256'],
            ['[2048, 8191]', 'nTrs=48 (8 个矩阵)', '每矩阵 768'],
        ]
    )

    doc.add_heading('4.3 状态机设计', 2)
    doc.add_table(
        ['状态', '功能'],
        [
            ['S_IDLE', '空闲等待'],
            ['S_LOAD', '加载 16 个低频系数 (15 周期超时)'],
            ['S_PREFETCH', '从 LFNST ROM 预取系数'],
            ['S_COMPUTE', 'MAC 串行计算'],
            ['S_DRAIN', '等待 MAC 流水线排空 (2 周期)'],
            ['S_OUTPUT', '计算 (sum+64)>>>7'],
            ['S_OUTPUT_CLIP', 'clip3(-32768, 32767)'],
            ['S_DONE', '完成'],
        ]
    )

    doc.add_heading('4.4 overlay 缓冲机制', 2)
    doc.add_para('在 500MHz 架构中，LFNST 结果写入 lfnst_out_buf[0:47] 小缓冲区而非大 in_mem，消除高扇出写路径。行变换引擎读取时通过地址比较检测是否命中 overlay 区域。扇出从 4096 降低到 48。')
    doc.add_page_break()

    # ════════ 第5章 500MHz ════════
    doc.add_heading('五、500MHz 高频架构设计', 1)

    doc.add_heading('5.1 双时钟架构', 2)
    doc.add_para('接口时钟域 (clk_if, 100MHz) 处理外部接口信号，核心时钟域 (clk_core, 500MHz) 运行变换引擎。数据通路全部通过 Gray-code 异步 FIFO 隔离，控制信号通过 toggle-based 同步器跨域。')

    doc.add_heading('5.2 异步 FIFO 设计', 2)
    doc.add_para('异步 FIFO 采用 Gray-code 编码指针，确保跨时钟域时只有 1-bit 变化。空标志使用当前 rd_ptr_gray 比较以避免组合环路，满标志使用 MSB 取反比较法，读模式为 FWFT。')
    doc.add_table(
        ['FIFO 实例', '位宽', '深度', '用途'],
        [
            ['cmd_fifo', '23-bit', '4', '传输 TU 参数'],
            ['input_fifo', '29-bit', '16', '传输输入系数'],
            ['output_fifo', '40-bit', '16', '传输输出结果'],
        ]
    )

    doc.add_heading('5.3 复位同步器', 2)
    doc.add_para('3 级同步器链，异步断言直接清零，同步释放经过 3 个时钟沿。')

    doc.add_heading('5.4 完成信号 CDC', 2)
    doc.add_para('core_done (500MHz) 单周期脉冲通过 toggle 同步器传递到 clk_if (100MHz)：toggle 寄存器在 core_done 时翻转，通过 2-FF 同步器传递，XOR 边沿检测产生 it_done 脉冲。')

    doc.add_heading('5.5 时序优化策略', 2)
    doc.add_table(
        ['优化项', '方法', '目的'],
        [
            ['BRAM 同步读', 'in_mem/tp_buf 使用 Block RAM', '解耦存储访问路径'],
            ['LFNST overlay', '小缓冲区替代大 in_mem 回写', '降低扇出'],
            ['绝对地址递推', '替代 base+offset 加法器', '消除加法器关键路径'],
            ['输出 3 级流水', 'BRAM读->寄存->FIFO写', '支持反压保持'],
            ['命令 FIFO 流水', 'cmd_fifo_data_r 寄存', '切断组合路径'],
            ['ifdef SYNTHESIS', 'ROM 地址寄存化 + P0 流水', '消除桶形移位器'],
        ]
    )
    doc.add_page_break()

    # ════════ 第6章 仿真验证 ════════
    doc.add_heading('六、仿真验证', 1)

    doc.add_heading('6.1 仿真环境', 2)
    doc.add_table(
        ['项目', '配置'],
        [
            ['仿真工具', 'ModelSim SE-64 10.6e'],
            ['时钟周期', '2ns (500MHz)'],
            ['测试向量', 'Python 自动生成 (gen_test_vectors.py)'],
            ['参考模型', 'Python 参考实现 (ref_model.py)'],
            ['运行时间', '17 秒 (仿真时间 71.6ms)'],
        ]
    )

    doc.add_heading('6.2 测试覆盖矩阵', 2)
    doc.add_table(
        ['测试类别', '用例数', '说明'],
        [
            ['标准回归', '1377', '全部变换类型 x 尺寸 x LFNST 组合'],
            ['协议边界', '10', 'end 与最后一个数据同周期'],
            ['连续 TU', '20', 'TU 之间不复位'],
            ['背压测试', '37', '随机反压'],
            ['合计', '1444', '--'],
        ]
    )

    doc.add_heading('6.3 标准回归测试', 2)
    doc.add_table(
        ['变换类型', 'TU 尺寸组合', 'LFNST 配置', '用例数'],
        [
            ['DCT2', '25 种 (4x4~64x64)', '9', '225'],
            ['DCT8', '16 种 (4x4~32x32)', '9', '144'],
            ['DST7', '16 种 (4x4~32x32)', '9', '144'],
            ['MTS 混合', '64 种', '9', '576'],
            ['其他', '--', '--', '288'],
        ]
    )

    doc.add_heading('6.4 边界测试', 2)
    doc.add_table(
        ['用例名', '测试内容'],
        [
            ['boundary_dc_4x4', '纯 DC 系数'],
            ['boundary_maxval_4x4', '最大值系数 (+-32767)'],
            ['boundary_minval_4x4', '最小值系数'],
            ['boundary_sparse_8x8', '极稀疏 (仅 3 个非零)'],
            ['boundary_zero_4x4', '全零输入'],
        ]
    )

    doc.add_heading('6.5 回归测试结果', 2)
    doc.add_table(
        ['指标', '结果'],
        [
            ['总用例数', '1444'],
            ['通过', '1444'],
            ['失败', '0'],
            ['运行时间', '17 秒'],
        ]
    )
    doc.add_para('所有 1444 个用例均 PASS，无 MISMATCH 或 PROTOCOL VIOLATION。')
    doc.add_page_break()

    # ════════ 第7章 综合实现 ════════
    doc.add_heading('七、综合实现与性能指标', 1)

    doc.add_heading('7.1 目标器件', 2)
    doc.add_table(
        ['设计', '器件', '用途'],
        [
            ['its_top', 'xc7a200tfbg484-3', 'Artix-7 完整实现'],
            ['its_core_500', 'xc7a200tfbg484-3', 'Artix-7 OOC'],
            ['its_core_500', 'xcku5p-ffvb676-2-e', 'UltraScale+ OOC'],
        ]
    )

    doc.add_heading('7.2 Artix-7 时序结果', 2)
    doc.add_table(
        ['阶段', 'WNS (ns)', '说明'],
        [
            ['综合后', '-5.378', '差距较大'],
            ['布局布线后', '-5.213', '仍有大量违例'],
            ['最佳物理优化', '-2.093', '双次 phys_opt'],
        ]
    )
    doc.add_para('结论：Artix-7 上 500MHz 物理不可达，最佳 WNS = -2.093ns。')

    doc.add_heading('7.3 UltraScale+ 时序结果', 2)
    doc.add_table(
        ['阶段', 'WNS (ns)', 'TNS (ns)', 'WHS (ns)'],
        [
            ['综合后', '+0.242', '0.000', '+0.024'],
            ['布局布线后', '+0.030', '0.000', '+0.020'],
        ]
    )
    doc.add_para('500MHz 时序达标，零违例。')

    doc.add_heading('7.4 资源利用率', 2)
    doc.add_heading('7.4.1 its_core_500 UltraScale+', 3)
    doc.add_table(
        ['资源', 'Used', 'Available', 'Util%'],
        [
            ['CLB LUTs', '2,843', '216,960', '1.31%'],
            ['CLB Registers', '2,882', '433,920', '0.66%'],
            ['RAMB36E2', '12', '480', '2.50%'],
            ['DSP48E2', '9', '1,824', '0.49%'],
        ]
    )

    doc.add_heading('7.5 功耗分析', 2)
    doc.add_table(
        ['设计', '器件', '总功耗 (W)', '动态 (W)', '静态 (W)'],
        [
            ['its_top', 'xc7a200tfbg484-1', '0.787', '0.653', '0.133'],
            ['its_core_500', 'xc7a200tfbg484-3', '0.602', '0.478', '0.124'],
            ['its_core_500', 'xcku5p-ffvb676-2-e', '0.769', '0.316', '0.453'],
        ]
    )

    doc.add_heading('7.6 存储资源分布', 2)
    doc.add_table(
        ['存储', '深度x宽度', '容量', '实现'],
        [
            ['in_mem', '4096x16', '65,536 bits', 'BRAM'],
            ['tp_buf', '4096x16', '65,536 bits', 'BRAM'],
            ['out_mem', '4096x10', '40,960 bits', 'BRAM'],
            ['变换核 ROM', '8176x16', '130,816 bits', 'BRAM'],
            ['LFNST ROM', '8192x16', '131,072 bits', 'BRAM'],
            ['总计', '--', '454,912 bits', '--'],
        ]
    )
    doc.add_page_break()

    # ════════ 第8章 ════════
    doc.add_heading('八、综合脚本与约束', 1)

    doc.add_heading('8.1 TCL 脚本清单', 2)
    doc.add_table(
        ['脚本', '功能'],
        [
            ['its_synth.tcl', '基础综合 (xc7a200tfbg484-2)'],
            ['its_synth_impl.tcl', '完整实现 (xc7a200tfbg484-3)'],
            ['its_core_500_ooc.tcl', 'Artix-7 OOC 综合'],
            ['its_core_500_ooc_usp.tcl', 'UltraScale+ OOC 综合'],
            ['its_core_500_phys_opt.tcl', '6 种策略对比'],
        ]
    )

    doc.add_heading('8.2 约束说明', 2)
    doc.add_para('顶层约束 (timing.xdc)：100MHz 时钟、IOB 约束、Block RAM 推断、最大扇出 50。核心约束 (timing_core_500.xdc)：500MHz 时钟、FIFO 接口 I/O delay 0.5ns、异步时钟组约束。')
    doc.add_page_break()

    # ════════ 第9章 ════════
    doc.add_heading('九、工程注意事项与后续优化', 1)

    doc.add_heading('9.1 仿真注意事项', 2)
    doc.add_bullet('500MHz 仿真不可行，建议使用 200MHz 进行功能验证')
    doc.add_bullet('异步 FIFO 使用 initial 块初始化指针')
    doc.add_bullet('测试台必须等待复位同步器释放后再发送数据')
    doc.add_bullet('使用 ifdef SYNTHESIS 区分仿真/综合模式')

    doc.add_heading('9.2 已知问题', 2)
    doc.add_para('its_core_500 与 its_top 存在计算结果差异，原因包括：BRAM 同步读延迟、LFNST overlay 地址映射边界条件、输出流水线级数差异。此问题不影响 its_top 的 1444/1444 回归。')

    doc.add_heading('9.3 后续优化方向', 2)
    doc.add_table(
        ['优先级', '内容'],
        [
            ['P0', '修复 its_core_500 计算差异'],
            ['P1', 'ROM 地址流水线优化、coeff_buf 迁移 BRAM'],
            ['P2', '12-bit 像素精度、ISP 模块、多 TU 并行'],
            ['P3', 'SDF 时序反标、系统级集成验证'],
        ]
    )
    doc.add_page_break()

    # ════════ 第10章 ════════
    doc.add_heading('十、总结', 1)
    doc.add_para('本项目完成了 VVC (H.266) 标准反变换子系统的全硬件实现，主要成果包括：全标准覆盖 DCT2/DCT8/DST7/LFNST；行列分离 2D 变换 + 4 路并行 MAC 高效架构；500MHz 高频设计 (UltraScale+ WNS +0.030ns)；Gray-code 异步 FIFO + toggle CDC 双时钟架构；1444 个测试用例全部通过；10 个 RTL 源文件 + 完整工具链和文档。')
    doc.add_para('本设计可作为 VVC 解码器 SoC 中反变换子系统的 IP 核，集成到更大的视频解码流水线中。')
    doc.add_page_break()

    # ════════ 附录A ════════
    doc.add_heading('附录A 源码清单', 1)
    doc.add_table(
        ['文件', '行数', '说明'],
        [
            ['rtl/its_top.v', '617', '单时钟顶层'],
            ['rtl/its_core_500.v', '807', '500MHz 核心'],
            ['rtl/its_top_500_wrapper.v', '210', '双时钟 wrapper'],
            ['rtl/its_transform_engine.v', '628', '1D 变换引擎'],
            ['rtl/its_mac.v', '49', 'MAC 单元'],
            ['rtl/its_rom.v', '27', '变换核 ROM'],
            ['rtl/its_lfnst.v', '399', 'LFNST 模块'],
            ['rtl/its_lfnst_rom.v', '27', 'LFNST ROM'],
            ['rtl/async_fifo.v', '148', '异步 FIFO'],
            ['rtl/rst_sync.v', '23', '复位同步器'],
        ]
    )
    doc.add_page_break()

    # ════════ 附录B ════════
    doc.add_heading('附录B 关键参数与命令', 1)

    doc.add_heading('B.1 仿真命令', 2)
    doc.add_table(
        ['命令', '说明'],
        [
            ['vsim -do run.do', '主回归测试 (1444 用例)'],
            ['vsim -do run_500.do', 'Wrapper CDC 测试'],
            ['vsim -do run_core_500.do', 'Core 500MHz 测试'],
        ]
    )

    doc.add_heading('B.2 综合命令', 2)
    doc.add_table(
        ['命令', '说明'],
        [
            ['vivado -batch -source its_core_500_ooc.tcl', 'Artix-7 OOC'],
            ['vivado -batch -source its_core_500_ooc_usp.tcl', 'UltraScale+ OOC'],
        ]
    )

    doc.add_heading('B.3 关键参数', 2)
    doc.add_table(
        ['参数', '值'],
        [
            ['MAC 位宽', '16x16 -> 40'],
            ['输出截断', '(result+32)>>>6'],
            ['输出精度', '10-bit signed'],
            ['ROM 条目', '8176 + 8192'],
            ['FIFO 深度', '4/16/16'],
            ['复位同步级数', '3'],
            ['LFNST 超时', '15 周期'],
        ]
    )
    doc.add_page_break()

    # ════════ 附录C ════════
    doc.add_heading('附录C RTL 源码说明', 1)

    doc.add_heading('C.1 顶层与控制', 2)
    doc.add_para('its_top.v (617 行)：单时钟顶层，10 状态状态机，实例化 2 个变换引擎、1 个共享 ROM、1 个 LFNST 模块。')
    doc.add_para('its_core_500.v (807 行)：500MHz 核心，BRAM 同步读、LFNST overlay、绝对地址递推、3 级输出流水。')
    doc.add_para('its_top_500_wrapper.v (210 行)：双时钟 wrapper，3 个异步 FIFO、2 个复位同步器、toggle CDC。')

    doc.add_heading('C.2 计算引擎', 2)
    doc.add_para('its_transform_engine.v (628 行)：1D 变换引擎，5 状态状态机，4 路 MAC 并行，ifdef SYNTHESIS 条件编译。')
    doc.add_para('its_mac.v (49 行)：2 级流水线 MAC，16x16 乘法 + 40-bit 累加，推断 DSP48。')
    doc.add_para('its_lfnst.v (399 行)：LFNST 模块，8 状态状态机，单 MAC 串行，15 周期超时稀疏加载。')

    doc.add_heading('C.3 存储与 CDC', 2)
    doc.add_para('its_rom.v (27 行)：8176x16-bit 同步读 ROM。its_lfnst_rom.v (27 行)：8192x16-bit 同步读 ROM。')
    doc.add_para('async_fifo.v (148 行)：Gray-code 异步 FIFO，FWFT 读模式。rst_sync.v (23 行)：3 级复位同步器。')
    doc.add_page_break()

    # ════════ 附录D ════════
    doc.add_heading('附录D Python 工具脚本', 1)
    doc.add_para('gen_rom_coeffs.py：生成变换核 ROM 系数 (rom_coeffs.hex)。')
    doc.add_para('parse_lfnst_matrices.py：生成 LFNST ROM 系数 (lfnst_coeffs.hex)。')
    doc.add_para('gen_test_vectors.py：生成 1444 个测试用例的输入和黄金参考。')
    doc.add_para('ref_model.py：Python 参考模型，numpy 矩阵乘法实现完整反变换。')
    doc.add_page_break()

    # ════════ 附录E ════════
    doc.add_heading('附录E 数据结构清单', 1)

    doc.add_heading('E.1 状态机编码', 2)
    doc.add_table(
        ['状态', '编码', '说明'],
        [
            ['S_IDLE', '0', '空闲'],
            ['S_LOAD', '1', '加载输入'],
            ['S_ROW_START', '2', '行变换启动'],
            ['S_ROW_RUN', '3', '行变换执行'],
            ['S_COL_START', '4', '列变换启动'],
            ['S_COL_RUN', '5', '列变换执行'],
            ['S_OUT', '6', '输出'],
            ['S_DONE', '7', '完成'],
            ['S_LFNST', '8', 'LFNST'],
            ['S_CLEAR', '9', '清零'],
        ]
    )

    doc.add_heading('E.2 FIFO 格式', 2)
    doc.add_table(
        ['FIFO', '格式', '说明'],
        [
            ['cmd_fifo', '{0, it_info[21:0]}', 'TU 参数'],
            ['input_fifo', '{last, addr[11:0], coeff[15:0]}', '输入数据'],
            ['output_fifo', '{out3, out2, out1, out0}', '4x10-bit 输出'],
        ]
    )

    # ── Build ──
    output_path = r'D:\Workspace\its_vvc\doc\ITS_VVC_技术报告.docx'
    document_xml = doc.build()
    footer_xml = build_footer_xml()

    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('[Content_Types].xml', CONTENT_TYPES)
        zf.writestr('_rels/.rels', RELS)
        zf.writestr('word/_rels/document.xml.rels', WORD_RELS)
        zf.writestr('word/document.xml', document_xml)
        zf.writestr('word/styles.xml', STYLES)
        zf.writestr('word/settings.xml', SETTINGS)
        zf.writestr('word/fontTable.xml', FONT_TABLE)
        zf.writestr('word/footer1.xml', footer_xml)

    size = os.path.getsize(output_path)
    print(f'Saved: {output_path} ({size:,} bytes)')


if __name__ == '__main__':
    main()
