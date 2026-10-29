// Rookies push notifications: a Cloudflare Worker + D1 database.
//
// The app tells this worker what each install does (cart changes, checkout,
// products viewed, wishlist); Shopify tells it about orders and shipping
// through webhooks. The worker plans messages from the rules in flows.js and
// a cron sends whatever is due through Firebase Cloud Messaging.
//
//   POST /register   {installId, fcmToken, platform, enabled, customerAccessToken?}
//   POST /event      {installId, type, data}
//       cart_updated       {cartId, count}
//       checkout_started   {}
//       checkout_completed {}
//       product_viewed     {productId, handle, title, image}
//       wishlist_added     {productId, handle, title, image}
//       wishlist_removed   {productId}
//       signed_out         {}
//       app_error          {where, error}   (only logged, for debugging)
//   POST /webhooks/shopify            Shopify order webhooks (HMAC-checked)
//   GET  /admin                       page for sending notifications by hand
//   POST /admin/broadcast             {title, body, link?, image?, audience?, sendAt?}
//   GET  /admin/campaigns             recent broadcasts and how many went out
//   POST /admin/cancel                {campaign} cancels its messages still waiting
//   POST /admin/setup-webhooks        subscribes the Shopify order webhooks
//   GET  /admin/stats
//   GET  /health
//
// /admin/* needs "Authorization: Bearer <ADMIN_KEY>".
//
// Cron: every minute sends due messages (quiet hours and the daily limit
// applied here); every hour checks wishlisted products for restocks and
// price drops.

import { FLOWS, flowDef, DAY } from './flows.js';
import { sendPush } from './fcm.js';
import { ADMIN_PAGE } from './admin-page.js';
import {
  cartSummary, customerForToken, isValidWebhook, productStates, registerWebhooks,
} from './shopify.js';

const IST_OFFSET = 330 * 60 * 1000;
// Workers on the free plan may make 50 outgoing requests per run; keep a
// margin for the Google token and Shopify cart checks.
const SENDS_PER_RUN = 40;
const ID_RE = /^[A-Za-z0-9-]{8,64}$/;

export default {
  fetch: (request, env) => handleRequest(request, env),
  async scheduled(event, env, ctx) {
    if (event.cron === '0 * * * *') ctx.waitUntil(checkWishlistProducts(env));
    else ctx.waitUntil(sendDueMessages(env));
  },
};

async function handleRequest(request, env) {
  const path = new URL(request.url).pathname.replace(/\/+$/, '');
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS_HEADERS });

  try {
    if (request.method === 'GET' && path === '/health') return json({ ok: true });
    if (request.method === 'GET' && path === '/admin') {
      return new Response(ADMIN_PAGE, { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
    }
    if (path === '/webhooks/shopify' && request.method === 'POST') return await shopifyWebhook(request, env);
    if (path.startsWith('/admin/')) {
      if (!env.ADMIN_KEY || request.headers.get('Authorization') !== `Bearer ${env.ADMIN_KEY}`) {
        return json({ error: 'Unauthorized' }, 401);
      }
      if (path === '/admin/stats' && request.method === 'GET') return await stats(env);
      if (path === '/admin/broadcast' && request.method === 'POST') return await broadcast(await request.json(), env);
      if (path === '/admin/campaigns' && request.method === 'GET') return await campaigns(env);
      if (path === '/admin/cancel' && request.method === 'POST') return await cancelCampaign(await request.json(), env);
      if (path === '/admin/setup-webhooks' && request.method === 'POST') {
        const uri = `${new URL(request.url).origin}/webhooks/shopify`;
        return json(await registerWebhooks(uri, env));
      }
      return json({ error: 'Not found' }, 404);
    }
    if (request.method !== 'POST') return json({ error: 'Not found' }, 404);

    const body = await request.json().catch(() => null);
    if (!body || !ID_RE.test(String(body.installId || ''))) return json({ error: 'Invalid request.' }, 400);
    if (path === '/register') return await register(body, env);
    if (path === '/event') return await appEvent(body, env);
    return json({ error: 'Not found' }, 404);
  } catch (e) {
    console.error(path, e);
    return json({ error: 'Something went wrong.' }, 500);
  }
}

// ---------------------------------------------------------------------------
// App endpoints

async function register(body, env) {
  const now = Date.now();
  const id = body.installId;
  const existing = await env.DB.prepare('SELECT fcm_token FROM devices WHERE install_id = ?')
    .bind(id).first();

  await touchDevice(env, id, now);
  await env.DB.prepare(
    'UPDATE devices SET fcm_token = ?, platform = ?, enabled = ? WHERE install_id = ?',
  ).bind(
    typeof body.fcmToken === 'string' && body.fcmToken ? body.fcmToken : null,
    body.platform === 'ios' ? 'ios' : 'android',
    body.enabled === false ? 0 : 1,
    id,
  ).run();

  if (typeof body.customerAccessToken === 'string' && body.customerAccessToken) {
    const customer = await customerForToken(body.customerAccessToken, env).catch((e) => {
      console.warn('customer lookup failed:', e.message);
      return null;
    });
    if (customer) {
      await env.DB.prepare(
        'UPDATE devices SET customer_id = ?, email = ?, phone10 = ?, first_name = ? WHERE install_id = ?',
      ).bind(customer.id, lower(customer.email), phone10(customer.phone), customer.firstName || null, id).run();
    }
  }

  // First time this install can receive pushes: start the welcome series,
  // unless it ever had one.
  if (!existing?.fcm_token && body.fcmToken) {
    const had = await env.DB.prepare('SELECT 1 FROM jobs WHERE install_id = ? AND flow = ? LIMIT 1')
      .bind(id, 'welcome').first();
    if (!had) await startFlow(env, id, 'welcome', {}, now);
  }
  return json({ ok: true });
}

async function appEvent(body, env) {
  const now = Date.now();
  const id = body.installId;
  const data = body.data && typeof body.data === 'object' ? body.data : {};
  await touchDevice(env, id, now);

  switch (body.type) {
    case 'cart_updated': {
      const count = Number(data.count) || 0;
      await env.DB.prepare('UPDATE devices SET cart_id = ? WHERE install_id = ?')
        .bind(typeof data.cartId === 'string' ? data.cartId : null, id).run();
      await cancelFlows(env, id, ['browse']);
      if (count > 0) await startFlow(env, id, 'cart', {}, now);
      else await cancelFlows(env, id, ['cart']);
      break;
    }
    case 'checkout_started':
      await cancelFlows(env, id, ['cart', 'browse']);
      await startFlow(env, id, 'checkout', {}, now);
      break;
    case 'checkout_completed':
      await cancelFlows(env, id, ['cart', 'checkout', 'browse']);
      break;
    case 'product_viewed': {
      // Only the latest viewed product, and at most one of these a day.
      const recent = await env.DB.prepare(
        "SELECT 1 FROM jobs WHERE install_id = ? AND flow = 'browse' AND status = 'sent' AND sent_at > ? LIMIT 1",
      ).bind(id, now - DAY).first();
      if (!recent) await startFlow(env, id, 'browse', productFields(data), now);
      break;
    }
    case 'wishlist_added':
      if (typeof data.productId !== 'string') break;
      await env.DB.prepare(
        `INSERT INTO wishlist (install_id, product_id, handle, title, image, added_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT (install_id, product_id) DO UPDATE SET handle = excluded.handle,
           title = excluded.title, image = excluded.image`,
      ).bind(id, data.productId, ...Object.values(productFields(data)), now).run();
      break;
    case 'wishlist_removed':
      await env.DB.prepare('DELETE FROM wishlist WHERE install_id = ? AND product_id = ?')
        .bind(id, String(data.productId || '')).run();
      break;
    case 'signed_out':
      await env.DB.prepare(
        'UPDATE devices SET customer_id = NULL, email = NULL, phone10 = NULL, first_name = NULL WHERE install_id = ?',
      ).bind(id).run();
      break;
    case 'app_error':
      console.warn(`app error on ${id}: ${str(data.where)}: ${str(data.error)}`);
      break;
    default:
      return json({ error: 'Unknown event.' }, 400);
  }
  return json({ ok: true });
}

function productFields(data) {
  return {
    handle: str(data.handle),
    title: str(data.title),
    image: str(data.image),
  };
}

async function touchDevice(env, id, now) {
  await env.DB.prepare(
    `INSERT INTO devices (install_id, created_at, last_seen) VALUES (?, ?, ?)
     ON CONFLICT (install_id) DO UPDATE SET last_seen = excluded.last_seen`,
  ).bind(id, now, now).run();
}

// ---------------------------------------------------------------------------
// Planning

/// (Re)starts [flow] for one install: drops its pending steps and plans them
/// all again from [now].
async function startFlow(env, installId, flow, payload, now) {
  const def = flowDef(flow);
  const promo = def.capped || flow.startsWith('campaign') ? 1 : 0;
  const statements = [
    env.DB.prepare("UPDATE jobs SET status = 'cancelled' WHERE install_id = ? AND flow = ? AND status = 'pending'")
      .bind(installId, flow),
    ...def.steps.map((step, i) => env.DB.prepare(
      'INSERT INTO jobs (install_id, flow, step, promo, due_at, created_at, payload) VALUES (?, ?, ?, ?, ?, ?, ?)',
    ).bind(installId, flow, i, promo, now + step.after, now, JSON.stringify(payload))),
  ];
  await env.DB.batch(statements);
}

async function cancelFlows(env, installId, flows) {
  await env.DB.prepare(
    `UPDATE jobs SET status = 'cancelled' WHERE install_id = ? AND status = 'pending'
     AND flow IN (${flows.map(() => '?').join(',')})`,
  ).bind(installId, ...flows).run();
}

/// True when this install already got (or is about to get) [flow].
async function hasFlow(env, installId, flow, sinceMs = 0) {
  return !!(await env.DB.prepare(
    "SELECT 1 FROM jobs WHERE install_id = ? AND flow = ? AND status IN ('pending', 'sent') AND created_at >= ? LIMIT 1",
  ).bind(installId, flow, sinceMs).first());
}

// ---------------------------------------------------------------------------
// Sending (every minute)

async function sendDueMessages(env) {
  const now = Date.now();
  const { results } = await env.DB.prepare(
    `SELECT j.*, d.fcm_token, d.enabled, d.first_name, d.cart_id, d.last_order_at
     FROM jobs j JOIN devices d ON d.install_id = j.install_id
     WHERE j.status = 'pending' AND j.due_at <= ?
     ORDER BY j.due_at LIMIT ?`,
  ).bind(now, SENDS_PER_RUN * 2).all();

  let budget = SENDS_PER_RUN;
  for (const job of results) {
    if (budget <= 0) break;
    try {
      budget -= await sendJob(env, job, now);
    } catch (e) {
      console.error(`job ${job.id} (${job.flow}):`, e);
      await retryLater(env, job, now);
    }
  }
}

/// Handles one due job. Returns how many outgoing requests it used.
async function sendJob(env, job, now) {
  const def = flowDef(job.flow);
  const step = def?.steps[job.step];
  if (!step || !job.fcm_token || !job.enabled) return setStatus(env, job, 'skipped', 0);
  if (def.stopIfOrdered && job.last_order_at && job.last_order_at > job.created_at) {
    return setStatus(env, job, 'cancelled', 0);
  }

  if (def.quiet) {
    const later = afterQuietHours(env, now);
    if (later) return moveTo(env, job, later);
  }
  if (def.capped && await promosSentToday(env, job.install_id, now) >= Number(env.MAX_PROMOS_PER_DAY || 2)) {
    return moveTo(env, job, nextDayAt(now, 11 * 60));
  }

  const ctx = {
    ...JSON.parse(job.payload || '{}'),
    name: job.first_name || '',
    welcomeCoupon: env.WELCOME_COUPON || '',
    cartCoupon: env.CART_COUPON || '',
    winbackCoupon: env.WINBACK_COUPON || '',
  };
  let used = 0;
  if (def.needsCart) {
    const cart = job.cart_id ? await cartSummary(job.cart_id, env) : null;
    used++;
    if (!cart || cart.count === 0) return setStatus(env, job, 'cancelled', used);
    ctx.count = cart.count;
    ctx.itemTitle = cart.firstTitle;
  }

  const result = await sendPush(env, job.fcm_token, step.msg(ctx), { transactional: !def.quiet });
  used++;
  if (result === 'sent') {
    await env.DB.prepare("UPDATE jobs SET status = 'sent', sent_at = ? WHERE id = ?").bind(now, job.id).run();
  } else if (result === 'unregistered') {
    await env.DB.prepare('UPDATE devices SET fcm_token = NULL WHERE install_id = ?').bind(job.install_id).run();
    await setStatus(env, job, 'skipped', 0);
  } else {
    await retryLater(env, job, now);
  }
  return used;
}

async function setStatus(env, job, status, used) {
  await env.DB.prepare('UPDATE jobs SET status = ? WHERE id = ?').bind(status, job.id).run();
  return used;
}

async function moveTo(env, job, dueAt) {
  await env.DB.prepare('UPDATE jobs SET due_at = ? WHERE id = ?').bind(dueAt, job.id).run();
  return 0;
}

async function retryLater(env, job, now) {
  const attempts = job.attempts + 1;
  await env.DB.prepare('UPDATE jobs SET attempts = ?, due_at = ?, status = ? WHERE id = ?')
    .bind(attempts, now + attempts * 10 * 60 * 1000, attempts >= 3 ? 'failed' : 'pending', job.id).run();
}

async function promosSentToday(env, installId, now) {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM jobs WHERE install_id = ? AND promo = 1 AND status = 'sent' AND sent_at >= ?",
  ).bind(installId, istDayStart(now)).first();
  return row.n;
}

// ---------------------------------------------------------------------------
// Time (India Standard Time, no daylight saving)

const istMinutes = (ts) => Math.floor(((ts + IST_OFFSET) % DAY) / 60000);
const istDayStart = (ts) => ts - ((ts + IST_OFFSET) % DAY);
const hhmm = (text, fallback) => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(text || '');
  return m ? Number(m[1]) * 60 + Number(m[2]) : fallback;
};

/// When [now] is inside quiet hours, the time they end (spread over half an
/// hour so the morning sends don't all land at once); otherwise null.
function afterQuietHours(env, now) {
  const start = hhmm(env.QUIET_START, 22 * 60 + 30);
  const end = hhmm(env.QUIET_END, 9 * 60);
  const m = istMinutes(now);
  const quiet = start > end ? (m >= start || m < end) : (m >= start && m < end);
  if (!quiet) return null;
  const endToday = istDayStart(now) + end * 60000;
  const endAt = m < end ? endToday : endToday + DAY;
  return endAt + Math.floor(Math.random() * 30) * 60000;
}

function nextDayAt(now, minutes) {
  return istDayStart(now) + DAY + minutes * 60000 + Math.floor(Math.random() * 60) * 60000;
}

// ---------------------------------------------------------------------------
// Shopify webhooks

async function shopifyWebhook(request, env) {
  const raw = await request.text();
  if (!(await isValidWebhook(raw, request.headers.get('X-Shopify-Hmac-Sha256'), env))) {
    return json({ error: 'Invalid signature' }, 401);
  }
  const topic = request.headers.get('X-Shopify-Topic');
  const payload = JSON.parse(raw);
  const now = Date.now();

  if (topic === 'orders/create') {
    const order = {
      id: String(payload.id),
      name: payload.name || '',
      customerId: payload.customer?.admin_graphql_api_id || null,
      email: lower(payload.email || payload.customer?.email),
      phone: phone10(payload.phone || payload.customer?.phone || payload.shipping_address?.phone),
      firstName: payload.customer?.first_name || payload.shipping_address?.first_name || null,
    };
    await env.DB.prepare(
      `INSERT OR IGNORE INTO orders (order_id, order_name, customer_id, email, phone10, first_name, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).bind(order.id, order.name, order.customerId, order.email, order.phone, order.firstName, now).run();

    for (const installId of await devicesFor(env, order)) {
      await env.DB.prepare('UPDATE devices SET last_order_at = ? WHERE install_id = ?').bind(now, installId).run();
      await cancelFlows(env, installId, ['cart', 'checkout', 'browse', 'welcome']);
      if (!(await hasFlow(env, installId, `order_confirmed:${order.id}`))) {
        await startFlow(env, installId, `order_confirmed:${order.id}`, { orderName: order.name }, now);
      }
      await startFlow(env, installId, 'repeat', {}, now);
    }
  } else if (topic === 'orders/cancelled') {
    const order = await orderRow(env, payload.id);
    if (order) {
      for (const installId of await devicesFor(env, order)) {
        await cancelFlows(env, installId, [`review:${order.id}`]);
      }
    }
  } else if (topic === 'fulfillments/create') {
    await orderUpdate(env, payload.order_id, 'shipped', now);
  } else if (topic === 'fulfillment_events/create') {
    if (payload.status === 'out_for_delivery') await orderUpdate(env, payload.order_id, 'out_for_delivery', now);
    if (payload.status === 'delivered') await orderUpdate(env, payload.order_id, 'delivered', now);
  }
  // Shopify retries anything that isn't 2xx, so unknown topics are accepted too.
  return json({ ok: true });
}

async function orderUpdate(env, orderId, flow, now) {
  const order = await orderRow(env, orderId);
  if (!order) return; // placed before notifications were set up
  for (const installId of await devicesFor(env, order)) {
    // Shopify can deliver the same webhook twice; send each update once.
    if (await hasFlow(env, installId, `${flow}:${order.id}`)) continue;
    await startFlow(env, installId, `${flow}:${order.id}`, { orderName: order.name }, now);
    if (flow === 'delivered') await startFlow(env, installId, `review:${order.id}`, { orderName: order.name }, now);
  }
}

async function orderRow(env, orderId) {
  const row = await env.DB.prepare('SELECT * FROM orders WHERE order_id = ?').bind(String(orderId)).first();
  return row && {
    id: row.order_id, name: row.order_name, customerId: row.customer_id,
    email: row.email, phone: row.phone10,
  };
}

/// Installs signed in as the order's customer (matched by Shopify id, email
/// or phone, since GoKwik may create the order under a different record).
async function devicesFor(env, order) {
  const { results } = await env.DB.prepare(
    `SELECT install_id FROM devices
     WHERE (customer_id IS NOT NULL AND customer_id = ?)
        OR (email IS NOT NULL AND email = ?)
        OR (phone10 IS NOT NULL AND phone10 = ?)`,
  ).bind(order.customerId || '', order.email || '', order.phone || '').all();
  return results.map((r) => r.install_id);
}

// ---------------------------------------------------------------------------
// Restock / price drop (every hour)

async function checkWishlistProducts(env) {
  const now = Date.now();
  const { results } = await env.DB.prepare(
    'SELECT DISTINCT product_id FROM wishlist LIMIT 300',
  ).all();
  const ids = results.map((r) => r.product_id);

  for (let i = 0; i < ids.length; i += 100) {
    let states;
    try {
      states = await productStates(ids.slice(i, i + 100), env);
    } catch (e) {
      console.error('product check failed:', e);
      continue;
    }
    for (const p of states) {
      const before = await env.DB.prepare('SELECT available, price FROM products WHERE product_id = ?')
        .bind(p.id).first();
      await env.DB.prepare(
        `INSERT INTO products (product_id, available, price, checked_at) VALUES (?, ?, ?, ?)
         ON CONFLICT (product_id) DO UPDATE SET available = excluded.available,
           price = excluded.price, checked_at = excluded.checked_at`,
      ).bind(p.id, p.available, p.price, now).run();
      if (!before) continue; // first look: nothing to compare with

      let flow = null;
      if (!before.available && p.available) flow = 'restock';
      else if (p.available && p.price <= before.price * 0.95) flow = 'price_drop';
      if (!flow) continue;

      const { results: fans } = await env.DB.prepare(
        'SELECT install_id, handle, title, image FROM wishlist WHERE product_id = ?',
      ).bind(p.id).all();
      for (const fan of fans) {
        const key = `${flow}:${p.id}`;
        // One alert per product per 3 days, however often stock flickers.
        if (await hasFlow(env, fan.install_id, key, now - 3 * DAY)) continue;
        await startFlow(env, fan.install_id, key, {
          handle: fan.handle, title: fan.title, image: fan.image, price: Math.round(p.price),
        }, now);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Admin

const AUDIENCES = {
  all: '1 = 1',
  signed_in: 'customer_id IS NOT NULL',
  buyers: 'last_order_at IS NOT NULL',
  non_buyers: 'last_order_at IS NULL',
};

/// Queues a message for everyone in [audience] (or one install with
/// audience "install:<installId>", handy for testing).
async function broadcast(body, env) {
  if (!str(body?.title) || !str(body?.body)) return json({ error: 'title and body are required' }, 400);
  const now = Date.now();
  const dueAt = body.sendAt ? Date.parse(body.sendAt) : now;
  if (Number.isNaN(dueAt)) return json({ error: 'sendAt must be an ISO date, e.g. 2026-11-01T19:30:00+05:30' }, 400);

  let where = AUDIENCES[body.audience || 'all'];
  const binds = [];
  if (String(body.audience || '').startsWith('install:')) {
    where = 'install_id = ?';
    binds.push(body.audience.slice('install:'.length));
  }
  if (!where) return json({ error: `audience must be one of ${Object.keys(AUDIENCES).join(', ')} or install:<id>` }, 400);

  const flow = `campaign:${now}`;
  const payload = JSON.stringify({
    title: body.title, body: body.body, link: str(body.link) || '/home', image: str(body.image),
  });
  const result = await env.DB.prepare(
    `INSERT INTO jobs (install_id, flow, step, promo, due_at, created_at, payload)
     SELECT install_id, ?, 0, 1, ?, ?, ? FROM devices
     WHERE fcm_token IS NOT NULL AND enabled = 1 AND ${where}`,
  ).bind(flow, dueAt, now, payload, ...binds).run();
  return json({ queued: result.meta.changes, campaign: flow });
}

async function stats(env) {
  const devices = await env.DB.prepare(
    `SELECT COUNT(*) AS installs,
       SUM(fcm_token IS NOT NULL AND enabled = 1) AS reachable,
       SUM(customer_id IS NOT NULL) AS signed_in
     FROM devices`,
  ).first();
  const { results } = await env.DB.prepare(
    `SELECT substr(flow, 1, instr(flow || ':', ':') - 1) AS flow, status, COUNT(*) AS n
     FROM jobs WHERE created_at > ? GROUP BY 1, 2 ORDER BY 1, 2`,
  ).bind(Date.now() - 7 * DAY).all();
  // How many reachable phones each broadcast audience has.
  const audiences = {};
  for (const [name, where] of Object.entries(AUDIENCES)) {
    const row = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM devices WHERE fcm_token IS NOT NULL AND enabled = 1 AND ${where}`,
    ).first();
    audiences[name] = row.n;
  }
  return json({ devices, audiences, last7Days: results, flows: Object.keys(FLOWS) });
}

/// The 30 latest broadcasts, newest first, with how many were sent and how
/// many are still waiting (scheduled, or held by quiet hours).
async function campaigns(env) {
  const { results } = await env.DB.prepare(
    `SELECT flow, MAX(payload) AS payload, MIN(due_at) AS due_at,
       SUM(status = 'sent') AS sent, SUM(status = 'pending') AS pending,
       SUM(status IN ('failed', 'skipped')) AS failed,
       SUM(status = 'cancelled') AS cancelled
     FROM jobs WHERE flow LIKE 'campaign:%'
     GROUP BY flow ORDER BY MAX(created_at) DESC LIMIT 30`,
  ).all();
  return json({
    campaigns: results.map((r) => {
      const p = JSON.parse(r.payload || '{}');
      return {
        campaign: r.flow, title: p.title, body: p.body, link: p.link,
        dueAt: r.due_at, sent: r.sent, pending: r.pending, failed: r.failed,
        cancelled: r.cancelled,
      };
    }),
  });
}

async function cancelCampaign(body, env) {
  const flow = String(body?.campaign || '');
  if (!/^campaign:\d+$/.test(flow)) return json({ error: 'campaign is required' }, 400);
  const result = await env.DB.prepare(
    "UPDATE jobs SET status = 'cancelled' WHERE flow = ? AND status = 'pending'",
  ).bind(flow).run();
  return json({ cancelled: result.meta.changes });
}

// ---------------------------------------------------------------------------
// Helpers

const str = (v) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, 500) : null);
const lower = (v) => (typeof v === 'string' && v.trim() ? v.trim().toLowerCase() : null);

function phone10(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  return digits.length >= 10 ? digits.slice(-10) : null;
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept, Authorization',
  'Access-Control-Max-Age': '86400',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}
