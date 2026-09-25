/* Shared by every portal page (except the kiosk):
   - one Supabase client (window.portalSb)
   - checks the login and the user's access for this page
   - draws the portal bar (links to the parts this user may open + Logout)
   Usage: <script src="assets/portal.js" data-module="inv"></script>
          data-module = docs | inv | hr | admin | (empty for the home page)
   Other scripts wait for:  await window.PORTAL_READY   -> PORTAL_CONFIG.user is then filled */
(function () {
  const C = window.PORTAL_CONFIG = window.PORTAL_CONFIG || {};
  C.LOGIN_DOMAIN = C.LOGIN_DOMAIN || 'alhyakel.local';
  C.links = {home: 'index.html', documents: 'documents.html', inventory: 'inventory.html', employees: 'employees.html',
             kiosk: 'kiosk.html', access: 'access.html', logout: 'login.html?logout=1'};
  C.user = null;
  C.DOCS_READY = false;   // Documents part arrives in phase 2
  const need = (document.currentScript && document.currentScript.dataset.module) || '';
  const never = () => new Promise(() => {});
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));

  if (!C.SUPABASE_URL || /YOUR-PROJECT/.test(C.SUPABASE_URL)) {
    window.PORTAL_READY = never();
    document.addEventListener('DOMContentLoaded', () => document.body.innerHTML =
      '<p style="font:16px system-ui;padding:30px">Setup needed: put the Supabase URL and key in <b>assets/config.js</b>.</p>');
    return;
  }
  const sb = window.portalSb = supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY);

  function drawBar() {
    const U = C.user, L = C.links;
    const here = (location.pathname.split('/').pop() || 'index.html');
    const items = [['Portal', L.home, true], ['Documents', L.documents, !!U.docs_role && C.DOCS_READY],
                   ['Inventory', L.inventory, !!U.inv_role], ['Employees', L.employees, !!U.hr_role],
                   ['Users & Access', L.access, U.is_admin]].filter(x => x[2]);
    const st = document.createElement('style');
    st.textContent = `#portalbar{background:#0d5c63;color:#fff;display:flex;align-items:center;gap:14px;padding:6px 14px;
      padding-top:calc(6px + env(safe-area-inset-top,0px));font:500 14px/1.3 "Segoe UI",Tahoma,Arial,sans-serif;
      border-bottom:3px solid #e8792e;flex-wrap:wrap;position:relative;z-index:50}
      #portalbar b{font-weight:700;margin-right:6px;white-space:nowrap}
      #portalbar .pnav{display:flex;gap:4px;flex-wrap:wrap;flex:1}
      #portalbar .pnav a{color:#fff!important;text-decoration:none;padding:3px 9px!important;border-radius:3px;opacity:.85;
        display:inline-block!important;margin:0!important;box-shadow:none!important;font-weight:500}
      #portalbar .pnav a:hover{opacity:1;background:rgba(255,255,255,.12)}
      #portalbar .pnav a.on{opacity:1;background:rgba(255,255,255,.2)!important;font-weight:700}
      #portalbar .who{opacity:.85;white-space:nowrap}
      #portalbar .out{color:#fff;border:1px solid rgba(255,255,255,.5);border-radius:3px;padding:2px 9px;text-decoration:none;white-space:nowrap}`;
    document.head.appendChild(st);
    const bar = document.createElement('div');
    bar.id = 'portalbar';
    bar.innerHTML = `<b>Al Hyakel Portal</b><div class="pnav" role="navigation" aria-label="Portal">${items.map(([t, h]) =>
      `<a href="${h}"${h === here ? ' class="on" aria-current="page"' : ''}>${esc(t)}</a>`).join('')}</div>
      <span class="who">${esc(U.full_name)}</span><a class="out" href="${L.logout}">Logout</a>`;
    document.body.insertBefore(bar, document.body.firstChild);
  }

  window.PORTAL_READY = (async () => {
    const {data: {session}} = await sb.auth.getSession();
    const here = (location.pathname.split('/').pop() || 'index.html') + location.hash;
    if (!session) { location.replace('login.html?next=' + encodeURIComponent(here)); return never(); }
    const {data: me, error} = await sb.from('portal_users').select('*').eq('id', session.user.id).maybeSingle();
    if (error) {
      document.addEventListener('DOMContentLoaded', () => document.body.insertAdjacentHTML('afterbegin',
        `<p style="background:#b3261e;color:#fff;padding:10px;margin:0">Database error: ${esc(error.message)}</p>`));
      return never();
    }
    if (!me || !me.active) { await sb.auth.signOut(); location.replace('login.html?msg=' + (me ? 'blocked' : 'notadded')); return never(); }
    C.user = {id: me.id, username: me.username, full_name: me.full_name || me.username, is_admin: !!me.is_admin,
              docs_role: me.docs_role, inv_role: me.inv_role, hr_role: me.hr_role};
    const allowed = !need || (need === 'admin' ? me.is_admin : !!me[need + '_role']);
    if (!allowed) { location.replace('index.html?denied=' + need); return never(); }
    if (document.readyState === 'loading') await new Promise(r => document.addEventListener('DOMContentLoaded', r));
    drawBar();
    return C.user;
  })();

  sb.auth.onAuthStateChange(ev => { if (ev === 'SIGNED_OUT' && !/login\.html/.test(location.pathname)) location.replace('login.html'); });
})();
