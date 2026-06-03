'use strict';
require('dotenv').config();

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

const authMode = (process.env.AUTH_MODE || 'oidc').toLowerCase();
const baseUrl = process.env.BASE_URL || `http://localhost:${process.env.PORT || 3000}`;

// Derive the mount path (subdirectory) from BASE_URL. When the app is served at
// a subpath behind a reverse proxy (e.g. BASE_URL=https://host/edl), basePath is
// "/edl" and every route, link, redirect, and the session cookie are scoped to
// it. When BASE_URL has no path (e.g. http://localhost:3000), basePath is "" and
// the app runs at the URL root exactly as before.
let basePath = '';
try { basePath = new URL(baseUrl).pathname.replace(/\/+$/, ''); } catch { basePath = ''; }

module.exports = {
  authMode,
  baseUrl: baseUrl.replace(/\/+$/, ''),
  basePath,
  // Prefix a route with the base path; "" -> "/" for the root case.
  path: (p = '') => (basePath + p) || '/',
  port: parseInt(process.env.PORT || '3000', 10),
  bindAddr: process.env.BIND_ADDR || '0.0.0.0',
  sessionSecret: required('SESSION_SECRET'),
  databaseUrl: required('DATABASE_URL'),
  trustProxy: process.env.TRUST_PROXY === '1',

  oidc: authMode === 'oidc' ? {
    issuer: required('OIDC_ISSUER'),
    clientId: required('OIDC_CLIENT_ID'),
    clientSecret: required('OIDC_CLIENT_SECRET'),
    redirectUri: required('OIDC_REDIRECT_URI'),
    scopes: process.env.OIDC_SCOPES || 'openid profile email',
  } : null,

  local: {
    user: authMode === 'local' ? required('LOCAL_ADMIN_USER') : process.env.LOCAL_ADMIN_USER,
    password: authMode === 'local' ? required('LOCAL_ADMIN_PASSWORD') : process.env.LOCAL_ADMIN_PASSWORD,
  },

  adminEmails: (process.env.ADMIN_EMAILS || '')
    .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean),
};
