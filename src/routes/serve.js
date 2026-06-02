'use strict';
const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const { formatLine } = require('../validation');

const router = express.Router();

// GET /edl/<slug>.txt  -- public, unauthenticated, text/plain
// Returns enabled, non-expired entries (one per line). Expired entries are
// filtered here so the served list is always correct even if the sweeper
// has not yet run.
router.get('/:slug.txt', async (req, res) => {
  const { slug } = req.params;

  const edlRes = await db.query(
    `SELECT id, name, type, enabled FROM edls WHERE slug = $1`,
    [slug]
  );
  const edl = edlRes.rows[0];

  // A disabled or missing EDL returns 404 -- never 200 with an empty body,
  // which PAN-OS would treat as a valid (empty) list and clear the object.
  if (!edl || !edl.enabled) {
    return res.status(404).type('text/plain').send('# EDL not found\n');
  }

  const entriesRes = await db.query(
    `SELECT value, comment FROM edl_entries
      WHERE edl_id = $1 AND enabled
        AND (expires_at IS NULL OR expires_at > now())
      ORDER BY value`,
    [edl.id]
  );
  const entries = entriesRes.rows;

  // PAN-OS does not support standalone comment/header lines on any list type,
  // so the body is entries only -- one per line, nothing else.
  const body = entries.map((e) => formatLine(edl.type, e)).join('\n') + (entries.length ? '\n' : '');

  // ETag enables cheap conditional polling (firewalls poll frequently).
  const etag = '"' + crypto.createHash('sha1').update(body).digest('hex') + '"';
  res.set('Content-Type', 'text/plain; charset=utf-8');
  res.set('Cache-Control', 'no-cache');
  res.set('ETag', etag);

  const notModified = req.headers['if-none-match'] === etag;
  const status = notModified ? 304 : 200;

  // Record the fetch (fire-and-forget; don't block the response).
  db.query(
    `INSERT INTO edl_fetch_log (edl_id, source_ip, user_agent, entry_count, status)
       VALUES ($1, $2, $3, $4, $5)`,
    [edl.id, req.ip, req.headers['user-agent'] || null, entries.length, status]
  ).catch((err) => console.error('fetch log failed', err));

  if (notModified) return res.status(304).end();
  return res.status(200).send(body);
});

module.exports = router;
