
## Rakazo computer environment

The complete Skill files are installed under `/opt/rakazo/skills/`, in a folder
matching each Skill's name. Resolve this Skill's relative script, reference, and
asset paths against its installed folder, and inspect them with `shell` when
needed. Only `SKILL.md` is imported into Rakazo's library; read supporting files
with `shell`, not `skill_read`.
For example, run the DOCX validator as
`python3 /opt/rakazo/skills/docx/scripts/office/validate.py /absolute/path/report.docx`.
Resolve links inside reference documents relative to the document containing them.

Use the preinstalled system `python3` and `node` for document scripts. The image
provides the document Python/Node dependencies, LibreOffice (`soffice`),
Tesseract with English and simplified Chinese, Poppler, Pandoc, and qpdf.
Save multiline scripts with `write_file` before running them; the shell guard
rejects interpreter heredocs.

Run project work in the current Bot workspace. Save user-facing outputs under
its `exports/` and use `attach_file` with a relative path, for example
`exports/report.pdf`. This replaces instructions that assume `/workspace`,
`/mnt/data`, or another assistant's output directory.
Rakazo accepts PDF, XLSX and ZIP attachments. Bundle DOCX/PPTX deliverables, e.g.
`python3 -m zipfile -c exports/documents.zip exports/report.docx exports/slides.pptx`
before attaching the ZIP.
