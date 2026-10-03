/* Al Hyakel Portal — Data export (portal admins, on the Users & Access page).
   Downloads one Excel file with a sheet per kind of record, for a chosen period.
   It reads with the logged-in user's own permissions, so a section the user has no role in is skipped. */
(() => {
  const sb = window.portalSb, TZ = 'Asia/Riyadh';
  const $ = s => document.querySelector(s);
  const today = () => new Intl.DateTimeFormat('en-CA', {timeZone: TZ}).format(new Date());
  const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
  const riyadh = ts => ts ? new Intl.DateTimeFormat('en-GB', {timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false})
    .format(new Date(ts)).replace(/(\d+)\/(\d+)\/(\d+),?/, '$3-$2-$1') : '';
  const num = v => v === '' || v == null || isNaN(Number(v)) ? (v ?? '') : Number(v);
  const DOC_NAMES = {leak: 'Leak Test', tank: 'Tank Certificate', quotation: 'Quotation', invoice: 'Invoice', dn: 'Delivery Note', po: 'Purchase Order', jobcard: 'Job Card', mr: 'Material Request', receipt: 'Cash Receipt'};
  const human = k => k.replace(/_/g, ' ').replace(/\b\w/, c => c.toUpperCase()).replace(/\bno\b/i, 'No.').replace(/\bvat\b/i, 'VAT');

  const PERIODS = {
    month: () => { const t = today(); return [t.slice(0, 8) + '01', t]; },
    lastmonth: () => { const t = today(), first = t.slice(0, 8) + '01', end = addDays(first, -1); return [end.slice(0, 8) + '01', end]; },
    year: () => { const t = today(); return [t.slice(0, 4) + '-01-01', t]; },
    lastyear: () => { const y = Number(today().slice(0, 4)) - 1; return [`${y}-01-01`, `${y}-12-31`]; },
    all: () => ['', '']
  };

  // read every row (Supabase returns at most 1000 per request)
  async function all(table, cols, filter) {
    const out = [];
    for (let i = 0; ; i += 1000) {
      let q = sb.from(table).select(cols);
      if (filter) q = filter(q);
      const {data, error} = await q.range(i, i + 999);
      if (error) throw error;
      out.push(...data);
      if (data.length < 1000) return out;
    }
  }
  const between = (field, from, to, ts) => q => {
    if (from) q = q.gte(field, ts ? `${from}T00:00:00+03:00` : from);
    if (to) q = ts ? q.lt(field, `${addDays(to, 1)}T00:00:00+03:00`) : q.lte(field, to);
    return q;
  };

  async function build(from, to, mods, say) {
    const sheets = [], notes = [];
    const add = (name, rows) => sheets.push([name, rows]);
    const tryPart = async (label, fn) => { try { say(`Reading ${label}…`); await fn(); } catch (e) { notes.push(`${label}: skipped (${e.message || e})`); } };
    const users = {}; (await sb.from('portal_users').select('id, username, full_name').then(r => r.data || [])).forEach(u => users[u.id] = u.full_name || u.username);
    const who = id => users[id] || '';
    let emps = {};

    if (mods.users) await tryPart('users', async () => {
      const u = await all('portal_users', '*');
      add('Users', u.map(x => ({'User ID': x.username, 'Full name': x.full_name, Documents: x.docs_role || '', Inventory: x.inv_role || '', Employees: x.hr_role || '',
        'Portal admin': x.is_admin ? 'Yes' : '', Active: x.active ? 'Yes' : 'No'})));
    });

    if (mods.docs) {
      let docs = [];
      await tryPart('documents', async () => {
        docs = await all('docs_documents', '*', q => between('doc_date', from, to)(q).order('doc_date').order('doc_no'));
        for (const [type, title] of Object.entries(DOC_NAMES)) {
          const list = docs.filter(d => d.doc_type === type); if (!list.length) continue;
          const keys = [...new Set(list.flatMap(d => Object.keys(d.data || {})))].filter(k => k !== 'items');
          add(title, list.map(d => {
            const row = {'No.': d.doc_no, Date: d.doc_date, [type === 'po' || type === 'mr' ? 'Party' : 'Customer']: d.party_name, Status: d.status};
            keys.forEach(k => { const v = d.data?.[k]; row[human(k)] = v && typeof v === 'object' ? JSON.stringify(v) : num(v); });
            Object.assign(row, {'Created by': who(d.created_by), 'Created at': riyadh(d.created_at), 'Approved by': who(d.approved_by), 'Approved at': riyadh(d.approved_at)});
            return row;
          }));
        }
        const lines = docs.flatMap(d => (d.data?.items || []).map((it, i) => ({Type: DOC_NAMES[d.doc_type], 'Doc No.': d.doc_no, Date: d.doc_date, Party: d.party_name, Line: i + 1,
          ...Object.fromEntries(Object.entries(it).map(([k, v]) => [human(k), num(v)]))})));
        if (lines.length) add('Document lines', lines);
      });
      await tryPart('invoice payments', async () => {
        const pays = await all('docs_payments', '*', q => between('paid_on', from, to)(q).order('paid_on'));
        const byId = Object.fromEntries(docs.map(d => [d.id, d]));
        const missing = [...new Set(pays.map(p => p.document_id).filter(id => !byId[id]))];
        for (let i = 0; i < missing.length; i += 200) (await sb.from('docs_documents').select('id, doc_no, party_name').in('id', missing.slice(i, i + 200)).then(r => r.data || [])).forEach(d => byId[d.id] = d);
        add('Payments', pays.map(p => ({Date: p.paid_on, 'Invoice No.': byId[p.document_id]?.doc_no || '', Customer: byId[p.document_id]?.party_name || '', 'Amount (SAR)': num(p.amount),
          Method: p.method, Reference: p.reference, 'Recorded by': who(p.created_by)})));
      });
      await tryPart('price list', async () => {
        const c = await all('docs_catalog', '*', q => q.order('category').order('subcategory').order('name'));
        add('Price list', c.map(x => ({Category: x.category, 'Sub-category': x.subcategory, Product: x.name, Description: x.description, Unit: x.unit, 'Rate (SAR)': num(x.rate), Active: x.active ? 'Yes' : 'No'})));
      });
    }

    if (mods.inv) {
      let prods = [], sup = {};
      await tryPart('suppliers', async () => {
        const s = await all('inv_suppliers', '*', q => q.order('name')); s.forEach(x => sup[x.id] = x.name);
        add('Suppliers', s.map(x => ({Name: x.name, 'Contact person': x.contact_person, Phone: x.phone, Email: x.email, Notes: x.notes})));
      });
      await tryPart('products', async () => {
        prods = await all('inv_products', '*', q => q.order('sku'));
        add('Products', prods.map(p => ({SKU: p.sku, Product: p.name, Category: p.category, Grade: p.grade, 'Thickness (mm)': num(p.thickness_mm), 'Width (mm)': num(p.width_mm),
          'Length (mm)': num(p.length_mm), Size: p.size, Unit: p.unit, 'In stock': num(p.qty), 'Minimum stock': num(p.min_stock), 'Weight (kg)': num(p.weight_kg), Location: p.location, Supplier: sup[p.supplier_id] || ''})));
      });
      await tryPart('stock movements', async () => {
        const byId = Object.fromEntries(prods.map(p => [p.id, p]));
        const m = await all('inv_movements', '*', q => between('created_at', from, to, true)(q).order('created_at'));
        add('Stock movements', m.map(x => ({'Date & time': riyadh(x.created_at), Type: x.type, SKU: byId[x.product_id]?.sku || '', Product: byId[x.product_id]?.name || '',
          Qty: num(x.qty), Unit: byId[x.product_id]?.unit || '', 'Balance after': num(x.balance_after), Reference: x.reference, Note: x.note, By: who(x.user_id)})));
      });
    }

    if (mods.hr) {
      await tryPart('employees', async () => {
        const e = await all('hr_employees', 'id, emp_code, name, designation, phone, active', q => q.order('emp_code'));
        e.forEach(x => emps[x.id] = x);
        let pay = {}; try { (await all('hr_pay', '*')).forEach(p => pay[p.employee_id] = p); } catch (err) { pay = null; }
        add('Employees', e.map(x => ({Code: x.emp_code, Name: x.name, Designation: x.designation, Phone: x.phone, Active: x.active ? 'Yes' : 'No',
          ...(pay ? {'Basic pay (SAR)': num(pay[x.id]?.basic_pay), 'OT rate (SAR/h)': num(pay[x.id]?.ot_rate)} : {})})));
      });
      const E = id => ({Code: emps[id]?.emp_code || '', Name: emps[id]?.name || ''});
      await tryPart('attendance', async () => {
        const a = await all('hr_attendance', '*', q => between('work_date', from, to)(q).order('work_date'));
        add('Attendance', a.map(x => ({Date: x.work_date, ...E(x.employee_id), Status: x.status, 'Check in': riyadh(x.check_in).slice(11), 'Check out': riyadh(x.check_out).slice(11),
          'OT hours': num(x.ot_hours), Note: x.note, Source: x.source})));
      });
      await tryPart('tasks', async () => {
        const t = await all('hr_tasks', '*', q => between('assigned_on', from, to)(q).order('assigned_on'));
        add('Tasks', t.map(x => ({'Given on': x.assigned_on, ...E(x.employee_id), Task: x.title, Details: x.details, Priority: x.priority, Status: x.status, Due: x.due_date,
          Completed: riyadh(x.completed_at), Paid: x.paid ? 'Yes' : '', 'Payment (SAR)': x.paid ? num(x.amount) : '', Remarks: x.remarks})));
      });
      await tryPart('working kit', async () => {
        const k = await all('hr_kit', '*', q => between('issued_on', from, to)(q).order('issued_on'));
        add('Working kit', k.map(x => ({Issued: x.issued_on, ...E(x.employee_id), Item: x.item, Size: x.size, Qty: num(x.qty), 'Kit round': x.batch || 'single',
          Returned: x.returned_on, Condition: x.return_condition, 'Charge (SAR)': num(x.charge), Note: x.note})));
      });
      await tryPart('deductions & bonuses', async () => {
        const a = await all('hr_adjustments', '*', q => between('adj_date', from, to)(q).order('adj_date'));
        add('Deductions & bonuses', a.map(x => ({Date: x.adj_date, ...E(x.employee_id), Type: x.kind, Reason: x.reason, 'Amount (SAR)': num(x.amount)})));
      });
      await tryPart('advances', async () => {
        const a = await all('hr_advances', '*', q => between('given_on', from, to)(q).order('given_on'));
        add('Advances', a.map(x => ({'Given on': x.given_on, ...E(x.employee_id), 'Amount (SAR)': num(x.amount), 'Monthly installment': num(x.installment), Note: x.note})));
      });
      await tryPart('salary payments', async () => {
        const s = await all('hr_salary_payments', '*', q => between('paid_on', from, to)(q).order('paid_on'));
        add('Salary payments', s.map(x => ({'Paid on': x.paid_on, 'Salary month': x.month, ...E(x.employee_id), 'Amount (SAR)': num(x.amount), Method: x.method, Reference: x.reference, Note: x.note, 'Recorded by': who(x.created_by)})));
      });
      await tryPart('payslips', async () => {
        const s = await all('hr_payslips', '*', q => { if (from) q = q.gte('month', from.slice(0, 7)); if (to) q = q.lte('month', to.slice(0, 7)); return q.order('month'); });
        add('Payslips', s.map(x => { const d = x.data || {}, dd = d.days || {};
          const sum = f => (d.ded || []).filter(f).reduce((a, y) => a + Number(y.amount || 0), 0);
          return {Month: x.month, ...E(x.employee_id), 'Basic (SAR)': num(d.basic), 'Overtime hours': num(d.otHours), 'Gross (SAR)': num(d.gross),
            'Absent deduction': sum(y => y.kind === 'absent'), 'Violations / deductions': sum(y => y.kind === 'violation' || y.kind === 'deduction'), 'Advance recovery': sum(y => y.kind === 'advance'),
            'Total deductions': num(d.totalDed), 'Net pay (SAR)': num(x.net), 'Present days': num(dd.present), 'Absent days': num(dd.absent), 'Half days': num(dd.half), 'Saved at': riyadh(x.created_at)}; }));
      });
    }
    return {sheets, notes};
  }

  function loadXlsx() {
    if (window.XLSX) return Promise.resolve();
    return new Promise((ok, no) => { const s = document.createElement('script'); s.src = 'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js';
      s.onload = ok; s.onerror = () => no(new Error('Could not load the Excel library. Check the internet connection.')); document.head.appendChild(s); });
  }

  function save({sheets, notes}, from, to, me) {
    const wb = XLSX.utils.book_new(), used = new Set();
    const put = (name, rows) => {
      let n = name.replace(/[\\/?*[\]:]/g, ' ').slice(0, 31), i = 2; while (used.has(n)) n = name.slice(0, 28) + ' ' + i++; used.add(n);
      const ws = rows.length ? XLSX.utils.json_to_sheet(rows) : XLSX.utils.aoa_to_sheet([['No records in this period']]);
      if (rows.length) {
        const cols = Object.keys(rows[0]);
        ws['!cols'] = cols.map(c => ({wch: Math.min(60, Math.max(c.length, ...rows.slice(0, 300).map(r => String(r[c] ?? '').length)) + 2)}));
        ws['!autofilter'] = {ref: ws['!ref']};
      }
      XLSX.utils.book_append_sheet(wb, ws, n);
    };
    put('Summary', [
      {Item: 'Company', Value: 'Al Hyakel Metal Industries'},
      {Item: 'Period', Value: from || to ? `${from || 'start'} to ${to || 'today'}` : 'All time'},
      {Item: 'Exported by', Value: me.full_name},
      {Item: 'Exported at', Value: riyadh(new Date().toISOString())},
      ...sheets.map(([n, r]) => ({Item: `Sheet: ${n}`, Value: `${r.length} rows`})),
      ...notes.map(n => ({Item: 'Note', Value: n}))]);
    sheets.forEach(([n, r]) => put(n, r));
    const tag = from || to ? `${from || 'start'}_to_${to || today()}` : `all_${today()}`;
    XLSX.writeFile(wb, `AlHyakel-Portal-export_${tag}.xlsx`, {compression: true});
  }

  /* ---------- backups (weekly automatic + "Back up now") ---------- */
  const TABLE_NAMES = {portal_users: 'Users', docs_documents: 'Documents', docs_payments: 'Payments', docs_catalog: 'Price list', inv_suppliers: 'Suppliers',
    inv_products: 'Products', inv_movements: 'Stock movements', inv_counts: 'Stock counts', hr_settings: 'HR settings', hr_employees: 'Employees', hr_pay: 'Pay',
    hr_attendance: 'Attendance', hr_tasks: 'Tasks', hr_kit: 'Working kit', hr_adjustments: 'Deductions & bonuses', hr_advances: 'Advances', hr_payslips: 'Payslips', hr_salary_payments: 'Salary payments'};
  const kb = n => n > 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB';
  window.portalBackups = async () => {
    const box = $('#backupBox'); if (!box) return;
    const draw = async () => {
      const {data, error} = await sb.from('portal_backups').select('id,kind,created_at,size_bytes,tables').order('created_at', {ascending: false});
      if (error) { box.innerHTML = `<h2>Backups</h2><p class="muted">Backups are not set up yet. Run <b>supabase_extras.sql</b> in Supabase (README).</p>`; return; }
      const fmt = ts => new Intl.DateTimeFormat('en-GB', {timeZone: TZ, dateStyle: 'medium', timeStyle: 'short'}).format(new Date(ts));
      const lastAuto = data.find(b => b.kind === 'auto');
      box.innerHTML = `<h2>Backups</h2>
        <p class="muted" style="margin-top:0">A full copy of the portal's data is saved automatically every Friday night (the latest 8 are kept). ${lastAuto ? `Last automatic backup: <b>${fmt(lastAuto.created_at)}</b>.` : 'No automatic backup yet; it needs Cron turned on in Supabase (README).'}</p>
        <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:12px"><button class="btn" id="b_now">Back up now</button><span class="muted" id="b_status" role="status"></span></div>
        ${data.length ? `<div class="table-wrap" style="box-shadow:none;border:1px solid var(--border)"><table><thead><tr><th>Date</th><th>Type</th><th>Records</th><th>Size</th><th></th></tr></thead><tbody>
          ${data.map(b => `<tr><td>${fmt(b.created_at)}</td><td>${b.kind === 'auto' ? 'Weekly' : 'Manual'}</td><td>${Object.values(b.tables || {}).reduce((a, n) => a + n, 0).toLocaleString('en-US')}</td><td>${kb(b.size_bytes || 0)}</td>
            <td style="white-space:nowrap"><button class="btn sec small" data-xl="${b.id}">Excel</button> <button class="btn sec small" data-js="${b.id}">JSON</button></td></tr>`).join('')}
          </tbody></table></div>` : '<p class="muted">No backups yet.</p>'}`;
      const say = t => { $('#b_status').textContent = t; };
      $('#b_now').onclick = async () => {
        $('#b_now').disabled = true; say('Saving a backup…');
        const {error: e} = await sb.rpc('portal_backup_now', {p_kind: 'manual'});
        if (e) { say('Backup failed: ' + e.message); $('#b_now').disabled = false; return; }
        await draw(); $('#b_status').textContent = 'Backup saved.';
      };
      const get = async id => { const {data: r, error: e} = await sb.from('portal_backups').select('created_at,data').eq('id', Number(id)).single(); if (e) throw e; return r; };
      const stamp = ts => new Intl.DateTimeFormat('en-CA', {timeZone: TZ}).format(new Date(ts));
      box.querySelectorAll('[data-js]').forEach(b => b.onclick = async () => { try { say('Preparing…'); const r = await get(b.dataset.js);
        const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(r.data)], {type: 'application/json'}));
        a.download = `AlHyakel-Portal-backup_${stamp(r.created_at)}.json`; a.click(); say(''); } catch (e) { say('Download failed: ' + e.message); } });
      box.querySelectorAll('[data-xl]').forEach(b => b.onclick = async () => { try { say('Preparing…'); await loadXlsx(); const r = await get(b.dataset.xl);
        const wb = XLSX.utils.book_new();
        Object.entries(r.data).forEach(([t, rows]) => {
          const flat = rows.map(x => Object.fromEntries(Object.entries(x).map(([k, v]) => [k, v && typeof v === 'object' ? JSON.stringify(v) : v])));
          XLSX.utils.book_append_sheet(wb, flat.length ? XLSX.utils.json_to_sheet(flat) : XLSX.utils.aoa_to_sheet([['(empty)']]), (TABLE_NAMES[t] || t).slice(0, 31));
        });
        XLSX.writeFile(wb, `AlHyakel-Portal-backup_${stamp(r.created_at)}.xlsx`, {compression: true}); say(''); } catch (e) { say('Download failed: ' + e.message); } });
    };
    await draw();
  };

  window.portalExport = me => {
    const box = $('#exportBox'); if (!box) return;
    box.innerHTML = `
      <h2>Data export</h2>
      <p class="muted" style="margin-top:0">Download the portal's data as one Excel file, with a separate sheet for each kind of record. Use it for reports, your accountant, or as a monthly backup.</p>
      <div class="form-grid">
        <div class="field"><label for="x_period">Period</label><select id="x_period">
          <option value="month">This month</option><option value="lastmonth">Last month</option><option value="year">This year</option>
          <option value="lastyear">Last year</option><option value="custom">Custom dates</option><option value="all">All time (full backup)</option></select></div>
        <div class="field"><label for="x_from">From</label><input id="x_from" type="date"></div>
        <div class="field"><label for="x_to">To</label><input id="x_to" type="date"></div>
      </div>
      <div class="field"><label>Include</label><div style="display:flex;gap:6px 18px;flex-wrap:wrap">
        <label><input type="checkbox" id="x_docs" checked> Documents, payments &amp; price list</label>
        <label><input type="checkbox" id="x_inv" checked> Inventory</label>
        <label><input type="checkbox" id="x_hr" checked> Employees (attendance, tasks, kit, payroll)</label>
        <label><input type="checkbox" id="x_users"> Users &amp; roles</label></div></div>
      <p class="muted" style="font-size:13px">The period applies to dated records (document date, payment date, attendance day, stock movement time …). Lists such as products, employees and the price list are always exported in full.</p>
      <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap"><button class="btn" id="x_go">Download Excel</button><span class="muted" id="x_status" role="status"></span></div>`;
    const setDates = () => { const p = $('#x_period').value; if (p === 'custom') return; const [f, t] = PERIODS[p](); $('#x_from').value = f; $('#x_to').value = t; };
    setDates();
    $('#x_period').onchange = setDates;
    ['#x_from', '#x_to'].forEach(s => $(s).addEventListener('input', () => { $('#x_period').value = 'custom'; }));
    $('#x_go').onclick = async () => {
      const from = $('#x_from').value, to = $('#x_to').value, say = t => { $('#x_status').textContent = t; };
      const mods = {docs: $('#x_docs').checked, inv: $('#x_inv').checked, hr: $('#x_hr').checked, users: $('#x_users').checked};
      if (!Object.values(mods).some(Boolean)) { say('Tick at least one section.'); return; }
      if (from && to && from > to) { say('"From" must be before "To".'); return; }
      const b = $('#x_go'); b.disabled = true;
      try {
        say('Loading Excel…'); await loadXlsx();
        const res = await build(from, to, mods, say);
        say('Creating file…'); save(res, from, to, me);
        const rows = res.sheets.reduce((a, [, r]) => a + r.length, 0);
        say(`Done: ${rows.toLocaleString('en-US')} rows in ${res.sheets.length} sheets.${res.notes.length ? ' Some parts were skipped, see the Summary sheet.' : ''}`);
      } catch (e) { say('Export failed: ' + (e.message || e)); }
      b.disabled = false;
    };
  };
})();
