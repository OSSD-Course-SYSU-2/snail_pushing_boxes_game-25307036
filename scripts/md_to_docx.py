#!/usr/bin/env python3

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
import html
import re
import sys


DOC_NAMESPACE = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


def xml_escape(text: str) -> str:
    return html.escape(text, quote=False)


def run_xml(text: str, *, bold: bool = False, size: int = 22) -> str:
    safe_text = xml_escape(text)
    preserve = ' xml:space="preserve"' if text != text.strip() or "  " in text else ""
    props = [
        "<w:rPr>",
        f'<w:sz w:val="{size}"/>',
        f'<w:szCs w:val="{size}"/>',
    ]
    if bold:
        props.append("<w:b/>")
    props.append("</w:rPr>")
    return f"<w:r>{''.join(props)}<w:t{preserve}>{safe_text}</w:t></w:r>"


def paragraph_xml(
    text: str,
    *,
    bold: bool = False,
    size: int = 22,
    after: int = 160,
    left: int = 0,
) -> str:
    paragraph_props = (
        "<w:pPr>"
        f'<w:spacing w:after="{after}"/>'
        f'{f"<w:ind w:left=\"{left}\"/>" if left else ""}'
        "</w:pPr>"
    )
    return f"<w:p>{paragraph_props}{run_xml(text, bold=bold, size=size)}</w:p>"


def blank_paragraph_xml() -> str:
    return "<w:p/>"


def markdown_to_document_xml(markdown_text: str) -> str:
    paragraphs: list[str] = []
    for raw_line in markdown_text.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        if not stripped:
            paragraphs.append(blank_paragraph_xml())
            continue

        if stripped.startswith("```"):
            continue

        if line.startswith("# "):
            paragraphs.append(paragraph_xml(line[2:].strip(), bold=True, size=32, after=240))
            continue

        if line.startswith("## "):
            paragraphs.append(paragraph_xml(line[3:].strip(), bold=True, size=28, after=200))
            continue

        if re.match(r"^\d+\.\s+", stripped):
            paragraphs.append(paragraph_xml(stripped, bold=True, size=22, after=120))
            continue

        if stripped.startswith("- "):
            paragraphs.append(paragraph_xml(f"• {stripped[2:].strip()}", size=22, after=120))
            continue

        if line.startswith("   ") or line.startswith("  "):
            paragraphs.append(paragraph_xml(stripped, size=22, after=120, left=420))
            continue

        paragraphs.append(paragraph_xml(stripped, size=22, after=160))

    body = "".join(paragraphs)
    section = (
        "<w:sectPr>"
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="708" w:footer="708" w:gutter="0"/>'
        "</w:sectPr>"
    )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:document xmlns:w="{DOC_NAMESPACE}">'
        f"<w:body>{body}{section}</w:body>"
        "</w:document>"
    )


def content_types_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/docProps/core.xml" '
        'ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        "</Types>"
    )


def root_relationships_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/>'
        '<Relationship Id="rId2" '
        'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
        'Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" '
        'Target="docProps/app.xml"/>'
        "</Relationships>"
    )


def core_properties_xml(title: str) -> str:
    created = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    safe_title = xml_escape(title)
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        f"<dc:title>{safe_title}</dc:title>"
        "<dc:creator>Codex</dc:creator>"
        "<cp:lastModifiedBy>Codex</cp:lastModifiedBy>"
        f'<dcterms:created xsi:type="dcterms:W3CDTF">{created}</dcterms:created>'
        f'<dcterms:modified xsi:type="dcterms:W3CDTF">{created}</dcterms:modified>'
        "</cp:coreProperties>"
    )


def app_properties_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        "<Application>Codex</Application>"
        "</Properties>"
    )


def build_docx(source_path: Path, output_path: Path) -> None:
    markdown_text = source_path.read_text(encoding="utf-8")
    title = source_path.stem
    document_xml = markdown_to_document_xml(markdown_text)

    with ZipFile(output_path, "w", compression=ZIP_DEFLATED) as docx:
        docx.writestr("[Content_Types].xml", content_types_xml())
        docx.writestr("_rels/.rels", root_relationships_xml())
        docx.writestr("docProps/core.xml", core_properties_xml(title))
        docx.writestr("docProps/app.xml", app_properties_xml())
        docx.writestr("word/document.xml", document_xml)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: md_to_docx.py <input.md> <output.docx>", file=sys.stderr)
        return 1

    source_path = Path(sys.argv[1]).resolve()
    output_path = Path(sys.argv[2]).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    build_docx(source_path, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
