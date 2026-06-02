'use strict';
const db = require('./db');

// Write an audit record. `actor` is the req.user object, or null for system jobs.
async function audit(actor, { action, entityType, entityId, edlId, detail }) {
  try {
    await db.query(
      `INSERT INTO audit_log (actor_sub, actor_email, action, entity_type, entity_id, edl_id, detail)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        actor ? actor.sub : 'system',
        actor ? actor.email : null,
        action,
        entityType,
        entityId || null,
        edlId || null,
        detail ? JSON.stringify(detail) : null,
      ]
    );
  } catch (err) {
    // Never let an audit failure break the user action; just log it.
    console.error('audit write failed', err);
  }
}

module.exports = { audit };
