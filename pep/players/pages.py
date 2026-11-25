"""
Small web pages for people who don't have the app: a guardian opening the
link from a text (/g/4F7K). Plain HTML and a little JavaScript, served by the
API itself, so they work on any phone browser with no install and little data.

The page only talks to the JSON routes in guardian_routes.py. It builds every
piece of text with `textContent`, never by pasting strings into HTML, so a
name like "<script>" shows as text instead of running (that attack is called
*cross-site scripting*, XSS; handbook chapter 10).
"""

from __future__ import annotations

from html import escape

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse

from . import card

router = APIRouter(include_in_schema=False)

STYLE = """
:root{color-scheme:dark}*{box-sizing:border-box}
body{margin:0;background:#000;color:#F2F4EC;font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:480px;margin:0 auto;padding:28px 20px 48px}
h1{font-size:26px;line-height:1.15;margin:6px 0 8px}h2{font-size:17px;margin:26px 0 8px}
.eyebrow{font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#A7AC9C}
.muted{color:#A7AC9C;font-size:14px}.card{background:#0E0E0E;border:1px solid #1E1E1E;border-radius:18px;padding:14px 16px;margin:10px 0}
.row{display:flex;gap:12px;align-items:center;justify-content:space-between;padding:10px 0;border-bottom:1px solid #1E1E1E}
.row:last-child{border-bottom:0}.chips{display:flex;gap:8px;flex-wrap:wrap}
.chip{border:1px solid #2A2A2A;background:#121212;color:#F2F4EC;border-radius:999px;padding:9px 16px;font:inherit;font-size:14px}
.chip.on{background:#F2F4EC;color:#000;border-color:#F2F4EC}
button.go{width:100%;min-height:50px;border:0;border-radius:999px;background:#F2F4EC;color:#000;font:600 16px system-ui;margin-top:14px}
button.ghost{width:100%;min-height:46px;border:1px solid #2A2A2A;border-radius:999px;background:transparent;color:#F2F4EC;font:600 15px system-ui;margin-top:10px}
input.code{width:100%;font:600 28px ui-monospace,monospace;letter-spacing:.4em;text-align:center;padding:12px;border-radius:14px;border:1px solid #2A2A2A;background:#161616;color:#F2F4EC}
label.agree{display:flex;gap:10px;align-items:flex-start;margin-top:14px;font-size:14px}
.note{background:#1B1505;border:1px solid rgba(255,194,26,.22);color:#EADFB8;border-radius:14px;padding:12px 14px;font-size:13.5px;margin-top:14px}
.err{color:#FFC21A;font-size:14px;margin-top:10px;min-height:1em}
.switch{width:52px;height:30px;border-radius:999px;border:0;background:#2A2A2A;position:relative;flex:none}
.switch::after{content:"";position:absolute;top:3px;left:3px;width:24px;height:24px;border-radius:50%;background:#A7AC9C;transition:left .15s}
.switch.on{background:#F2F4EC}.switch.on::after{left:25px;background:#000}
a{color:#F2F4EC}
"""

GUARDIAN_JS = r"""
const code = location.pathname.split('/').filter(Boolean).pop();
const api = (p, opt = {}) => fetch('/v1/g/' + code + p, {
  ...opt, headers: {'Content-Type': 'application/json', 'X-Guardian-Session': sessionStorage.getItem('g:' + code) || ''},
}).then(async r => { const j = await r.json().catch(() => ({})); if (!r.ok) throw Object.assign(new Error(j.detail || 'Something went wrong.'), {status: r.status}); return j; });
const $ = (tag, props = {}, ...kids) => { const e = document.createElement(tag); Object.assign(e, props); kids.flat().forEach(k => e.append(k)); return e; };
const root = document.getElementById('app');
const show = (...nodes) => { root.replaceChildren(...nodes); window.scrollTo(0, 0); };
const err = $('div', {className: 'err'});
const WHAT = {post: 'post clips that other players can see', share_card: 'share a link to their player card', search: 'let other players their age find their profile'};

async function start() {
  try { const d = await api(''); d.needsCode ? askCode(d) : page(d); }
  catch (e) { show($('h1', {textContent: "This link doesn't work"}), $('p', {className: 'muted', textContent: e.message})); }
}

function askCode(d) {
  const input = $('input', {className: 'code', inputMode: 'numeric', maxLength: 4, autocomplete: 'one-time-code', placeholder: '••••'});
  const verify = $('button', {className: 'go', textContent: 'Continue', onclick: async () => {
    try { const r = await api('/verify', {method: 'POST', body: JSON.stringify({code: input.value})}); sessionStorage.setItem('g:' + code, r.session); start(); }
    catch (e) { err.textContent = e.message; } }});
  const send = $('button', {className: 'ghost', textContent: 'Text me a code', onclick: async () => {
    try { const r = await api('/code', {method: 'POST'}); err.textContent = 'We sent a code to ' + r.sentTo + '.'; input.focus(); }
    catch (e) { err.textContent = e.message; } }});
  show($('div', {className: 'eyebrow', textContent: 'Tracka · guardian'}),
       $('h1', {textContent: d.childFirstName + ' asked for your OK'}),
       $('p', {className: 'muted', textContent: 'To keep ' + d.childFirstName + ' safe, we check it is you. We will text a 4-digit code to ' + d.phone + '.'}),
       send, $('h2', {textContent: 'Code we texted you'}), input, verify, err);
}

const switchEl = (on, onchange) => $('button', {className: 'switch' + (on ? ' on' : ''), role: 'switch', ariaChecked: String(on), onclick: onchange});

function page(d) {
  const c = d.child, first = c.firstName;
  const account = d.pending.find(p => p.kind === 'account');
  if (account || d.status === 'pending' || d.status === 'expired') return approve(d);
  const nodes = [$('div', {className: 'eyebrow', textContent: 'Guardian page'}), $('h1', {textContent: first + "'s account"}),
    $('p', {className: 'muted', textContent: d.status === 'approved' ? 'Change anything, any time.' : 'You said no, so ' + first + "'s account stays private. Training still works."})];
  for (const p of d.pending) {
    nodes.push($('div', {className: 'card'}, $('div', {className: 'eyebrow', textContent: 'New request'}),
      $('p', {textContent: first + ' is asking to ' + WHAT[p.kind] + '.'}),
      ...(p.kind === 'share_card' && d.card ? [
        $('div', {className: 'muted', textContent: 'People with the link will see: ' + [d.card.shirtName, d.card.positionName, d.card.ageGroup, d.card.region].filter(Boolean).join(', ') + ', measured skills and best times, and the clips ' + first + ' picks.'}),
        $('div', {className: 'muted', textContent: "They won't see: the full name, school or town, or any way to message " + first + '.'})] : []),
      $('button', {className: 'go', textContent: 'Say yes', onclick: () => decide(p.kind, true)}),
      $('button', {className: 'ghost', textContent: 'Say no', onclick: () => decide(p.kind, false)})));
  }
  if (d.status === 'approved') {
    nodes.push($('h2', {textContent: 'What ' + first + ' can do'}), $('div', {className: 'card'},
      ...[['post', 'Post clips', 'Other players can see what ' + first + ' posts'], ['shareCard', 'Share the player card', 'Only people with the link'],
          ['search', 'Show up in search', 'Other players the same age can find the profile']].map(([k, t, s]) =>
        $('div', {className: 'row'}, $('div', {}, $('div', {textContent: t}), $('div', {className: 'muted', textContent: s})),
          switchEl(d.permissions[k], () => decide(k === 'shareCard' ? 'share_card' : k, !d.permissions[k]))))));
  }
  nodes.push($('h2', {textContent: 'Always on'}), $('div', {className: 'card'}, ...d.alwaysOn.map(t => $('div', {className: 'row', textContent: t}))));
  nodes.push($('h2', {textContent: 'Texts to you'}), $('div', {className: 'card'},
    ...[['eachRequest', 'Each new request', 'We ask before anything new'], ['monthlySummary', 'A monthly summary', 'What ' + first + ' trained and posted']].map(([k, t, s]) =>
      $('div', {className: 'row'}, $('div', {}, $('div', {textContent: t}), $('div', {className: 'muted', textContent: s})),
        switchEl(!!d.prefs[k], async () => page(await api('/prefs', {method: 'PATCH', body: JSON.stringify({[k]: !d.prefs[k]})})))))));
  if (d.history.length) nodes.push($('h2', {textContent: "What you've answered"}), $('div', {className: 'card'},
    ...d.history.map(h => $('div', {className: 'row'}, $('span', {textContent: ({account: 'Account', post: 'Posting clips', share_card: 'Sharing the player card', search: 'Showing up in search'})[h.kind] + ': ' + h.status}),
      $('span', {className: 'muted', textContent: new Date(h.decidedAt).toLocaleDateString()})))));
  if (d.status === 'approved') nodes.push($('button', {className: 'ghost', textContent: 'Take back all approvals', onclick: async () => {
    if (confirm('This turns ' + first + "'s account back to private mode. Training stays.")) page(await api('/revoke', {method: 'POST'})); }}));
  nodes.push(err);
  show(...nodes);
}

function approve(d) {
  const c = d.child, first = c.firstName;
  let relation = d.guardian.relation || 'parent';
  const chips = $('div', {className: 'chips'});
  const drawChips = () => chips.replaceChildren(...[['parent', 'Parent'], ['guardian', 'Guardian'], ['coach', 'Coach']].map(([v, t]) =>
    $('button', {className: 'chip' + (relation === v ? ' on' : ''), textContent: t, onclick: () => { relation = v; drawChips(); }})));
  drawChips();
  const agree = $('input', {type: 'checkbox'});
  const list = (items) => $('div', {className: 'card'}, ...items.map(t => $('div', {className: 'row', textContent: t})));
  show($('div', {className: 'eyebrow', textContent: 'Tracka · guardian'}),
    $('h1', {textContent: first + ' wants to use Tracka'}),
    $('p', {className: 'muted', textContent: 'Tracka is a football app. Pep, its coach, gives training plans and tips from the clips ' + first + ' films.'}),
    $('div', {className: 'card'}, $('b', {textContent: c.fullName}), $('div', {className: 'muted', textContent: [c.ageGroup, c.town || c.region].filter(Boolean).join(' · ')})),
    $('h2', {textContent: 'Always private'}), list(['Full name, date of birth and town', 'Clips, until you agree they can be posted', 'No messages from anyone, ever']),
    $('h2', {textContent: 'You decide'}), list(['If ' + first + ' can post clips and share a player card', 'Who can see the profile', 'Anything new we ask about later. We text you each time.']),
    $('h2', {textContent: 'You are ' + first + "'s"}), chips,
    $('label', {className: 'agree'}, agree, $('span', {}, 'I agree to Tracka\'s ', $('a', {href: '/legal/terms', textContent: 'terms'}), ' and ', $('a', {href: '/legal/privacy', textContent: 'privacy policy'}), ' for ' + first + '.')),
    $('div', {className: 'note', textContent: 'Pep is an AI coach. It can get things wrong, it is not a doctor, and its tips are a guide. ' + first + "'s coach comes first."}),
    $('button', {className: 'go', textContent: 'Approve', onclick: () => { if (!agree.checked) { err.textContent = 'Please tick the box to agree first.'; return; } decide('account', true, relation); }}),
    $('button', {className: 'ghost', textContent: 'Not now', onclick: () => decide('account', false)}),
    $('p', {className: 'muted', textContent: "If you don't answer in 7 days, the answer is no."}), err);
}

async function decide(kind, yes, relation) {
  try { page(await api('/decide', {method: 'POST', body: JSON.stringify({kind, yes, relation, agree: true})})); }
  catch (e) { if (e.status === 401) { sessionStorage.removeItem('g:' + code); start(); } else err.textContent = e.message; }
}
start();
"""


def _page(title: str, body: str, script: str = "") -> HTMLResponse:
    html = (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<meta name="robots" content="noindex">'
        f"<title>{title}</title><style>{STYLE}</style></head>"
        f"<body><main>{body}</main>{f'<script>{script}</script>' if script else ''}</body></html>"
    )
    # No caching and no referrer: the link code shouldn't leak to other sites or shared caches.
    return HTMLResponse(html, headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"})


@router.get("/g/{code}")
def guardian_page(code: str) -> HTMLResponse:
    return _page("Tracka · guardian", '<div id="app"><p class="muted">Loading…</p></div>', GUARDIAN_JS)


@router.get("/c/{token}")
def card_page(token: str, req: Request) -> HTMLResponse:
    """A shared player card, as a plain page (it opens from WhatsApp on any phone).
    Built on the server with every value escaped (`html.escape`)."""
    try:
        c = card.public(token, str(req.base_url))
    except HTTPException:
        return _page(
            "Tracka",
            '<h1>This card isn\'t shared any more</h1><p class="muted">Ask the player for a new link.</p>',
        )
    e = lambda v: escape(str(v)) if v is not None else ""  # noqa: E731
    meta = " · ".join(
        e(x) for x in (c["foot"] and f"{c['foot'].title()} foot", c["region"], c["level"], c["ageGroup"]) if x
    )
    rows = [
        f'<div class="eyebrow">Player card</div><h1>{e(c["shirtName"])}{" · " + e(c["shirtNumber"]) if c["shirtNumber"] else ""}</h1>'
    ]
    rows.append(f'<p class="muted">{e(c["positionName"] or "")}<br>{meta}</p>')
    if c["style"]:
        rows.append(f'<div class="card"><div class="eyebrow">Their style</div>{e(c["style"])}</div>')
    if c["pepSees"]:
        rows.append(
            '<div class="card"><div class="eyebrow">Pep sees</div>'
            + " · ".join(e(x) for x in c["pepSees"])
            + "</div>"
        )
    if c["bests"]:
        rows.append(
            '<h2>Measured by Pep</h2><div class="card">'
            + "".join(
                f'<div class="row"><span>{e(b["label"])}</span><b>{e(b["value"])} {e(b["unit"])}</b></div>'
                for b in c["bests"]
            )
            + "</div>"
        )
    if c["skills"]:
        rows.append(
            '<h2>What scouts look for</h2><div class="card">'
            + "".join(
                f'<div class="row"><span>{e(s["name"])}<br><span class="muted">{e(s["average"])}</span></span><b>{e(s["band"])}</b></div>'
                for s in c["skills"]
            )
            + f'</div><p class="muted">Compared with {e(c["comparedWith"])}. Only skills Pep has measured are shown.</p>'
        )
    if c["clips"]:
        rows.append(
            "<h2>Clips</h2>"
            + "".join(
                f'<div class="card"><video controls preload="none" playsinline style="width:100%;border-radius:12px" '
                f'{"poster=" + chr(34) + e(v["thumbnailUrl"]) + chr(34) if v["thumbnailUrl"] else ""} src="{e(v["videoUrl"])}"></video>'
                f'<div class="muted">{e(v["title"])} · {e(v["date"])}</div></div>'
                for v in c["clips"]
            )
        )
    if c["under18"]:
        rows.append(
            '<div class="note">Under 18. Contact goes through the player\'s guardian. No direct messages. Region only, never a home address.</div>'
        )
    rows.append(
        '<p class="muted" style="margin-top:18px">Measured by Tracka from the player\'s own clips. Video measurements can be off, '
        "and Pep's notes come from an AI. Use them as a guide, not a final judgement.</p>"
    )
    return _page("Tracka · player card", "".join(rows))


LEGAL = {
    "terms": "Terms of use",
    "privacy": "Privacy policy",
}


@router.get("/legal/{doc}")
def legal(doc: str) -> HTMLResponse:
    title = LEGAL.get(doc, "Not found")
    return _page(
        f"Tracka · {title}",
        f'<div class="eyebrow">Tracka</div><h1>{title}</h1>'
        '<p class="muted">The full text is being reviewed by a lawyer and will be published here before launch. '
        "In short: Tracka never sells personal data, under-18s need a guardian's approval, only a player's region "
        "is ever shown, and you can delete your account and clips at any time.</p>",
    )
