// Replaces the orphaned mobile app records Shopify uses to generate
// https://rookiesjeans.com/.well-known/assetlinks.json and
// apple-app-site-association, so shared product links open the app.
//
// Needs the "Rookies Mobile App Links" custom app with the
// read/write_mobile_platform_applications scopes enabled by Shopify Support.
//
// Usage (dry run first, then --apply):
//   SHOPIFY_CLIENT_SECRET=... node tool/fix_app_links.mjs
//   SHOPIFY_CLIENT_SECRET=... APPLE_TEAM_ID=XXXXXXXXXX node tool/fix_app_links.mjs --apply
//
// APPLE_TEAM_ID is optional; without it only the Android record is replaced.

const SHOP = process.env.SHOPIFY_SHOP ?? 'rookies-jeans.myshopify.com';
const CLIENT_ID = process.env.SHOPIFY_CLIENT_ID ?? '35d85518f51d38a920726303a5bfb683';
const CLIENT_SECRET = process.env.SHOPIFY_CLIENT_SECRET;
const APPLE_TEAM_ID = process.env.APPLE_TEAM_ID;
const API_VERSION = '2025-10';
const APPLY = process.argv.includes('--apply');

const ANDROID_PACKAGE = 'com.rookiesjeans.rookiesjeans';
const IOS_BUNDLE = 'com.rookiesjeans.rookiesjeans';
const ANDROID_FINGERPRINTS = [
  // Play app signing key (what installs from the Play Store are signed with)
  '12:77:9D:C2:E7:E2:65:96:2B:16:BB:5F:67:04:DB:C2:FC:96:F3:67:B2:CA:9E:DF:ED:39:A6:73:62:16:6E:F8',
  // Previous app signing key
  'D1:DE:13:D9:D2:F2:81:65:3A:46:F9:34:D0:A3:6E:45:2E:2F:60:7B:C0:81:83:91:BA:1F:11:89:27:61:D1:C6',
  // Upload key (sideloaded / internal builds)
  'D2:F6:88:7F:85:B7:87:90:87:E3:A6:9B:EF:5C:79:F5:92:CE:18:05:34:80:A8:B9:0A:17:6F:3B:6D:9F:90:A4',
];

if (!CLIENT_SECRET) {
  console.error('Set SHOPIFY_CLIENT_SECRET (Dev Dashboard > Rookies Mobile App Links > Settings).');
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

const token = await getToken();

const { mobilePlatformApplications } = await gql(token, `{
  mobilePlatformApplications(first: 20) {
    nodes {
      __typename
      ... on AndroidApplication { id applicationId appLinksEnabled sha256CertFingerprints }
      ... on AppleApplication { id appId universalLinksEnabled sharedWebCredentialsEnabled }
    }
  }
}`);

const existing = mobilePlatformApplications.nodes;
console.log('Current records:');
console.log(JSON.stringify(existing, null, 2));

const toDelete = existing.filter((app) =>
  app.__typename === 'AndroidApplication' || (APPLE_TEAM_ID && app.__typename === 'AppleApplication'));

const android = {
  applicationId: ANDROID_PACKAGE,
  appLinksEnabled: true,
  sha256CertFingerprints: ANDROID_FINGERPRINTS,
};
const apple = APPLE_TEAM_ID && {
  appId: `${APPLE_TEAM_ID}.${IOS_BUNDLE}`,
  universalLinksEnabled: true,
  sharedWebCredentialsEnabled: true,
};

console.log('\nPlan:');
for (const app of toDelete) console.log(`  delete ${app.__typename} ${app.applicationId ?? app.appId} (${app.id})`);
console.log(`  create Android ${android.applicationId}`);
if (apple) console.log(`  create Apple ${apple.appId}`);
else console.log('  (skipping iOS: APPLE_TEAM_ID not set)');

if (!APPLY) {
  console.log('\nDry run only. Re-run with --apply to make these changes.');
  process.exit(0);
}

for (const app of toDelete) {
  const data = await gql(token, `mutation($id: ID!) {
    mobilePlatformApplicationDelete(id: $id) { deletedMobilePlatformApplicationId userErrors { field message } }
  }`, { id: app.id });
  checkUserErrors('delete', data.mobilePlatformApplicationDelete);
  console.log(`Deleted ${app.id}`);
}

const createMutation = `mutation($input: MobilePlatformApplicationCreateInput!) {
  mobilePlatformApplicationCreate(input: $input) {
    mobilePlatformApplication { __typename ... on AndroidApplication { id } ... on AppleApplication { id } }
    userErrors { field message }
  }
}`;

for (const input of [{ android }, apple && { apple }].filter(Boolean)) {
  const data = await gql(token, createMutation, { input });
  checkUserErrors('create', data.mobilePlatformApplicationCreate);
  console.log(`Created ${data.mobilePlatformApplicationCreate.mobilePlatformApplication.id}`);
}

console.log('\nDone. Check (may take a few minutes to update):');
console.log('  https://rookiesjeans.com/.well-known/assetlinks.json');
console.log('  https://rookiesjeans.com/.well-known/apple-app-site-association');
