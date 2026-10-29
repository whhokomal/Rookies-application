// Shopify Admin + Storefront API helpers, and webhook signature checks.

const apiVersion = (env) => env.SHOPIFY_API_VERSION || '2026-04';

// Order webhooks this worker listens to (registered by POST /admin/setup-webhooks).
export const WEBHOOK_TOPICS = [
  'ORDERS_CREATE',
  'ORDERS_CANCELLED',
  'FULFILLMENTS_CREATE',
  'FULFILLMENT_EVENTS_CREATE',
];

// Admin API token, same as otp_login_worker: Dev Dashboard apps get one from
// the client credentials grant; it lasts 24h, so it's cached per worker
// instance and renewed a few minutes early. A legacy permanent
// SHOPIFY_ADMIN_API_TOKEN (shpat_...) still wins.
let cachedAdminToken = null; // { token, expiresAt }

async function adminToken(env) {
  if (env.SHOPIFY_ADMIN_API_TOKEN) return env.SHOPIFY_ADMIN_API_TOKEN;
  if (cachedAdminToken && Date.now() < cachedAdminToken.expiresAt) {
    return cachedAdminToken.token;
  }

  const res = await fetch(`https://${env.SHOPIFY_SHOP_DOMAIN}/admin/oauth/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: env.SHOPIFY_CLIENT_ID,
      client_secret: env.SHOPIFY_CLIENT_SECRET,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(`Shopify client credentials grant failed (${res.status}): ${JSON.stringify(data)}`);
  }

  const lifetimeMs = (Number(data.expires_in) || 86399) * 1000;
  cachedAdminToken = {
    token: data.access_token,
    expiresAt: Date.now() + lifetimeMs - 5 * 60 * 1000,
  };
  return cachedAdminToken.token;
}

export async function adminGraphql(query, variables, env) {
  const res = await fetch(
    `https://${env.SHOPIFY_SHOP_DOMAIN}/admin/api/${apiVersion(env)}/graphql.json`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Shopify-Access-Token': await adminToken(env),
      },
      body: JSON.stringify({ query, variables }),
    },
  );
  const json = await res.json();
  if (!res.ok || json.errors) {
    throw new Error(`Shopify Admin API: ${json.errors?.[0]?.message || res.status}`);
  }
  return json.data;
}

export async function storefrontGraphql(query, variables, env) {
  const res = await fetch(
    `https://${env.SHOPIFY_SHOP_DOMAIN}/api/${apiVersion(env)}/graphql.json`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Shopify-Storefront-Access-Token': env.SHOPIFY_STOREFRONT_TOKEN,
      },
      body: JSON.stringify({ query, variables }),
    },
  );
  const json = await res.json();
  if (!res.ok || json.errors) {
    throw new Error(`Shopify Storefront API: ${json.errors?.[0]?.message || res.status}`);
  }
  return json.data;
}

/// The signed-in customer behind a Storefront customer access token, or null.
export async function customerForToken(customerAccessToken, env) {
  const data = await storefrontGraphql(
    `query ($t: String!) { customer(customerAccessToken: $t) { id email phone firstName } }`,
    { t: customerAccessToken },
    env,
  );
  return data.customer;
}

/// { count, firstTitle } of a Storefront cart, or null when Shopify no
/// longer has it (expired or turned into an order).
export async function cartSummary(cartId, env) {
  const data = await storefrontGraphql(
    `query ($id: ID!) {
      cart(id: $id) {
        totalQuantity
        lines(first: 1) { edges { node { merchandise { ... on ProductVariant { product { title } } } } } }
      }
    }`,
    { id: cartId },
    env,
  );
  if (!data.cart) return null;
  return {
    count: data.cart.totalQuantity,
    firstTitle: data.cart.lines.edges[0]?.node.merchandise?.product?.title || '',
  };
}

/// Stock and lowest price for up to 100 product ids.
export async function productStates(ids, env) {
  const data = await storefrontGraphql(
    `query ($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on Product { id availableForSale priceRange { minVariantPrice { amount } } }
      }
    }`,
    { ids },
    env,
  );
  return data.nodes.filter(Boolean).map((p) => ({
    id: p.id,
    available: p.availableForSale ? 1 : 0,
    price: Number(p.priceRange.minVariantPrice.amount),
  }));
}

/// Subscribes the order webhooks to [uri]. Topics already pointing there are
/// skipped, so it's safe to run again.
export async function registerWebhooks(uri, env) {
  const existing = await adminGraphql(
    `{ webhookSubscriptions(first: 100) { nodes { topic uri } } }`, {}, env,
  );
  const have = new Set(existing.webhookSubscriptions.nodes
    .filter((n) => n.uri === uri).map((n) => n.topic));

  const results = {};
  for (const topic of WEBHOOK_TOPICS) {
    if (have.has(topic)) {
      results[topic] = 'already subscribed';
      continue;
    }
    const data = await adminGraphql(
      `mutation ($topic: WebhookSubscriptionTopic!, $sub: WebhookSubscriptionInput!) {
        webhookSubscriptionCreate(topic: $topic, webhookSubscription: $sub) {
          webhookSubscription { id }
          userErrors { message }
        }
      }`,
      { topic, sub: { uri } },
      env,
    );
    const errors = data.webhookSubscriptionCreate.userErrors;
    results[topic] = errors.length ? errors.map((e) => e.message).join('; ') : 'subscribed';
  }
  return results;
}

/// True when [rawBody] carries a valid X-Shopify-Hmac-Sha256 signature
/// (signed with the app's client secret).
export async function isValidWebhook(rawBody, signature, env) {
  const secret = env.SHOPIFY_WEBHOOK_SECRET || env.SHOPIFY_CLIENT_SECRET;
  if (!signature || !secret) return false;
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'],
  );
  let expected;
  try {
    expected = Uint8Array.from(atob(signature), (c) => c.charCodeAt(0));
  } catch {
    return false;
  }
  // crypto.subtle.verify compares in constant time.
  return crypto.subtle.verify('HMAC', key, expected, new TextEncoder().encode(rawBody));
}
