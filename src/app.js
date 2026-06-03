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

  // Everything is attached to `root`, then mounted at the base path so the app
  // can live at the URL root or under a subdirectory (e.g. /edl) transparently.
  const root = express.Router();

  // Public, unauthenticated EDL feed: /<slug>.txt (i.e. <base>/<slug>.txt).
  // Mounted BEFORE session/auth so the firewall fetch path stays stateless.
  root.use('/', serveRouter);

  // ---- Management plane ----
  root.use(express.urlencoded({ extended: false }));
  root.use(session({
    store: new PgSession({ pool: db.pool, tableName: 'session' }),
    secret: config.sessionSecret,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: config.trustProxy,           // HTTPS at the proxy in prod
      path: config.path(),                 // scope cookie to the app's subpath
      maxAge: 1000 * 60 * 60 * 8,
    },
  }));
  root.use(auth.attachUser);
  root.use(auth.csrf);

  root.get('/login', (req, res) => res.render('login', { error: null }));
  root.post('/login', auth.localLogin);
  root.get('/login/start', auth.login);
  root.get('/callback', auth.callback);
  root.post('/logout', auth.requireAuth, auth.logout);

  root.use(auth.requireAuth, edlsRouter);

  root.use((req, res) => res.status(404).send('Not found'));
  // eslint-disable-next-line no-unused-vars
  root.use((err, req, res, next) => { console.error(err); res.status(500).send('Internal server error'); });

  app.use(config.path(), root); // mount at "/" or "/edl"
  return app;
}

async function main() {
  const app = await createApp();
  app.listen(config.port, config.bindAddr, () => {
    console.log(`EDL Manager on ${config.baseUrl} (bind ${config.bindAddr}:${config.port}, base "${config.basePath || '/'}", auth ${config.authMode})`);
  });
}

if (require.main === module) {
  main().catch((err) => { console.error('Fatal startup error:', err); process.exit(1); });
}

module.exports = { createApp };
