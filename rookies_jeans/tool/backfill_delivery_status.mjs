// One-off backfill: copies each past order's shipment status (PICKED_UP,
// IN_TRANSIT, OUT_FOR_DELIVERY, ATTEMPTED_DELIVERY, DELIVERED) into the order
// metafield custom.delivery_status, which the app reads to show Shipped /
// Delivered. New updates are written by the Shopify Flow
// (Fulfillment event created → Update order metafield).
//
// Needs a custom app with the read_orders, write_orders and read_all_orders
// scopes (read_all_orders, or Shopify only returns the last 60 days).
//
// Usage (dry run first, then --apply):
//   SHOPIFY_CLIENT_ID=... SHOPIFY_CLIENT_SECRET=... node tool/backfill_delivery_status.mjs
//   SHOPIFY_CLIENT_ID=... SHOPIFY_CLIENT_SECRET=... node tool/backfill_delivery_status.mjs --apply

const SHOP = process.env.SHOPIFY_SHOP ?? 'rookies-jeans.myshopify.com';
const CLIENT_ID = process.env.SHOPIFY_CLIENT_ID;
const CLIENT_SECRET = process.env.SHOPIFY_CLIENT_SECRET;
const API_VERSION = '2025-10';
const APPLY = process.argv.includes('--apply');

// metafieldsSet accepts at most 25 metafields per call.
const BATCH = 25;

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error('Set SHOPIFY_CLIENT_ID and SHOPIFY_CLIENT_SECRET (Dev Dashboard > your app > Settings).');
  process.exit(1);
}

async function getToken() {
  const res = await fetch(`https://${SHOP}/admin/oauth/access_token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    throw new Error(`Token request failed (${res.status}): ${JSON.stringify(body)}`);
  }
  return body.access_token;
}

async function gql(token, query, variables = {}) {
  const res = await fetch(`https://${SHOP}/admin/api/${API_VERSION}/graphql.json`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': token },
    body: JSON.stringify({ query, variables }),
  });
  const body = await res.json();
  if (body.errors) throw new Error(JSON.stringify(body.errors, null, 2));
  return body.data;
}

function checkUserErrors(label, payload) {
  if (payload.userErrors?.length) {
    throw new Error(`${label}: ${JSON.stringify(payload.userErrors)}`);
  }
}

async function waitForBulk(token, id) {
  for (;;) {
    const { node } = await gql(token, `query($id: ID!) {
      node(id: $id) { ... on BulkOperation { status errorCode objectCount url } }
    }`, { id });
    process.stdout.write(`\r  ${node.status}, ${node.objectCount} objects   `);
    if (!['CREATED', 'RUNNING'].includes(node.status)) {
      console.log();
      if (node.status !== 'COMPLETED') throw new Error(`Bulk operation ${node.status} (${node.errorCode})`);
      return node;
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
}

const token = await getToken();

// 1. Export every fulfilled order with its shipments' delivery status.
console.log('Exporting fulfilled orders...');
const run = await gql(token, `mutation {
  bulkOperationRunQuery(query: """
    { orders(query: "fulfillment_status:shipped OR fulfillment_status:partial") {
      edges { node { id fulfillments { displayStatus } metafield(namespace: "custom", key: "delivery_status") { value } } }
    } }
  """) { bulkOperation { id } userErrors { field message } }
}`);
checkUserErrors('bulkOperationRunQuery', run.bulkOperationRunQuery);
const exported = await waitForBulk(token, run.bulkOperationRunQuery.bulkOperation.id);
const lines = exported.url
  ? (await (await fetch(exported.url)).text()).split('\n').filter(Boolean).map(JSON.parse)
  : [];

// 2. DELIVERED when every shipment is delivered, otherwise the first
// shipment's status if it has been picked up; skip unchanged orders.
const SHIPPED = ['PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY', 'ATTEMPTED_DELIVERY'];
function statusOf(o) {
  const statuses = o.fulfillments.map((f) => f.displayStatus);
  if (statuses.length && statuses.every((s) => s === 'DELIVERED')) return 'DELIVERED';
  return statuses.find((s) => SHIPPED.includes(s) || s === 'DELIVERED') ?? null;
}
const updates = lines
  .map((o) => ({ id: o.id, value: statusOf(o), current: o.metafield?.value?.toUpperCase() }))
  .filter((u) => u.value && u.value !== u.current);
const counts = {};
for (const u of updates) counts[u.value] = (counts[u.value] ?? 0) + 1;
console.log(`${lines.length} fulfilled orders, ${updates.length} to update:`, counts);

if (!updates.length) process.exit(0);
if (!APPLY) {
  console.log('\nDry run only. Re-run with --apply to update them.');
  process.exit(0);
}

// 3. Upload the metafieldsSet variables and run them as a bulk mutation.
const jsonl = [];
for (let i = 0; i < updates.length; i += BATCH) {
  jsonl.push(JSON.stringify({
    metafields: updates.slice(i, i + BATCH).map(({ id, value }) => ({
      ownerId: id,
      namespace: 'custom',
      key: 'delivery_status',
      type: 'single_line_text_field',
      value,
    })),
  }));
}
const file = new Blob([jsonl.join('\n') + '\n'], { type: 'text/jsonl' });

const staged = await gql(token, `mutation {
  stagedUploadsCreate(input: [{ resource: BULK_MUTATION_VARIABLES, filename: "delivered.jsonl", mimeType: "text/jsonl", httpMethod: POST }]) {
    stagedTargets { url parameters { name value } }
    userErrors { field message }
  }
}`);
checkUserErrors('stagedUploadsCreate', staged.stagedUploadsCreate);
const target = staged.stagedUploadsCreate.stagedTargets[0];
const form = new FormData();
for (const { name, value } of target.parameters) form.append(name, value);
form.append('file', file, 'delivered.jsonl');
const upload = await fetch(target.url, { method: 'POST', body: form });
if (!upload.ok) throw new Error(`Upload failed (${upload.status}): ${await upload.text()}`);
const path = target.parameters.find((p) => p.name === 'key').value;

console.log(`Updating ${updates.length} orders...`);
const mutate = await gql(token, `mutation($path: String!) {
  bulkOperationRunMutation(
    mutation: "mutation call($metafields: [MetafieldsSetInput!]!) { metafieldsSet(metafields: $metafields) { userErrors { field message } } }",
    stagedUploadPath: $path
  ) { bulkOperation { id } userErrors { field message } }
}`, { path });
checkUserErrors('bulkOperationRunMutation', mutate.bulkOperationRunMutation);
const result = await waitForBulk(token, mutate.bulkOperationRunMutation.bulkOperation.id);

// 4. Report any per-batch errors.
const failed = result.url
  ? (await (await fetch(result.url)).text()).split('\n').filter((l) => l.includes('"message"'))
  : [];
console.log(failed.length ? `${failed.length} batches had errors:\n${failed.slice(0, 5).join('\n')}` : 'Done.');
