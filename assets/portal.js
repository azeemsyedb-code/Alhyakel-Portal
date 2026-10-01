/* Shared by every portal page (except the kiosk):
   - one Supabase client (window.portalSb)
   - checks the login and the user's access for this page
   - draws the top bar: logo, global search, notifications, user menu and the module tabs
   - makes the portal installable on a phone (manifest + service worker)
   Usage: <script src="assets/portal.js" data-module="inv"></script>
          data-module = docs | inv | hr | admin | (empty for the home page)
   Other scripts wait for:  await window.PORTAL_READY   -> PORTAL_CONFIG.user is then filled
   Home page uses:          await window.portalAlerts()  -> counts for the dashboard */
(function () {
  const C = window.PORTAL_CONFIG = window.PORTAL_CONFIG || {};
  C.LOGIN_DOMAIN = C.LOGIN_DOMAIN || 'alhyakel.local';
  C.links = {home: 'index.html', documents: 'documents.html', inventory: 'inventory.html', employees: 'employees.html',
             kiosk: 'kiosk.html', access: 'access.html', logout: 'login.html?logout=1'};
  C.user = null;
  C.DOCS_READY = true;
  const need = (document.currentScript && document.currentScript.dataset.module) || '';
  const never = () => new Promise(() => {});
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  const head = document.head;
  const addHead = (tag, attrs) => { const el = document.createElement(tag); Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, v)); head.appendChild(el); return el; };

  // fonts, shell styles, phone-app bits
  addHead('link', {rel: 'preconnect', href: 'https://fonts.googleapis.com'});
  addHead('link', {rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: ''});
  addHead('link', {rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Sans+Arabic:wght@400;600&display=swap'});
  addHead('link', {rel: 'stylesheet', href: 'assets/shell.css'});
  if (!document.querySelector('link[rel=manifest]')) addHead('link', {rel: 'manifest', href: 'manifest.webmanifest'});
  addHead('meta', {name: 'theme-color', content: '#1D6E80'});
  addHead('link', {rel: 'apple-touch-icon', href: 'assets/icon-192.png'});
  addHead('meta', {name: 'apple-mobile-web-app-capable', content: 'yes'});
  addHead('meta', {name: 'apple-mobile-web-app-title', content: 'Al Hyakel'});
  if ('serviceWorker' in navigator && window.isSecureContext) window.addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));

  if (!C.SUPABASE_URL || /YOUR-PROJECT/.test(C.SUPABASE_URL)) {
    window.PORTAL_READY = never();
    document.addEventListener('DOMContentLoaded', () => document.body.innerHTML =
      '<p style="font:16px system-ui;padding:30px">Setup needed: put the Supabase URL and key in <b>assets/config.js</b>.</p>');
    return;
  }
  const sb = window.portalSb = supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY);

  /* ---------- icons ---------- */
  const P = {
    home: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    doc: '<path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>',
    box: '<path d="M21 8 12 3 3 8v8l9 5 9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>',
    team: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><circle cx="17.5" cy="9" r="2.5"/><path d="M16 14.2a5 5 0 0 1 6 4.8"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9M17 6l3 3"/>',
    check: '<path d="M9 11l3 3 8-8"/><path d="M20 12v7a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h11"/>',
    alert: '<path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17v.5"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/>',
    gate: '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10 21a2 2 0 0 0 4 0"/>',
    cal: '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M3 9h18M8 2v4M16 2v4"/>',
    out: '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l-5-5 5-5M5 12h12"/>',
    task: '<path d="M9 6h11M9 12h11M9 18h11M4 6l1 1 2-2M4 12l1 1 2-2M4 18l1 1 2-2"/>'
  };
  const icon = (k, cls = '') => `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[k] || ''}</svg>`;
  window.portalIcon = icon;
  const COL = {brand: 'var(--ah-brand)', orange: 'var(--ah-orange)', green: 'var(--ah-green)', red: 'var(--ah-red)', blue: 'var(--ah-blue)', purple: 'var(--ah-purple)', amber: 'var(--ah-amber)'};
  window.portalColors = COL;

  const today = () => new Intl.DateTimeFormat('en-CA', {timeZone: 'Asia/Riyadh'}).format(new Date());
  const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
  const DOC_NAMES = {leak: 'Leak Test', tank: 'Tank Certificate', quotation: 'Quotation', invoice: 'Invoice', dn: 'Delivery Note', po: 'Purchase Order', jobcard: 'Job Card', mr: 'Material Request'};
  window.portalDocNames = DOC_NAMES;
  const initials = n => String(n || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase();

  /* ---------- alerts (bell + home dashboard) ---------- */
  let alertsP = null;
  window.portalAlerts = () => alertsP || (alertsP = (async () => {
    const U = C.user, t = today(), groups = [], stats = {};
    const jobs = [];
    if (U.docs_role) {
      if (U.docs_role === 'manager') jobs.push(sb.from('docs_documents').select('id, doc_type, doc_no, party_name', {count: 'exact'})
        .eq('status', 'draft').order('created_at', {ascending: false}).limit(8).then(({data, count}) => {
          stats.approvals = count || 0;
          if (count) groups.push({key: 'approve', title: 'Waiting for approval', color: COL.orange, icon: 'check', count,
            items: (data || []).map(d => ({label: d.doc_no, sub: `${DOC_NAMES[d.doc_type] || d.doc_type} · ${d.party_name || ''}`, href: `documents.html#${d.doc_type}/${d.id}`}))});
        }));
      jobs.push(sb.from('docs_documents').select('id, doc_no, party_name, data').eq('doc_type', 'tank')
        .gte('data->>valid_until', t).lte('data->>valid_until', addDays(t, 30)).limit(30).then(({data}) => {
          const rows = (data || []).sort((a, b) => String(a.data?.valid_until).localeCompare(String(b.data?.valid_until)));
          stats.expiring = rows.length;
          if (rows.length) groups.push({key: 'expiry', title: 'Tank certificates expiring in 30 days', color: COL.blue, icon: 'cal', count: rows.length,
            items: rows.map(d => ({label: d.doc_no, sub: `${d.party_name || ''} · valid until ${d.data?.valid_until}`, href: `documents.html#tank/${d.id}`}))});
        }));
      jobs.push(sb.from('docs_documents').select('id, doc_no, party_name, doc_date, data').eq('doc_type', 'invoice').gte('doc_date', t.slice(0, 7) + '-01')
        .then(({data}) => { stats.invoicedMonth = (data || []).reduce((s, d) => s + (Number(d.data?.grand_total) || 0), 0); }));
      jobs.push(sb.from('docs_documents').select('id, doc_no, party_name, data').eq('doc_type', 'invoice').gt('data->>due_date', '1900').lt('data->>due_date', t).limit(300)
        .then(async ({data}) => {
          const inv = data || []; if (!inv.length) { stats.overdue = 0; return; }
          const {data: pays} = await sb.from('docs_payments').select('document_id, amount').in('document_id', inv.map(d => d.id));
          const paid = {}; (pays || []).forEach(p => paid[p.document_id] = (paid[p.document_id] || 0) + Number(p.amount));
          const rows = inv.map(d => ({...d, bal: (Number(d.data?.grand_total) || 0) - (paid[d.id] || 0)})).filter(d => d.bal > 0.005);
          stats.overdue = rows.length; stats.overdueAmount = rows.reduce((s, d) => s + d.bal, 0);
          if (rows.length) groups.push({key: 'overdue', title: 'Overdue invoices', color: COL.red, icon: 'cash', count: rows.length,
            items: rows.slice(0, 8).map(d => ({label: d.doc_no, sub: `${d.party_name || ''} · SAR ${d.bal.toLocaleString('en-US', {minimumFractionDigits: 2, maximumFractionDigits: 2})} due ${d.data.due_date}`, href: `documents.html#invoice/${d.id}`}))});
        }));
    }
    if (U.inv_role) jobs.push(sb.from('inv_products').select('id, sku, name, qty, min_stock, unit').then(({data}) => {
      const low = (data || []).filter(p => Number(p.min_stock) > 0 && Number(p.qty) <= Number(p.min_stock));
      stats.products = (data || []).length; stats.low = low.length;
      if (low.length) groups.push({key: 'low', title: 'Low stock', color: COL.red, icon: 'alert', count: low.length,
        items: low.slice(0, 8).map(p => ({label: p.name, sub: `${p.sku} · ${p.qty} ${p.unit || ''} left (min ${p.min_stock})`, href: `inventory.html#scan:${encodeURIComponent(p.sku)}`}))});
    }));
    if (U.hr_role) {
      jobs.push(sb.from('hr_tasks').select('id, title, due_date', {count: 'exact'}).in('status', ['pending', 'in_progress']).lt('due_date', t).limit(8)
        .then(({data, count}) => {
          stats.overdueTasks = count || 0;
          if (count) groups.push({key: 'tasks', title: 'Overdue tasks', color: COL.purple, icon: 'task', count,
            items: (data || []).map(x => ({label: x.title, sub: `due ${x.due_date}`, href: 'employees.html#tasks'}))});
        }));
      jobs.push(Promise.all([sb.from('hr_employees').select('id', {count: 'exact', head: true}).eq('active', true),
        sb.from('hr_attendance').select('id', {count: 'exact', head: true}).eq('work_date', t).not('check_in', 'is', null)])
        .then(([e, a]) => { stats.employees = e.count || 0; stats.checkedIn = a.count || 0; }));
    }
    await Promise.allSettled(jobs);
    const order = ['approve', 'overdue', 'low', 'expiry', 'tasks'];
    groups.sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key));
    return {groups, stats, total: groups.reduce((s, g) => s + g.count, 0)};
  })());

  /* ---------- search ---------- */
  async function search(q) {
    const U = C.user, s = q.replace(/[,()%*\\:"]/g, ' ').trim();
    if (s.length < 2) return [];
    const like = `%${s}%`, out = [];
    const jobs = [];
    if (U.docs_role) jobs.push(sb.from('docs_documents').select('id, doc_type, doc_no, party_name, doc_date')
      .or(`doc_no.ilike.${like},party_name.ilike.${like}`).order('created_at', {ascending: false}).limit(8)
      .then(({data}) => (data || []).forEach(d => out.push({g: 'Documents', color: COL.brand, icon: 'doc', label: d.doc_no,
        sub: `${DOC_NAMES[d.doc_type] || d.doc_type} · ${d.party_name || ''}`, href: `documents.html#${d.doc_type}/${d.id}`}))));
    if (U.inv_role) jobs.push(sb.from('inv_products').select('sku, name, qty, unit').or(`sku.ilike.${like},name.ilike.${like}`).limit(6)
      .then(({data}) => (data || []).forEach(p => out.push({g: 'Products', color: COL.orange, icon: 'box', label: p.name,
        sub: `${p.sku} · ${p.qty} ${p.unit || ''} in stock`, href: `inventory.html#scan:${encodeURIComponent(p.sku)}`}))));
    if (U.hr_role) jobs.push(sb.from('hr_employees').select('emp_code, name, designation').or(`name.ilike.${like},emp_code.ilike.${like}`).limit(6)
      .then(({data}) => (data || []).forEach(e => out.push({g: 'Employees', color: COL.green, icon: 'team', label: e.name,
        sub: [e.emp_code, e.designation].filter(Boolean).join(' · '), href: 'employees.html#employees'}))));
    await Promise.allSettled(jobs);
    const order = ['Documents', 'Products', 'Employees'];
    return out.sort((a, b) => order.indexOf(a.g) - order.indexOf(b.g));
  }

  /* ---------- top bar ---------- */
  function drawBar() {
    const U = C.user, L = C.links;
    document.body.classList.add('ah');
    const here = (location.pathname.split('/').pop() || 'index.html');
    const tabs = [['Home', L.home, 'home', true], ['Documents', L.documents, 'doc', !!U.docs_role], ['Inventory', L.inventory, 'box', !!U.inv_role],
                  ['Employees', L.employees, 'team', !!U.hr_role], ['Users & Access', L.access, 'key', U.is_admin]].filter(x => x[3]);
    const roles = [U.docs_role && `Documents: ${U.docs_role}`, U.inv_role && `Inventory: ${U.inv_role}`, U.hr_role && `Employees: ${U.hr_role}`, U.is_admin && 'Portal admin']
      .filter(Boolean).join(' · ');
    const bar = document.createElement('header');
    bar.id = 'ahbar';
    bar.innerHTML = `
      <div class="row1">
        <a class="logo" href="${L.home}"><img src="assets/logo_mark.png" alt=""><span>Al Hyakel Portal</span></a>
        <div class="search" role="search">${icon('search')}
          <input id="ahq" type="search" placeholder="Search documents, products, employees…" autocomplete="off" aria-label="Search the portal" aria-controls="ahres">
          <div class="ahdrop" id="ahres" hidden role="listbox"></div></div>
        <div class="tools">
          <div style="position:relative"><button class="ibtn" id="ahbell" aria-label="Notifications" aria-expanded="false">${icon('bell')}<span class="badge" id="ahbadge" hidden></span></button>
            <div class="ahdrop right" id="ahnotes" hidden></div></div>
          <div style="position:relative"><button class="avatar" id="ahme" aria-label="Account menu" aria-expanded="false">${esc(initials(U.full_name))}</button>
            <div class="ahdrop right" id="ahmenu" hidden>
              <div class="me"><b>${esc(U.full_name)}</b><span>${esc(U.username)}${roles ? ' · ' + esc(roles) : ''}</span></div>
              <a href="${L.home}">${icon('home')}Portal home</a>
              <a href="${L.logout}">${icon('out')}Logout</a></div></div>
        </div>
      </div>
      <nav class="row2 hr" aria-label="Portal">${tabs.map(([t, h, ic]) =>
        `<a href="${h}"${h === here ? ' class="on" aria-current="page"' : ''}>${icon(ic)}${esc(t)}</a>`).join('')}</nav>`;
    document.body.insertBefore(bar, document.body.firstChild);

    const $ = id => document.getElementById(id);
    const drops = [['ahbell', 'ahnotes'], ['ahme', 'ahmenu']];
    const closeAll = except => { drops.forEach(([b, d]) => { if (d !== except) { $(d).hidden = true; $(b).setAttribute('aria-expanded', 'false'); } });
      if (except !== 'ahres') $('ahres').hidden = true; };
    drops.forEach(([b, d]) => $(b).addEventListener('click', e => { e.stopPropagation(); const open = $(d).hidden; closeAll(d); $(d).hidden = !open; $(b).setAttribute('aria-expanded', String(open)); }));
    document.addEventListener('click', e => { if (!bar.contains(e.target)) closeAll(); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape') closeAll(); });

    // notifications
    const notes = $('ahnotes');
    notes.innerHTML = '<div class="none">Loading…</div>';
    window.portalAlerts().then(a => {
      const b = $('ahbadge'); b.textContent = a.total > 99 ? '99+' : a.total; b.hidden = !a.total;
      notes.innerHTML = a.groups.length ? a.groups.map(g => `<h6>${esc(g.title)} (${g.count})</h6>` + g.items.map(i =>
        `<a href="${i.href}"><span class="dot" style="background:${g.color}">${icon(g.icon)}</span><span class="t"><b>${esc(i.label)}</b><span>${esc(i.sub)}</span></span></a>`).join('')).join('')
        : '<div class="none">Sab theek hai. Koi notification nahi.</div>';
    }).catch(() => { notes.innerHTML = '<div class="none">Notifications load nahi hui.</div>'; });

    // search
    const q = $('ahq'), res = $('ahres');
    let timer, seq = 0, sel = -1, results = [];
    const draw = () => {
      if (!results.length) { res.innerHTML = '<div class="none">Kuch nahi mila.</div>'; return; }
      let g = '';
      res.innerHTML = results.map((r, i) => (r.g !== g ? `<h6>${esc(g = r.g)}</h6>` : '') +
        `<a href="${r.href}" class="${i === sel ? 'act' : ''}" role="option"><span class="dot" style="background:${r.color}">${icon(r.icon)}</span><span class="t"><b>${esc(r.label)}</b><span>${esc(r.sub)}</span></span></a>`).join('');
    };
    q.addEventListener('input', () => {
      clearTimeout(timer);
      const v = q.value.trim();
      if (v.length < 2) { res.hidden = true; return; }
      timer = setTimeout(async () => {
        const my = ++seq; closeAll('ahres'); res.hidden = false; res.innerHTML = '<div class="none">Searching…</div>';
        const r = await search(v); if (my !== seq) return;
        results = r; sel = -1; draw();
      }, 250);
    });
    q.addEventListener('keydown', e => {
      if (res.hidden || !results.length) return;
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); sel = (sel + (e.key === 'ArrowDown' ? 1 : -1) + results.length) % results.length; draw(); }
      if (e.key === 'Enter') { e.preventDefault(); location.href = results[Math.max(0, sel)].href; }
    });
    q.addEventListener('focus', () => { if (q.value.trim().length >= 2 && results.length) { res.hidden = false; draw(); } });
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
