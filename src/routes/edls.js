'use strict';
const express = require('express');
const config = require('../config');
const db = require('../db');
const { validate, parseBulk, formatLine } = require('../validation');
const { audit } = require('../audit');

const router = express.Router();

// async error wrapper
const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function slugify(s) {
  return String(s)
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64);
}

function randomSlug() {
  return require('crypto').randomBytes(12).toString('hex');
}

function publicUrl(slug) {
  // baseUrl already includes any subpath (e.g. https://host/edl), so the feed
  // is served at <baseUrl>/<slug>.txt.
  return `${config.baseUrl}/${slug}.txt`;
}

// nullable timestamp from a datetime-local input
function parseExpires(v) {
  if (!v) return null;
  const d = new Date(v);
  return isNaN(d.getTime()) ? null : d.toISOString();
}

// --- Dashboard: list EDLs ----------------------------------------------------
router.get('/', wrap(async (req, res) => {
  const { rows } = await db.query(
    `SELECT e.*, 
            (SELECT count(*) FROM edl_entries x
              WHERE x.edl_id = e.id AND x.enabled
                AND (x.expires_at IS NULL OR x.expires_at > now())) AS active_count,
            (SELECT max(fetched_at) FROM edl_fetch_log f WHERE f.edl_id = e.id) AS last_fetch
       FROM edls e
      ORDER BY e.name`
  );
  res.render('edls', { edls: rows, publicUrl });
}));

// --- Create EDL --------------------------------------------------------------
router.post('/edls', wrap(async (req, res) => {
  const { name, type, description, random } = req.body;
  if (!name || !['ip', 'domain', 'url'].includes(type)) {
    return res.status(400).send('Name and a valid type are required');
  }
  const slug = random ? randomSlug() : slugify(name) || randomSlug();
  try {
    const { rows } = await db.query(
      `INSERT INTO edls (slug, name, type, description, created_by)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [slug, name, type, description || null, req.user.id]
    );
    await audit(req.user, {
      action: 'create_edl', entityType: 'edl', entityId: rows[0].id,
      edlId: rows[0].id, detail: { after: { name, type, slug } },
    });
    res.redirect(config.path(`/edls/${rows[0].id}`));
  } catch (err) {
    if (err.code === '23505') return res.status(409).send('Slug already exists; pick a different name or use a random slug.');
    throw err;
  }
}));

// --- EDL detail --------------------------------------------------------------
router.get('/edls/:id', wrap(async (req, res) => {
  const edlRes = await db.query(`SELECT * FROM edls WHERE id = $1`, [req.params.id]);
  const edl = edlRes.rows[0];
  if (!edl) return res.status(404).send('EDL not found');

  const entries = (await db.query(
    `SELECT * FROM edl_entries WHERE edl_id = $1 ORDER BY value`, [edl.id]
  )).rows;

  const auditRows = (await db.query(
    `SELECT * FROM audit_log WHERE edl_id = $1 ORDER BY created_at DESC LIMIT 100`, [edl.id]
  )).rows;

  res.render('edl', { edl, entries, audit: auditRows, publicUrl, now: new Date() });
}));

// --- Update EDL metadata -----------------------------------------------------
router.post('/edls/:id', wrap(async (req, res) => {
  const { name, description, enabled } = req.body;
  const before = (await db.query(`SELECT name, description, enabled FROM edls WHERE id=$1`, [req.params.id])).rows[0];
  if (!before) return res.status(404).send('EDL not found');
  await db.query(
    `UPDATE edls SET name=$1, description=$2, enabled=$3, updated_at=now() WHERE id=$4`,
    [name, description || null, enabled === 'on', req.params.id]
  );
  await audit(req.user, {
    action: 'update_edl', entityType: 'edl', entityId: req.params.id, edlId: req.params.id,
    detail: { before, after: { name, description, enabled: enabled === 'on' } },
  });
  res.redirect(config.path(`/edls/${req.params.id}`));
}));

// --- Delete EDL --------------------------------------------------------------
router.post('/edls/:id/delete', wrap(async (req, res) => {
  const before = (await db.query(`SELECT name, slug, type FROM edls WHERE id=$1`, [req.params.id])).rows[0];
  await db.query(`DELETE FROM edls WHERE id=$1`, [req.params.id]);
  await audit(req.user, {
    action: 'delete_edl', entityType: 'edl', entityId: req.params.id, edlId: req.params.id,
    detail: { before },
  });
  res.redirect(config.path('/'));
}));

// --- Add a single entry ------------------------------------------------------
router.post('/edls/:id/entries', wrap(async (req, res) => {
  const edl = (await db.query(`SELECT id, type FROM edls WHERE id=$1`, [req.params.id])).rows[0];
  if (!edl) return res.status(404).send('EDL not found');

  const result = validate(edl.type, req.body.value || '');
  if (!result.ok) return res.status(400).send(`Invalid ${edl.type} entry: ${result.error}`);

  const expires = parseExpires(req.body.expires_at);
  try {
    const { rows } = await db.query(
      `INSERT INTO edl_entries (edl_id, value, comment, expires_at, created_by)
         VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [edl.id, result.value, req.body.comment || null, expires, req.user.id]
    );
    await audit(req.user, {
      action: 'add_entry', entityType: 'entry', entityId: rows[0].id, edlId: edl.id,
      detail: { after: { value: result.value, comment: req.body.comment || null, expires_at: expires } },
    });
  } catch (err) {
    if (err.code === '23505') return res.status(409).send('That value already exists in this EDL.');
    throw err;
  }
  res.redirect(config.path(`/edls/${edl.id}`));
}));

// --- Edit an entry -----------------------------------------------------------
router.post('/entries/:id', wrap(async (req, res) => {
  const entry = (await db.query(
    `SELECT en.*, e.type FROM edl_entries en JOIN edls e ON e.id = en.edl_id WHERE en.id=$1`,
    [req.params.id]
  )).rows[0];
  if (!entry) return res.status(404).send('Entry not found');

  const result = validate(entry.type, req.body.value || '');
  if (!result.ok) return res.status(400).send(`Invalid ${entry.type} entry: ${result.error}`);
  const expires = parseExpires(req.body.expires_at);

  const before = { value: entry.value, comment: entry.comment, expires_at: entry.expires_at };
  await db.query(
    `UPDATE edl_entries SET value=$1, comment=$2, expires_at=$3, updated_at=now() WHERE id=$4`,
    [result.value, req.body.comment || null, expires, entry.id]
  );
  await audit(req.user, {
    action: 'edit_entry', entityType: 'entry', entityId: entry.id, edlId: entry.edl_id,
    detail: { before, after: { value: result.value, comment: req.body.comment || null, expires_at: expires } },
  });
  res.redirect(config.path(`/edls/${entry.edl_id}`));
}));

// --- Toggle enabled ----------------------------------------------------------
router.post('/entries/:id/toggle', wrap(async (req, res) => {
  const entry = (await db.query(`SELECT id, edl_id, enabled, value FROM edl_entries WHERE id=$1`, [req.params.id])).rows[0];
  if (!entry) return res.status(404).send('Entry not found');
  await db.query(`UPDATE edl_entries SET enabled = NOT enabled, updated_at=now() WHERE id=$1`, [entry.id]);
  await audit(req.user, {
    action: 'toggle_entry', entityType: 'entry', entityId: entry.id, edlId: entry.edl_id,
    detail: { value: entry.value, enabled: !entry.enabled },
  });
  res.redirect(config.path(`/edls/${entry.edl_id}`));
}));

// --- Delete an entry ---------------------------------------------------------
router.post('/entries/:id/delete', wrap(async (req, res) => {
  const entry = (await db.query(`SELECT id, edl_id, value FROM edl_entries WHERE id=$1`, [req.params.id])).rows[0];
  if (!entry) return res.status(404).send('Entry not found');
  await db.query(`DELETE FROM edl_entries WHERE id=$1`, [entry.id]);
  await audit(req.user, {
    action: 'delete_entry', entityType: 'entry', entityId: entry.id, edlId: entry.edl_id,
    detail: { before: { value: entry.value } },
  });
  res.redirect(config.path(`/edls/${entry.edl_id}`));
}));

// --- Bulk import -------------------------------------------------------------
router.post('/edls/:id/import', wrap(async (req, res) => {
  const edl = (await db.query(`SELECT id, type FROM edls WHERE id=$1`, [req.params.id])).rows[0];
  if (!edl) return res.status(404).send('EDL not found');

  const { accepted, rejected } = parseBulk(edl.type, req.body.bulk || '');
  let inserted = 0;
  for (const item of accepted) {
    const r = await db.query(
      `INSERT INTO edl_entries (edl_id, value, comment, created_by)
         VALUES ($1, $2, $3, $4)
       ON CONFLICT (edl_id, value) DO NOTHING`,
      [edl.id, item.value, item.comment, req.user.id]
    );
    inserted += r.rowCount;
  }
  await audit(req.user, {
    action: 'import', entityType: 'edl', entityId: edl.id, edlId: edl.id,
    detail: { inserted, rejected: rejected.length, skipped_existing: accepted.length - inserted },
  });
  res.render('import-result', {
    edlId: edl.id, inserted, rejected,
    skippedExisting: accepted.length - inserted,
  });
}));

// --- Export (served format) --------------------------------------------------
router.get('/edls/:id/export', wrap(async (req, res) => {
  const edl = (await db.query(`SELECT * FROM edls WHERE id=$1`, [req.params.id])).rows[0];
  if (!edl) return res.status(404).send('EDL not found');
  const entries = (await db.query(
    `SELECT value, comment FROM edl_entries
      WHERE edl_id=$1 AND enabled AND (expires_at IS NULL OR expires_at > now())
      ORDER BY value`, [edl.id]
  )).rows;
  const body = entries.map((e) => formatLine(edl.type, e)).join('\n') + (entries.length ? '\n' : '');
  res.set('Content-Type', 'text/plain; charset=utf-8');
  res.set('Content-Disposition', `attachment; filename="${edl.slug}.txt"`);
  res.send(body);
}));

module.exports = router;
