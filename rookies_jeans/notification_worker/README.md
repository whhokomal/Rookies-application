# Rookies push notifications

A Cloudflare Worker that sends the app's automatic push notifications (cart
reminders, order updates, restocks, win-backs ...) through Firebase. It runs
on the free plans of Cloudflare and Firebase.

- **Timings and wording:** [`src/flows.js`](src/flows.js). Edit and run
  `npm run deploy`; no app update needed.
- **Quiet hours, daily limit, coupon codes:** `[vars]` in
  [`wrangler.toml`](wrangler.toml).
- **How it fits together:** the header of [`src/index.js`](src/index.js).

## 1. Firebase (free)

1. console.firebase.google.com → **Add project** (Analytics not needed).
2. **Add app → Android**, package `com.rookiesjeans.rookiesjeans`. Download
   `google-services.json` into `android/app/`.
3. **Add app → iOS**, bundle ID `com.rookiesjeans.rookiesjeans`. Download
   `GoogleService-Info.plist`; on the Mac, drag it into `ios/Runner` in Xcode
   (tick "Copy items if needed" and the Runner target).
4. **Project settings → Cloud Messaging → Apple app configuration**: upload
   the APNs key from step 2 below.
5. **Project settings → Service accounts → Generate new private key**. This
   JSON file is the `FIREBASE_SERVICE_ACCOUNT` secret. Keep it private.

## 2. Apple Developer account

1. developer.apple.com → Certificates, IDs & Profiles → **Keys → +**, tick
   **Apple Push Notifications service (APNs)**, download the `.p8` file and
   note the Key ID and your Team ID (for Firebase step 4).
2. **Identifiers** → `com.rookiesjeans.rookiesjeans` → tick **Push
   Notifications** → Save. Xcode then picks it up from `Runner.entitlements`.

## 3. Shopify

The worker reuses the **Rookies OTP Login** app from `otp_login_worker`. In
the Dev Dashboard add the **`read_orders`** and **`read_fulfillments`**
scopes to its access scopes, release the version, then click **Install app**
on the app's overview to approve the new access on the store (until then
Shopify refuses the webhooks with "You cannot create a webhook subscription
with the specified topic"). Use that app's Client ID and
secret below (webhooks are signed with that secret).

## 4. Deploy

```bash
cd notification_worker
npm install
npx wrangler login
npx wrangler d1 create rookies-notifications   # paste the printed database_id into wrangler.toml
npm run db:init
npx wrangler secret put FIREBASE_SERVICE_ACCOUNT   # paste the whole JSON file
npx wrangler secret put SHOPIFY_CLIENT_ID
npx wrangler secret put SHOPIFY_CLIENT_SECRET
npx wrangler secret put ADMIN_KEY                  # any long random string
npm run deploy
```

Put the printed worker URL in `notificationsUrl` in
`lib/constants/shopify_constants.dart`, then subscribe the order webhooks:

```bash
curl -X POST https://<worker-url>/admin/setup-webhooks -H "Authorization: Bearer <ADMIN_KEY>"
```

## Sending a campaign (new drop, sale)

```bash
curl -X POST https://<worker-url>/admin/broadcast \
  -H "Authorization: Bearer <ADMIN_KEY>" -H "Content-Type: application/json" \
  -d '{"title":"Sale is live","body":"Hey {name}, flat 40% off till midnight","link":"/collections/hot-deals","audience":"all","sendAt":"2026-11-01T19:30:00+05:30"}'
```

`audience`: `all`, `signed_in`, `buyers`, `non_buyers`, or `install:<id>` to
test on one phone. `link` is any app path (`/products/<handle>`,
`/collections/<handle>`, `/cart`, `/orders`). Leave out `sendAt` to send now.

`GET /admin/stats` (same header) shows how many phones are reachable and what
was sent in the last 7 days. `npm run logs` streams live logs.

## Limits

- Free Workers plan: about 40 pushes per minute (~57,000 a day). A broadcast
  to more people than that takes a few minutes to go out. The $5/month plan
  raises it if ever needed.
- Shipping updates (out for delivery, delivered) come from Shopify
  fulfillment events, which the courier app must report to Shopify.
  "Shipped" works as soon as an order is fulfilled.
