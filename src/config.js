'use strict';
require('dotenv').config();

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

// 'oidc' (production) or 'local' (testing: username/password from env).
const authMode = (process.env.AUTH_MODE || 'oidc').toLowerCase();

module.exports = {
  authMode,
  baseUrl: process.env.BASE_URL || `http://localhost:${process.env.PORT || 3000}`,
  port: parseInt(process.env.PORT || '3000', 10),
  sessionSecret: required('SESSION_SECRET'),
  databaseUrl: required('DATABASE_URL'),
  trustProxy: process.env.TRUST_PROXY === '1',

  // OIDC config is only required when AUTH_MODE=oidc.
  oidc: authMode === 'oidc' ? {
    issuer: required('OIDC_ISSUER'),
    clientId: required('OIDC_CLIENT_ID'),
    clientSecret: required('OIDC_CLIENT_SECRET'),
    redirectUri: required('OIDC_REDIRECT_URI'),
    scopes: process.env.OIDC_SCOPES || 'openid profile email',
  } : null,

  // Local admin is only required when AUTH_MODE=local.
  local: {
    user: authMode === 'local' ? required('LOCAL_ADMIN_USER') : process.env.LOCAL_ADMIN_USER,
    password: authMode === 'local' ? required('LOCAL_ADMIN_PASSWORD') : process.env.LOCAL_ADMIN_PASSWORD,
  },

  adminEmails: (process.env.ADMIN_EMAILS || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean),
};
