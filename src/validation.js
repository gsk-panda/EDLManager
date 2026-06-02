'use strict';
// Validation + normalization for the three PAN-OS EDL types, per the official
// PAN-OS 11.1 "Formatting Guidelines for an External Dynamic List".
//
//   IP:     single address, CIDR (addr/mask), or range (start-end). One per line.
//           Comments allowed ON THE SAME LINE after a space: "IP <space> comment".
//   Domain: token separators . / ? & = ; +  ; a wildcard '*' must be the ONLY
//           character in its token and may only be PREPENDED (*.example.com).
//           A leading '^' means exact match (^example.com). Max 255 chars.
//           Protocol prefix (http(s)://), URLs, and IPs are not allowed.
//   URL:    follows the URL Category Exception syntax -- same separators, and a
//           '*' must be a standalone token between separators. Paths allowed.
//
// PAN-OS silently skips malformed lines (and only logs them), so we validate up
// front and surface rejections instead of letting the firewall drop them.

const ipaddr = require('ipaddr.js');

// ---- IP: single address, CIDR, or range "start-end" -------------------------
function validateIp(raw) {
  const s = raw.trim();
  if (!s) return { ok: false, error: 'empty' };

  if (s.includes('-')) {
    const parts = s.split('-').map((x) => x.trim());
    if (parts.length !== 2 || !ipaddr.isValid(parts[0]) || !ipaddr.isValid(parts[1])) {
      return { ok: false, error: 'invalid IP range (expected start-end)' };
    }
    const a = ipaddr.parse(parts[0]);
    const b = ipaddr.parse(parts[1]);
    if (a.kind() !== b.kind()) return { ok: false, error: 'range mixes IPv4 and IPv6' };
    return { ok: true, value: `${a.toString()}-${b.toString()}` };
  }

  if (s.includes('/')) {
    try {
      const [addr, prefix] = ipaddr.parseCIDR(s);
      return { ok: true, value: `${addr.toString()}/${prefix}` };
    } catch {
      return { ok: false, error: 'invalid CIDR (expected address/mask)' };
    }
  }

  if (ipaddr.isValid(s)) return { ok: true, value: ipaddr.parse(s).toString() };
  return { ok: false, error: 'invalid IP address' };
}

const LABEL_RE = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

// ---- Domain -----------------------------------------------------------------
function validateDomain(raw) {
  let s = raw.trim().toLowerCase();
  if (!s) return { ok: false, error: 'empty' };
  if (s.length > 255) return { ok: false, error: 'domain exceeds 255 characters' };
  if (/^https?:\/\//.test(s)) return { ok: false, error: 'remove the http(s):// prefix' };
  if (/[\s]/.test(s)) return { ok: false, error: 'domain contains whitespace' };
  // For a domain entry only '.' should appear as a separator; the others imply a URL/path.
  if (/[/?&=;+]/.test(s)) return { ok: false, error: 'looks like a URL, not a domain (use a URL list)' };

  let caret = false;
  if (s[0] === '^') { caret = true; s = s.slice(1); }

  const tokens = s.split('.');
  if (tokens.length < 2) return { ok: false, error: 'domain must have at least two labels' };

  let seenLabel = false;
  for (const t of tokens) {
    if (t === '*') {
      if (caret) return { ok: false, error: 'cannot combine ^ (exact) with * (wildcard)' };
      if (seenLabel) return { ok: false, error: 'wildcard (*) can only be prepended' };
      continue;
    }
    if (t.includes('*')) return { ok: false, error: 'wildcard (*) must be its own token' };
    if (!LABEL_RE.test(t)) return { ok: false, error: `invalid domain label "${t}"` };
    seenLabel = true;
  }
  if (!seenLabel) return { ok: false, error: 'domain has no non-wildcard label' };

  return { ok: true, value: (caret ? '^' : '') + tokens.join('.') };
}

// ---- URL --------------------------------------------------------------------
const URL_SEP_RE = /[./?&=;+]/;
function validateUrl(raw) {
  let s = raw.trim();
  if (!s) return { ok: false, error: 'empty' };
  s = s.replace(/^https?:\/\//i, ''); // PAN-OS URL lists omit the scheme
  if (!s) return { ok: false, error: 'empty after removing scheme' };
  if (/\s/.test(s)) return { ok: false, error: 'URL contains whitespace' };
  if (s.length > 1000) return { ok: false, error: 'URL is too long' };
  if (!/^[\x21-\x7e]+$/.test(s)) return { ok: false, error: 'URL contains unsupported characters' };

  for (const tok of s.split(URL_SEP_RE)) {
    if (tok.includes('*') && tok !== '*') {
      return { ok: false, error: 'wildcard (*) must be a standalone token between separators' };
    }
  }
  // Lowercase the host portion only; preserve path case.
  const slash = s.indexOf('/');
  s = slash === -1 ? s.toLowerCase() : s.slice(0, slash).toLowerCase() + s.slice(slash);
  return { ok: true, value: s };
}

const validators = { ip: validateIp, domain: validateDomain, url: validateUrl };

function validate(type, raw) {
  const fn = validators[type];
  if (!fn) return { ok: false, error: `unknown EDL type: ${type}` };
  return fn(raw);
}

// Render a stored entry as the firewall expects to receive it. Per PAN-OS,
// inline comments are only valid on IP lists (same line, after a space);
// domain/URL lists must contain the bare entry only.
function formatLine(type, entry) {
  if (type === 'ip' && entry.comment) return `${entry.value} # ${entry.comment}`;
  return entry.value;
}

// Parse pasted/imported text. Blank lines and full-line '#' comments are
// ignored. An inline '# comment' is split off. For IP lists we also accept the
// native "IP <space> comment" form so existing PAN-OS lists import cleanly.
function parseBulk(type, text) {
  const accepted = [];
  const rejected = [];
  const seen = new Set();

  String(text).split(/\r?\n/).forEach((line, i) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) return;

    let base = trimmed;
    let comment = null;
    const hash = base.indexOf('#');
    if (hash !== -1) { comment = base.slice(hash + 1).trim() || null; base = base.slice(0, hash).trim(); }

    // IP lists use "IP <space> comment"; split the first whitespace off as comment.
    if (type === 'ip') {
      const m = base.match(/^(\S+)\s+(.*)$/);
      if (m) { base = m[1]; if (!comment) comment = m[2].trim() || null; }
    }

    const res = validate(type, base);
    if (!res.ok) { rejected.push({ line: i + 1, value: base, error: res.error }); return; }
    if (seen.has(res.value)) { rejected.push({ line: i + 1, value: res.value, error: 'duplicate' }); return; }
    seen.add(res.value);
    accepted.push({ value: res.value, comment });
  });

  return { accepted, rejected };
}

module.exports = { validate, parseBulk, formatLine };
