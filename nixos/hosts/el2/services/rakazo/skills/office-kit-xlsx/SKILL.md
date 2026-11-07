---
name: office-kit-xlsx
description: Default workflow for creating and revising editable Excel workbooks with Office Kit. Use for budgets, formula-driven tables, formatted reports and native spreadsheet charts.
---

# Excel workbooks with Office Kit

Use the preinstalled ESM package `@office-kit/xlsx` 0.26.0. For a new project,
create a child directory in the current Bot workspace:

```sh
mkdir workbook
```

Write a `.mjs` script there with `write_file`, then run it with `node`.
No npm installation is needed. There is no root package import: use subpaths
such as `/workbook`, `/worksheet`, `/cell`, `/styles`, `/chart`, `/io`, `/node`.
Rows and columns are 1-based. Read
`/opt/rakazo/skills/office-kit-xlsx/references/cheatsheet.md` for the relevant
operations and `references/recipes/` in that same installed Skill directory
for runnable examples of styling, charts, formulas and reading existing files.
Inspect installed types for unfamiliar APIs instead of guessing names.
Use Office Kit for cell changes, styles and native charts as well as initial
workbook creation. The older spreadsheet tools can inspect or recalculate the
result; do not switch the authoring work to openpyxl on a follow-up request.
For styles, use `references/recipes/report-styles.ts`; for charts, adapt
`references/recipes/add-bar-chart.ts` and inspect `/chart` types for other kinds.

New workbooks in 0.26.0 have no theme. In LibreOffice, implicit chart colours
can therefore become invisible even though the file validates and labels show.
Set explicit RGB fills on series or data points instead of relying on
`varyColors` alone. For pie/doughnut slices, use the public `dPt` model:

```js
series.dPt = ['2563EB', 'F59E0B', '10B981'].map((value, idx) => ({
  idx,
  spPr: { fill: { kind: 'solidFill', color: { base: { kind: 'srgb', value }, mods: [] } } },
}));
```

When adding charts, render the workbook with LibreOffice and inspect the
actual chart colours, geometry and labels before delivery. Formula/XML checks
alone do not catch an invisible chart.

```js
import { saveWorkbook } from '@office-kit/xlsx/io';
import { toFile } from '@office-kit/xlsx/node';
import { createWorkbook, addWorksheet, setFullCalcOnLoad } from '@office-kit/xlsx/workbook';
import { setCell, appendRows } from '@office-kit/xlsx/worksheet';
import { makeFormula } from '@office-kit/xlsx/cell';

const wb = createWorkbook();
const ws = addWorksheet(wb, 'Budget');
appendRows(ws, [['Item', 'Amount'], ['Travel', 200], ['Meals', 100]]);
setCell(ws, 4, 1, 'Total');
setCell(ws, 4, 2, makeFormula('SUM(B2:B3)', { cachedValue: 300 }));
setFullCalcOnLoad(wb, true);
await saveWorkbook(wb, toFile('../exports/budget.xlsx'));
```

Keep formulas as formulas. This library does not evaluate them; provide a
correct cached value when it is known and request recalculation on open.
For calculations needing an engine, use the existing LibreOffice/recalculation
tools and verify resulting formulas and values. Preserve the original file.
Do not use `setCell(..., '=SUM(...)')` as a substitute for `makeFormula`.

Use native cell types, sensible number formats/column widths, clear headers and
appropriate charts. Use `Noto Sans CJK SC` for Chinese labels. For an existing
workbook, `loadWorkbook(fromFile(path))` reads it; modify only requested sheets
or cells. Verify actual saved values, formulas and chart ranges; if delivering a
printable report, also render it in LibreOffice and inspect page layout.
