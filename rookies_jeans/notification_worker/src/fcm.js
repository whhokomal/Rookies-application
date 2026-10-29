// Sends one push through Firebase Cloud Messaging (HTTP v1), which delivers
// to Android directly and to iOS through Apple's push service (APNs key
// uploaded in the Firebase console).
//
// Auth is a Google OAuth token made from the FIREBASE_SERVICE_ACCOUNT secret
// (the service-account JSON from Firebase), cached until shortly before it
// expires.

let cachedToken = null; // { token, expiresAt }

/// Returns 'sent', 'unregistered' (token no longer valid: forget it) or
/// 'error' (try again later).
export async function sendPush(env, fcmToken, message, { transactional }) {
  const account = serviceAccount(env);
  const data = { link: message.link || '/home' };

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${await accessToken(env)}`,
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: {
            title: message.title,
            body: message.body,
            ...(message.image ? { image: message.image } : {}),
          },
          data,
          android: {
            priority: 'HIGH',
            notification: {
              // Must match the channels the app creates.
              channel_id: transactional ? 'orders' : 'offers',
              icon: 'ic_notification',
            },
          },
          apns: {
            payload: { aps: { sound: 'default', 'mutable-content': 1 } },
            ...(message.image ? { fcm_options: { image: message.image } } : {}),
          },
        },
      }),
    },
  );

  if (res.ok) return 'sent';
  const body = await res.json().catch(() => ({}));
  const codes = (body.error?.details || []).map((d) => d.errorCode);
  if (res.status === 404 || codes.includes('UNREGISTERED') || codes.includes('INVALID_ARGUMENT')) {
    // INVALID_ARGUMENT for a well-formed message means a malformed token.
    console.warn('FCM rejected token:', res.status, body.error?.message);
    return 'unregistered';
  }
  console.error('FCM send failed:', res.status, JSON.stringify(body));
  return 'error';
}

function serviceAccount(env) {
  if (!env.FIREBASE_SERVICE_ACCOUNT) throw new Error('FIREBASE_SERVICE_ACCOUNT is not set');
  return JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
}

async function accessToken(env) {
  if (cachedToken && Date.now() < cachedToken.expiresAt) return cachedToken.token;

  const account = serviceAccount(env);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64UrlJson(header)}.${base64UrlJson(claims)}`;
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToBytes(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${toBase64Url(signature)}`,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(`Google OAuth failed (${res.status}): ${JSON.stringify(data)}`);
  }
  cachedToken = {
    token: data.access_token,
    expiresAt: Date.now() + (Number(data.expires_in) || 3600) * 1000 - 5 * 60 * 1000,
  };
  return cachedToken.token;
}

function pemToBytes(pem) {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

function base64UrlJson(value) {
  return toBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function toBase64Url(bytes) {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
