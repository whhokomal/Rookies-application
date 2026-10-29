// The page served at GET /admin for sending notifications by hand. It is
// plain HTML; everything it does goes through the /admin/* endpoints, which
// need the ADMIN_KEY (typed in once and kept in this browser).

export const ADMIN_PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Rookies Notifications</title>
<style>
  :root {
    --bg: #f4f4f2; --card: #fff; --text: #161616; --muted: #6b6b6b;
    --line: #e2e2de; --accent: #161616; --accent-text: #fff;
    --ok: #1d7a3a; --err: #b42318; --field: #fafaf8;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #111; --card: #1b1b1b; --text: #f1f1f1; --muted: #9a9a9a;
      --line: #2e2e2e; --accent: #f1f1f1; --accent-text: #111;
      --ok: #4cc06f; --err: #ff7a6b; --field: #151515;
    }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 980px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  h2 { font-size: 15px; margin: 0 0 14px; }
  .sub { color: var(--muted); margin: 0 0 20px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 18px; }
  .grid { display: grid; grid-template-columns: 1fr 320px; gap: 16px; align-items: start; }
  @media (max-width: 760px) { .grid { grid-template-columns: 1fr; } }
  label { display: block; font-weight: 600; font-size: 13px; margin: 14px 0 6px; }
  label:first-child { margin-top: 0; }
  .hint { font-weight: 400; color: var(--muted); }
  input, textarea, select { width: 100%; font: inherit; color: var(--text); background: var(--field);
    border: 1px solid var(--line); border-radius: 8px; padding: 9px 11px; }
  textarea { resize: vertical; min-height: 76px; }
  input:focus, textarea:focus, select:focus { outline: 2px solid var(--accent); outline-offset: -1px; }
  .row { display: flex; gap: 10px; flex-wrap: wrap; }
  .row > * { flex: 1 1 160px; }
  .radios { display: flex; gap: 16px; margin-top: 4px; }
  .radios label { display: flex; gap: 6px; align-items: center; font-weight: 400; margin: 0; font-size: 14px; }
  .radios input { width: auto; }
  button { font: inherit; font-weight: 600; border-radius: 8px; padding: 10px 16px; cursor: pointer;
    border: 1px solid var(--accent); background: var(--accent); color: var(--accent-text); }
  button.secondary { background: transparent; color: var(--text); border-color: var(--line); }
  button:disabled { opacity: .5; cursor: default; }
  .actions { display: flex; gap: 10px; margin-top: 18px; flex-wrap: wrap; }
  .msg { margin-top: 12px; font-size: 14px; min-height: 20px; }
  .msg.ok { color: var(--ok); } .msg.err { color: var(--err); }
  .stats { display: flex; gap: 10px; margin-bottom: 16px; flex-wrap: wrap; }
  .stat { flex: 1 1 120px; background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; }
  .stat b { display: block; font-size: 22px; }
  .stat span { color: var(--muted); font-size: 13px; }
  .phone { background: linear-gradient(160deg, #3b4a5a, #1d2630); border-radius: 22px; padding: 16px 12px 40px; }
  .note { background: rgba(245,245,245,.92); color: #111; border-radius: 14px; padding: 10px 12px;
    display: flex; gap: 10px; }
  .note .icon { width: 34px; height: 34px; border-radius: 8px; background: #111; color: #fff;
    display: grid; place-items: center; font-weight: 800; flex: none; }
  .note .top { display: flex; justify-content: space-between; font-size: 12px; color: #555; }
  .note .t { font-weight: 600; font-size: 14px; margin-top: 1px; overflow-wrap: anywhere; }
  .note .b { font-size: 14px; overflow-wrap: anywhere; }
  .note img { width: 100%; border-radius: 8px; margin-top: 8px; display: none; }
  .small { color: var(--muted); font-size: 13px; margin: 10px 0 0; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: left; padding: 9px 6px; border-top: 1px solid var(--line); vertical-align: top; }
  th { color: var(--muted); font-weight: 600; font-size: 12px; border-top: none; }
  td .t { font-weight: 600; } td .b { color: var(--muted); }
  .table-wrap { overflow-x: auto; }
  .hidden { display: none !important; }
  .keycard { max-width: 420px; }
</style>
</head>
<body>
<main>
  <h1>Rookies Notifications</h1>
  <p class="sub">Send a push notification to the app's customers.</p>

  <section id="login" class="card keycard hidden">
    <h2>Enter your admin key</h2>
    <label for="key">Admin key <span class="hint">(saved in this browser only)</span></label>
    <input id="key" type="password" autocomplete="current-password">
    <div class="actions"><button id="saveKey">Continue</button></div>
    <div id="loginMsg" class="msg err"></div>
  </section>

  <div id="app" class="hidden">
    <div class="stats">
      <div class="stat"><b id="sReach">–</b><span>phones that can get pushes</span></div>
      <div class="stat"><b id="sSigned">–</b><span>signed in</span></div>
      <div class="stat"><b id="sBuyers">–</b><span>have ordered</span></div>
    </div>

    <div class="grid">
      <form id="form" class="card" autocomplete="off">
        <h2>New notification</h2>
        <label for="title">Title</label>
        <input id="title" maxlength="65" required placeholder="New drop is live">
        <label for="body">Message <span class="hint">· {name} becomes the customer's first name</span></label>
        <textarea id="body" maxlength="240" required placeholder="Hey {name}, fresh fits just landed. Grab yours before they're gone."></textarea>
        <label for="link">Opens <span class="hint">· paste a product or collection link from the website, or leave empty for home</span></label>
        <input id="link" placeholder="https://rookiesjeans.com/collections/new-arrivals">
        <label for="image">Image link <span class="hint">· optional, shows a big picture</span></label>
        <input id="image" placeholder="https://cdn.shopify.com/...jpg">

        <div class="row">
          <div>
            <label for="audience">Send to</label>
            <select id="audience">
              <option value="all">Everyone</option>
              <option value="signed_in">Signed-in customers</option>
              <option value="buyers">Customers who have ordered</option>
              <option value="non_buyers">People who haven't ordered yet</option>
            </select>
          </div>
          <div>
            <label>When</label>
            <div class="radios">
              <label><input type="radio" name="when" value="now" checked> Now</label>
              <label><input type="radio" name="when" value="later"> Schedule</label>
            </div>
          </div>
        </div>
        <div id="laterBox" class="hidden">
          <label for="sendAt">Date and time <span class="hint">(India time)</span></label>
          <input id="sendAt" type="datetime-local">
        </div>

        <p class="small">Messages that fall between 10:30 pm and 9 am go out at 9 am instead.</p>
        <div class="actions">
          <button type="submit" id="send">Send</button>
          <button type="button" id="test" class="secondary">Send test to one phone</button>
        </div>
        <div id="testBox" class="hidden">
          <label for="installId">Phone's install ID <span class="hint">· remembered here after the first test</span></label>
          <div class="row">
            <input id="installId" placeholder="104220674c8f7a6860c813b3f4e163dc">
            <button type="button" id="sendTest" style="flex:0 0 auto">Send test</button>
          </div>
        </div>
        <div id="formMsg" class="msg"></div>
      </form>

      <div class="card">
        <h2>Preview</h2>
        <div class="phone">
          <div class="note">
            <div class="icon">R</div>
            <div style="flex:1;min-width:0">
              <div class="top"><span>Rookies</span><span>now</span></div>
              <div class="t" id="pTitle">New drop is live</div>
              <div class="b" id="pBody">Hey Komal, fresh fits just landed.</div>
              <img id="pImg" alt="">
            </div>
          </div>
        </div>
        <p class="small">Looks slightly different on each phone.</p>
      </div>
    </div>

    <section class="card" style="margin-top:16px">
      <h2>Recent notifications</h2>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Message</th><th>Send time</th><th>Sent</th><th>Waiting</th><th></th></tr></thead>
          <tbody id="history"><tr><td colspan="5" class="small">Loading…</td></tr></tbody>
        </table>
      </div>
      <div class="actions"><button type="button" id="logout" class="secondary">Forget admin key</button></div>
    </section>
  </div>
</main>

<script>
const $ = (id) => document.getElementById(id);
const store = {
  get(k) { try { return localStorage.getItem(k) || ''; } catch { return ''; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch {} },
  del(k) { try { localStorage.removeItem(k); } catch {} },
};
let key = store.get('rookiesAdminKey');

async function api(path, body) {
  const res = await fetch('/admin/' + path, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401) { showLogin('That admin key is not right.'); throw new Error('Unauthorized'); }
  if (!res.ok) throw new Error(data.error || 'Something went wrong (' + res.status + ')');
  return data;
}

function showLogin(err) {
  $('app').classList.add('hidden');
  $('login').classList.remove('hidden');
  $('loginMsg').textContent = err || '';
  $('key').focus();
}

async function start() {
  if (!key) return showLogin();
  try {
    await loadStats();
    $('login').classList.add('hidden');
    $('app').classList.remove('hidden');
    loadHistory();
  } catch (e) {
    if (e.message !== 'Unauthorized') showLogin(e.message);
  }
}

$('saveKey').onclick = () => {
  key = $('key').value.trim();
  if (!key) return;
  store.set('rookiesAdminKey', key);
  start();
};
$('key').onkeydown = (e) => { if (e.key === 'Enter') $('saveKey').click(); };
$('logout').onclick = () => { store.del('rookiesAdminKey'); key = ''; $('key').value = ''; showLogin(); };

async function loadStats() {
  const s = await api('stats');
  const a = s.audiences || {};
  $('sReach').textContent = s.devices.reachable || 0;
  $('sSigned').textContent = a.signed_in ?? '–';
  $('sBuyers').textContent = a.buyers ?? '–';
  const names = { all: 'Everyone', signed_in: 'Signed-in customers', buyers: 'Customers who have ordered', non_buyers: "People who haven't ordered yet" };
  for (const opt of $('audience').options) {
    if (a[opt.value] != null) opt.textContent = names[opt.value] + ' (' + a[opt.value] + ')';
  }
}

const fmt = (ms) => new Date(ms).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });

async function loadHistory() {
  const tbody = $('history');
  try {
    const { campaigns } = await api('campaigns');
    tbody.textContent = '';
    if (!campaigns.length) {
      tbody.innerHTML = '<tr><td colspan="5" class="small">Nothing sent yet.</td></tr>';
      return;
    }
    for (const c of campaigns) {
      const tr = document.createElement('tr');
      const msg = document.createElement('td');
      const t = document.createElement('div'); t.className = 't'; t.textContent = c.title || '';
      const b = document.createElement('div'); b.className = 'b'; b.textContent = c.body || '';
      msg.append(t, b);
      const cells = [fmt(c.dueAt), c.sent, c.pending || (c.cancelled ? 'Cancelled' : 0)].map((v) => { const td = document.createElement('td'); td.textContent = v; return td; });
      const act = document.createElement('td');
      if (c.pending > 0) {
        const btn = document.createElement('button');
        btn.className = 'secondary'; btn.textContent = 'Cancel';
        btn.onclick = async () => {
          if (!confirm('Cancel the ' + c.pending + ' messages still waiting?')) return;
          btn.disabled = true;
          try { await api('cancel', { campaign: c.campaign }); } catch (e) { alert(e.message); }
          loadHistory();
        };
        act.append(btn);
      }
      tr.append(msg, ...cells, act);
      tbody.append(tr);
    }
  } catch (e) {
    tbody.innerHTML = '<tr><td colspan="5" class="small"></td></tr>';
    tbody.querySelector('td').textContent = e.message;
  }
}

// Website links work too: keep only the path the app understands.
function appLink(raw) {
  raw = raw.trim();
  if (!raw) return '/home';
  try { raw = new URL(raw, 'https://x.invalid').pathname; } catch {}
  return raw.startsWith('/') ? raw : '/' + raw;
}

function preview() {
  $('pTitle').textContent = $('title').value || $('title').placeholder;
  $('pBody').textContent = ($('body').value || $('body').placeholder).replace(/\\{name\\}/g, 'Komal');
  const img = $('image').value.trim();
  $('pImg').style.display = img ? 'block' : 'none';
  if (img) $('pImg').src = img;
}
['title', 'body', 'image'].forEach((id) => $(id).addEventListener('input', preview));
$('pImg').onerror = () => { $('pImg').style.display = 'none'; };

document.querySelectorAll('input[name=when]').forEach((r) => r.onchange = () => {
  $('laterBox').classList.toggle('hidden', r.value !== 'later' || !r.checked);
});

function message() {
  const title = $('title').value.trim(), body = $('body').value.trim();
  if (!title || !body) throw new Error('Write a title and a message first.');
  const m = { title, body, link: appLink($('link').value) };
  const image = $('image').value.trim();
  if (image) m.image = image;
  return m;
}

function say(text, ok) { $('formMsg').textContent = text; $('formMsg').className = 'msg ' + (ok ? 'ok' : 'err'); }

$('form').onsubmit = async (e) => {
  e.preventDefault();
  try {
    const m = message();
    m.audience = $('audience').value;
    const later = document.querySelector('input[name=when]:checked').value === 'later';
    if (later) {
      if (!$('sendAt').value) throw new Error('Pick a date and time.');
      m.sendAt = $('sendAt').value + ':00+05:30';
    }
    const who = $('audience').selectedOptions[0].textContent;
    if (!confirm((later ? 'Schedule' : 'Send') + ' "' + m.title + '" to ' + who + '?')) return;
    $('send').disabled = true;
    const r = await api('broadcast', m);
    say(r.queued ? (later ? 'Scheduled for ' : 'Sending to ') + r.queued + ' phone' + (r.queued === 1 ? '' : 's') + '.' : 'Nobody in that group can get pushes yet.', r.queued > 0);
    loadHistory();
  } catch (err) {
    if (err.message !== 'Unauthorized') say(err.message, false);
  } finally {
    $('send').disabled = false;
  }
};

$('installId').value = store.get('rookiesTestInstall');
$('test').onclick = () => { $('testBox').classList.toggle('hidden'); $('installId').focus(); };
$('sendTest').onclick = async () => {
  try {
    const id = $('installId').value.trim();
    if (!id) throw new Error("Enter the phone's install ID.");
    const m = message();
    m.audience = 'install:' + id;
    const r = await api('broadcast', m);
    if (!r.queued) throw new Error("That phone can't get pushes (wrong ID, or notifications are off).");
    store.set('rookiesTestInstall', id);
    say('Test sent. It arrives within a minute.', true);
    loadHistory();
  } catch (err) {
    if (err.message !== 'Unauthorized') say(err.message, false);
  }
};

start();
</script>
</body>
</html>`;
