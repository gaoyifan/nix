import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { parseSkillMd } from '@rakazo/core';
import { createDb, runAsSystem } from '@rakazo/db';
import { createAgentSkillsService, resolveSkillContent } from './src/agent-skills.ts';

function managed(content) {
  const parsed = parseSkillMd(content);
  return !('error' in parsed)
    && parsed.frontmatter.metadata?.['managed-by'] === 'rakazo-computer';
}

const root = process.argv[2];
if (!root) throw new Error('Usage: publish-skills.mjs <skill-directory>');
const sources = new Map();
for (const directory of await readdir(root, { withFileTypes: true })) {
  if (!directory.isDirectory()) continue;
  const content = await readFile(join(root, directory.name, 'SKILL.md'), 'utf8');
  if (!managed(content)) continue;
  const resolved = resolveSkillContent({ content });
  sources.set(resolved.name, resolved.content);
}

const { prisma, pool } = createDb(process.env.DATABASE_URL);
try {
  await runAsSystem('Publish managed computer Skills', async () => {
    const service = createAgentSkillsService(prisma);
    const rows = await prisma.agentSkill.findMany({
      where: { source: 'user', name: { in: [...sources.keys()] } },
      select: { id: true, userId: true, spaceId: true, name: true, content: true },
    });
    let updated = 0;
    let unchanged = 0;
    for (const row of rows) {
      if (!managed(row.content)) continue;
      const content = sources.get(row.name);
      if (row.content === content) {
        unchanged++;
        continue;
      }
      await service.update(
        { userId: row.userId, spaceId: row.spaceId },
        { skillId: row.id, content },
      );
      updated++;
    }
    console.log(JSON.stringify({ updated, unchanged }));
  });
} finally {
  await prisma.$disconnect();
  await pool.end();
}
