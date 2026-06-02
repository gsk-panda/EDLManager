'use strict';
const path = require('path');
const express = require('express');
const session = require('express-session');
const PgSession = require('connect-pg-simple')(session);

const config = require('./config');
const db = require('./db');
const auth = require('./auth');
const serveRouter = require('./routes/serve');
const edlsRouter = require('./routes/edls');

async function createApp() {
  await auth.init(); // OIDC discovery (no-op in local mode)

  const app = express();
  if (config.trustProxy) app.set('trust proxy', 1);

  app.set('view engine', 'ejs');
  app.set('views', path.join(__dirname, '..', 'views'));

  // Public, unauthenticated EDL feed -- mounted BEFORE session/auth so the
  // firewall fetch path stays dead simple and stateless.
  app.use('/edl', serveRouter);

  // ---- Management plane ----
  app.use(express.urlencoded({ extended: false }));
  app.use(session({
    store: new PgSession({ pool: db.pool, tableName: 'session' }),
    secret: config.sessionSecret,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: config.trustProxy, // requires HTTPS at the proxy in prod
      maxAge: 1000 * 60 * 60 * 8,
    },
  }));
  app.use(auth.attachUser);
  app.use(auth.csrf); // issues a token to every page; validates every POST

  // Auth routes
  app.get('/login', (req, res) => res.render('login', { error: null }));
  app.post('/login', auth.localLogin);      // local mode
  app.get('/login/start', auth.login);       // oidc mode
  app.get('/callback', auth.callback);       // oidc mode
  app.post('/logout', auth.requireAuth, auth.logout);

  // Protected management routes
  app.use(auth.requireAuth, edlsRouter);

  // 404 + error handlers
  app.use((req, res) => res.status(404).send('Not found'));
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).send('Internal server error');
  });

  return app;
}

async function main() {
  const app = await createApp();
  app.listen(config.port, () => {
    console.log(`EDL Manager listening on ${config.baseUrl} (port ${config.port}) [auth: ${config.authMode}]`);
  });
}

if (require.main === module) {
  main().catch((err) => {
    console.error('Fatal startup error:', err);
    process.exit(1);
  });
}

module.exports = { createApp };
