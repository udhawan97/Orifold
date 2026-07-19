#!/usr/bin/env python3
"""Generate the tagged-PDF fixtures used by StructureInspectionServiceTests.

PDFKit cannot emit a structure tree, and no other tool in this repo writes tags, so
these fixtures are authored as raw PDF bytes. They are committed rather than generated
at test time because xref offsets must be byte-exact; this script exists so the next
person can regenerate or extend them instead of reverse-engineering the bytes.

Each fixture carries:
  * /MarkInfo << /Marked true >>          — what FPDFCatalog_IsTagged reads
  * /StructTreeRoot with a /Document      — the tree FPDF_StructTree_GetForPage walks
    wrapping H1 / P / Figure elements
  * /Pg back-references on every element  — PDFium associates elements to pages by /Pg
  * real marked content (BDC/EMC + MCIDs) — so the tags describe actual page content

Usage: python3 make-tagged-fixtures.py
"""

import pathlib

HERE = pathlib.Path(__file__).parent


def build_pdf(objects: list[str]) -> bytes:
    """Assemble numbered objects into a PDF with a correct xref table."""
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]

    for index, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{index} 0 obj\n".encode("latin-1")
        out += body.encode("latin-1")
        out += b"\nendobj\n"

    xref_offset = len(out)
    count = len(objects) + 1
    out += f"xref\n0 {count}\n".encode("latin-1")
    out += b"0000000000 65535 f \n"
    for offset in offsets[1:]:
        out += f"{offset:010d} 00000 n \n".encode("latin-1")
    out += (
        f"trailer\n<< /Size {count} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n"
    ).encode("latin-1")
    return bytes(out)


def content_stream() -> str:
    ops = (
        "/H1 <</MCID 0>> BDC\n"
        "BT /F1 24 Tf 72 700 Td (Heading One) Tj ET\n"
        "EMC\n"
        "/P <</MCID 1>> BDC\n"
        "BT /F1 12 Tf 72 660 Td (Body paragraph text.) Tj ET\n"
        "EMC\n"
        "/Figure <</MCID 2>> BDC\n"
        "0.85 0.2 0.2 rg 72 540 120 80 re f\n"
        "EMC\n"
    )
    return f"<< /Length {len(ops)} >>\nstream\n{ops}endstream"


def tagged(figure_alt: str | None) -> bytes:
    """A one-page tagged document. `figure_alt=None` omits /Alt on the Figure."""
    alt = f" /Alt ({figure_alt})" if figure_alt else ""
    return build_pdf([
        # 1 Catalog — /MarkInfo is what makes this document "tagged" at the catalog level.
        "<< /Type /Catalog /Pages 2 0 R /MarkInfo << /Marked true >> "
        "/StructTreeRoot 6 0 R >>",
        # 2 Pages
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        # 3 Page — /StructParents ties its marked content into the parent tree.
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        "/Resources << /Font << /F1 5 0 R >> >> /StructParents 0 >>",
        # 4 Contents
        content_stream(),
        # 5 Font
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        # 6 StructTreeRoot
        "<< /Type /StructTreeRoot /K [7 0 R] /ParentTree 11 0 R /ParentTreeNextKey 1 >>",
        # 7 Document wrapper
        "<< /Type /StructElem /S /Document /P 6 0 R /Pg 3 0 R /K [8 0 R 9 0 R 10 0 R] >>",
        # 8 H1
        "<< /Type /StructElem /S /H1 /P 7 0 R /Pg 3 0 R /K 0 /T (Heading One) >>",
        # 9 P
        "<< /Type /StructElem /S /P /P 7 0 R /Pg 3 0 R /K 1 >>",
        # 10 Figure — the alt-text tally's subject.
        f"<< /Type /StructElem /S /Figure /P 7 0 R /Pg 3 0 R /K 2{alt} >>",
        # 11 ParentTree
        "<< /Nums [0 [8 0 R 9 0 R 10 0 R]] >>",
    ])


def untagged() -> bytes:
    """Same visible content, no /MarkInfo, no /StructTreeRoot, no marked content."""
    ops = "BT /F1 24 Tf 72 700 Td (Untagged page) Tj ET\n"
    return build_pdf([
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        "/Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(ops)} >>\nstream\n{ops}endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])


def active_content() -> bytes:
    """Carries every key `hasActiveContent` looks for: /OpenAction, /AA, /Names/JavaScript."""
    ops = "BT /F1 18 Tf 72 700 Td (Active content) Tj ET\n"
    return build_pdf([
        "<< /Type /Catalog /Pages 2 0 R /OpenAction << /S /JavaScript /JS (app.alert\\(1\\);) >> "
        "/AA << /WC << /S /JavaScript /JS (app.alert\\(2\\);) >> >> "
        "/Names << /JavaScript << /Names [(script) 6 0 R] >> >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        "/Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(ops)} >>\nstream\n{ops}endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /S /JavaScript /JS (app.alert\\(3\\);) >>",
    ])


def output_intent() -> bytes:
    """Has /Root/OutputIntents and no fonts at all.

    The absent /Font dict is deliberate: it exercises the vacuous case where a page
    references no fonts, which must read as "all fonts embedded" rather than as a
    failure. Authoring a genuinely embedded font would mean shipping a font binary.
    """
    ops = "0.2 0.4 0.8 rg 72 500 200 150 re f\n"
    return build_pdf([
        "<< /Type /Catalog /Pages 2 0 R /OutputIntents [6 0 R] >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        "/Resources << >> >>",
        f"<< /Length {len(ops)} >>\nstream\n{ops}endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /OutputIntent /S /GTS_PDFA1 /OutputConditionIdentifier (sRGB) >>",
    ])


def xmp_metadata() -> bytes:
    """Catalog carries a /Metadata XMP stream."""
    xmp = (
        '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        "</rdf:RDF></x:xmpmeta><?xpacket end=\"w\"?>"
    )
    ops = "0.5 g 72 500 100 100 re f\n"
    return build_pdf([
        "<< /Type /Catalog /Pages 2 0 R /Metadata 6 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        "/Resources << >> >>",
        f"<< /Length {len(ops)} >>\nstream\n{ops}endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        f"<< /Type /Metadata /Subtype /XML /Length {len(xmp)} >>\nstream\n{xmp}\nendstream",
    ])


if __name__ == "__main__":
    written = {
        "tagged-sample.pdf": tagged("A red rectangle"),
        "tagged-no-alt.pdf": tagged(None),
        "untagged-sample.pdf": untagged(),
        "active-content.pdf": active_content(),
        "output-intent.pdf": output_intent(),
        "xmp-metadata.pdf": xmp_metadata(),
    }
    for name, payload in written.items():
        (HERE / name).write_bytes(payload)
        print(f"wrote {name} ({len(payload)} bytes)")
