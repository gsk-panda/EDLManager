'use strict';
// Import an existing EDL text file into a list, by slug.
//   node scripts/import.js --slug block-malicious-ips --file ./old-list.txt
// Validates and dedups against the list's type; reports rejected lines.
const fs = require('fs');
const db = require('../src/db');
const { parseBulk } = require('../src/validation');
const { audit } = require('../src/audit');

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 ? process.argv[i + 1] : undefined;
}

async function main() {
  const slug = arg('slug');
  const file = arg('file');
  if (!slug || !file) {
    console.error('Usage: node scripts/import.js --slug <edl-slug> --file <path>');
    process.exit(2);
  }

  const edl = (await db.query(`SELECT id, type, name FROM edls WHERE slug=$1`, [slug])).rows[0];
  if (!edl) { console.error(`No EDL with slug "${slug}"`); process.exit(1); }

  const text = fs.readFileSync(file, 'utf8');
  const { accepted, rejected } = parseBulk(edl.type, text);

  let inserted = 0;
  for (const item of accepted) {
    const r = await db.query(
      `INSERT INTO edl_entries (edl_id, value, comment)
         VALUES ($1, $2, $3) ON CONFLICT (edl_id, value) DO NOTHING`,
      [edl.id, item.value, item.comment]
    );
    inserted += r.rowCount;
  }

  await audit(null, {
    action: 'import', entityType: 'edl', entityId: edl.id, edlId: edl.id,
    detail: { source: file, inserted, rejected: rejected.length },
  });

  console.log(`Imported into "${edl.name}" (${edl.type}): ${inserted} added, ` +
              `${accepted.length - inserted} already existed, ${rejected.length} rejected.`);
  if (rejected.length) {
    console.log('Rejected:');
    rejected.forEach((r) => console.log(`  line ${r.line}: ${r.value} (${r.error})`));
  }
  await db.pool.end();
}

main().catch((err) => { console.error(err); process.exit(1); });
