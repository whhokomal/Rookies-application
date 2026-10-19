# rookies-links.vercel.app

Static Vercel site that makes shared product links open the Rookies app.

Shopify generates rookiesjeans.com/.well-known/* from records we can't edit,
so share links use this domain instead (links.rookiesjeans.com is
attached in Vercel too, pending a CNAME at the registrar):

- `/.well-known/assetlinks.json` – Android App Links verification
- `/.well-known/apple-app-site-association` – iOS Universal Links
  (Apple Team ID 6P6NW373DC)
- `/products/<handle>` – when the app isn't installed, redirects to
  rookiesjeans.com/products/<handle>

Deploy: `npx vercel --prod` from this folder.
