-- Rookies notifications database (Cloudflare D1).
-- Apply with: npm run db:init

-- One row per app install.
CREATE TABLE IF NOT EXISTS devices (
  install_id    TEXT PRIMARY KEY,
  fcm_token     TEXT,
  platform      TEXT,
  enabled       INTEGER NOT NULL DEFAULT 1,
  customer_id   TEXT,            -- gid://shopify/Customer/... when signed in
  email         TEXT,
  phone10       TEXT,            -- last 10 digits, to match order phones
  first_name    TEXT,
  cart_id       TEXT,
  last_order_at INTEGER,
  created_at    INTEGER NOT NULL,
  last_seen     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS devices_customer ON devices (customer_id);
CREATE INDEX IF NOT EXISTS devices_email ON devices (email);
CREATE INDEX IF NOT EXISTS devices_phone ON devices (phone10);

-- Every planned message. "flow" is the flow name, optionally with a key
-- ("restock:<productId>", "shipped:<orderId>") so the same flow can run for
-- different things at once.
CREATE TABLE IF NOT EXISTS jobs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  install_id TEXT NOT NULL,
  flow       TEXT NOT NULL,
  step       INTEGER NOT NULL DEFAULT 0,
  promo      INTEGER NOT NULL DEFAULT 0,  -- counts toward the daily limit
  due_at     INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  payload    TEXT,
  status     TEXT NOT NULL DEFAULT 'pending', -- pending | sent | cancelled | skipped | failed
  attempts   INTEGER NOT NULL DEFAULT 0,
  sent_at    INTEGER
);
CREATE INDEX IF NOT EXISTS jobs_due ON jobs (status, due_at);
CREATE INDEX IF NOT EXISTS jobs_device ON jobs (install_id, flow, status);

-- Wishlisted products per install, for restock and price-drop alerts.
CREATE TABLE IF NOT EXISTS wishlist (
  install_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  handle     TEXT,
  title      TEXT,
  image      TEXT,
  added_at   INTEGER NOT NULL,
  PRIMARY KEY (install_id, product_id)
);
CREATE INDEX IF NOT EXISTS wishlist_product ON wishlist (product_id);

-- Last known stock and price of each wishlisted product.
CREATE TABLE IF NOT EXISTS products (
  product_id TEXT PRIMARY KEY,
  available  INTEGER NOT NULL,
  price      REAL NOT NULL,
  checked_at INTEGER NOT NULL
);

-- Orders seen through webhooks, so shipping updates find the right people.
CREATE TABLE IF NOT EXISTS orders (
  order_id    TEXT PRIMARY KEY,   -- numeric Shopify order id
  order_name  TEXT,
  customer_id TEXT,
  email       TEXT,
  phone10     TEXT,
  first_name  TEXT,
  created_at  INTEGER NOT NULL
);
