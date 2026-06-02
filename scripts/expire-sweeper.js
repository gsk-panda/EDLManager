'use strict';
// Deletes entries whose expires_at has passed and writes an audit record for
// each. serve.js already filters expired entries at request time, so this is
// for cleanliness and audit history. Run from cron, e.g. every 5 minutes:
//   */5 * * * * cd /opt/edl-manager && node scripts/expire-sweeper.js >> /var/log/edl-sweep.log 2>&1
const db = require('../src/db');
const { audit } = require('../src/audit');

async function main() {
  const { rows } = await db.query(
    `DELETE FROM edl_entries
      WHERE expires_at IS NOT NULL AND expires_at <= now()
      RETURNING id, edl_id, value, comment, expires_at`
  );
  for (const e of rows) {
    await audit(null, {
      action: 'expire_entry', entityType: 'entry', entityId: e.id, edlId: e.edl_id,
      detail: { before: { value: e.value, comment: e.comment, expires_at: e.expires_at } },
    });
  }
  console.log(`[${new Date().toISOString()}] expired and removed ${rows.length} entries`);
  await db.pool.end();
}

main().catch((err) => { console.error(err); process.exit(1); });
