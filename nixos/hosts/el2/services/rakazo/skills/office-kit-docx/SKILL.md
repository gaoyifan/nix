---
name: office-kit-docx
description: Default workflow for creating and revising editable Word documents with Office Kit. Use for reports, meeting minutes, proposals and DOCX templates; render with LibreOffice for PDF delivery and visual review.
---

# Word documents with Office Kit

Use the preinstalled ESM package `@office-kit/docx` 0.2.0. For a new project,
create a child directory in the current Bot workspace:

```sh
mkdir word-report
```

Write a `.mjs` script in that directory with `write_file`, then run it with
`node`. Do not install dependencies for each document or use the unrelated
`docx` npm package for this workflow. Read the installed
`/opt/rakazo/skills/office-kit-docx/references/examples.md` for headings, styles,
tables, images, headers/footers, templates and tracked changes. The package's
actual exports/types are in its installed `dist/`; inspect them for unfamiliar
operations instead of guessing function names.

The basic API is function-based, not a document class:

```js
import { writeFileSync } from 'node:fs';
import {
  createDocx, ensureHeadingStyles, appendHeading, appendParagraph,
  addBulletList, addTable, setPageSize, PAGE_SIZE_A4, toUint8Array,
} from '@office-kit/docx';

const doc = createDocx({ paragraphs: [] });
setPageSize(doc, PAGE_SIZE_A4);
ensureHeadingStyles(doc, 2);
appendHeading(doc, 'Meeting notes', 1);
appendParagraph(doc, 'Use the user’s actual content here.');
addBulletList(doc, ['Decision', 'Next action']);
addTable(doc, [['Owner', 'Action'], ['Team', 'Confirm the schedule']]);
writeFileSync('../exports/notes.docx', toUint8Array(doc));
```

Choose formatting appropriate to the request. Use available Chinese fonts
such as `Noto Sans CJK SC` for Chinese documents. For an existing document,
use `openDocx(bytes)`, edit the intended text or structure and save to a new file;
preserve unrelated content. The upstream examples distinguish styled templates
from placeholder-based mail merge.

Render the exported DOCX with `soffice --headless --convert-to pdf --outdir
exports <file.docx>` and inspect the PDF pages before delivery. Confirm headings,
tables and Chinese characters are readable and fix clipping or awkward page
breaks. Keep the native DOCX; PDF is an additional deliverable when requested.
Office Kit itself does not render PDF.
