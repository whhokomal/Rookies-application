# links.rookiesjeans.com

Static Vercel site that makes shared product links open the Rookies app.

Shopify generates rookiesjeans.com/.well-known/* from records we can't edit,
so share links use this domain instead:

- `/.well-known/assetlinks.json` – Android App Links verification
- `/.well-known/apple-app-site-association` – iOS Universal Links
  (replace `APPLE_TEAM_ID` with the 10-character Team ID, then redeploy)
- `/products/<handle>` – when the app isn't installed, redirects to
  rookiesjeans.com/products/<handle>

Deploy: `npx vercel --prod` from this folder.
