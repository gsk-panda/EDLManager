'use strict';
const crypto = require('crypto');
const { Issuer, generators } = require('openid-client');
const config = require('./config');
const db = require('./db');

let client; // OIDC client, initialized at startup when AUTH_MODE=oidc

async function init() {
  if (config.authMode !== 'oidc') {
    console.log(`Auth mode: ${config.authMode} (OIDC disabled)`);
    return;
  }
  const issuer = await Issuer.discover(config.oidc.issuer);
  client = new issuer.Client({
    client_id: config.oidc.clientId,
    client_secret: config.oidc.clientSecret,
    redirect_uris: [config.oidc.redirectUri],
    response_types: ['code'],
  });
  console.log(`OIDC discovered issuer: ${issuer.metadata.issuer}`);
}

async function upsertUser({ sub, email, name, role }) {
  const { rows } = await db.query(
    `INSERT INTO users (oidc_sub, email, display_name, role, last_login_at)
       VALUES ($1, $2, $3, $4, now())
     ON CONFLICT (oidc_sub) DO UPDATE
       SET email = EXCLUDED.email, display_name = EXCLUDED.display_name, last_login_at = now()
     RETURNING id, oidc_sub AS sub, email, display_name, role`,
    [sub, email || null, name || null, role]
  );
  return rows[0];
}

function setSessionUser(req, user) {
  req.session.user = { id: user.id, sub: user.sub, email: user.email, name: user.display_name, role: user.role };
}

function login(req, res) {
  if (config.authMode !== 'oidc') return res.redirect(config.path('/login'));
  const state = generators.state();
  const nonce = generators.nonce();
  const codeVerifier = generators.codeVerifier();
  const codeChallenge = generators.codeChallenge(codeVerifier);
  req.session.oidc = { state, nonce, codeVerifier };
  res.redirect(client.authorizationUrl({
    scope: config.oidc.scopes, state, nonce,
    code_challenge: codeChallenge, code_challenge_method: 'S256',
  }));
}

async function callback(req, res, next) {
  if (config.authMode !== 'oidc') return res.redirect(config.path('/login'));
  try {
    const saved = req.session.oidc;
    if (!saved) return res.redirect(config.path('/login'));
    const params = client.callbackParams(req);
    const tokenSet = await client.callback(config.oidc.redirectUri, params, {
      state: saved.state, nonce: saved.nonce, code_verifier: saved.codeVerifier,
    });
    const claims = tokenSet.claims();
    const email = (claims.email || '').toLowerCase();
    const role = config.adminEmails.includes(email) ? 'admin' : 'editor';
    const user = await upsertUser({ sub: claims.sub, email, name: claims.name || claims.preferred_username || null, role });
    delete req.session.oidc;
    setSessionUser(req, user);
    res.redirect(config.path('/'));
  } catch (err) { next(err); }
}

function timingSafeEqual(a, b) {
  const ba = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}

async function localLogin(req, res, next) {
  if (config.authMode !== 'local') return res.redirect(config.path('/login'));
  try {
    const { username, password } = req.body;
    const ok = username && password &&
      timingSafeEqual(username, config.local.user) &&
      timingSafeEqual(password, config.local.password);
    if (!ok) return res.status(401).render('login', { error: 'Invalid username or password.' });
    const user = await upsertUser({ sub: `local:${config.local.user}`, email: null, name: config.local.user, role: 'admin' });
    setSessionUser(req, user);
    res.redirect(config.path('/'));
  } catch (err) { next(err); }
}

function logout(req, res) {
  req.session.destroy(() => res.redirect(config.path('/login')));
}

function attachUser(req, res, next) {
  req.user = req.session.user || null;
  res.locals.user = req.user;
  res.locals.authMode = config.authMode;
  res.locals.base = config.basePath; // "" or "/edl", for building links in views
  next();
}

function requireAuth(req, res, next) {
  if (req.user) return next();
  res.redirect(config.path('/login'));
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (req.user && roles.includes(req.user.role)) return next();
    res.status(403).send('Forbidden: insufficient role');
  };
}

function csrf(req, res, next) {
  if (!req.session.csrf) req.session.csrf = crypto.randomBytes(24).toString('hex');
  res.locals.csrf = req.session.csrf;
  if (['POST', 'PUT', 'DELETE'].includes(req.method)) {
    if (!req.body || req.body._csrf !== req.session.csrf) return res.status(403).send('Invalid CSRF token');
  }
  next();
}

module.exports = { init, login, callback, localLogin, logout, attachUser, requireAuth, requireRole, csrf };
