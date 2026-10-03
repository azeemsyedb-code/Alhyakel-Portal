-- =====================================================================
-- AL HYAKEL PORTAL — EXTRAS
--   1. Stock count by phone (Inventory → Stock count)
--   2. Photo at kiosk check-in / check-out
--   3. Weekly automatic backup (Users & Access → Backups)
--   4. Phone notifications (tables + triggers; see README "Phone notifications")
-- Run in Supabase > SQL Editor after the other SQL files. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. STOCK COUNT
--    A count is a list of {product_id: counted qty}. Admin + storekeeper count,
--    only the inventory admin applies it (stock becomes the counted qty).
-- ---------------------------------------------------------------------
create table if not exists public.inv_counts (
  id          bigint generated always as identity primary key,
  name        text not null,
  category    text,                                   -- null = all products
  status      text not null default 'open' check (status in ('open','applied','cancelled')),
  lines       jsonb not null default '{}'::jsonb,     -- {"<product_id>": {"qty": 12, "by": "<user id>", "at": "<time>"}}
  summary     jsonb,                                  -- what was changed when applied
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  applied_by  uuid,
  applied_at  timestamptz
);
alter table public.inv_counts enable row level security;
drop policy if exists inv_counts_read   on public.inv_counts;
drop policy if exists inv_counts_insert on public.inv_counts;
drop policy if exists inv_counts_update on public.inv_counts;
drop policy if exists inv_counts_delete on public.inv_counts;
create policy inv_counts_read   on public.inv_counts for select to authenticated using (public.my_role('inventory') is not null);
create policy inv_counts_insert on public.inv_counts for insert to authenticated with check (public.my_role('inventory') in ('admin','storekeeper'));
create policy inv_counts_update on public.inv_counts for update to authenticated
  using (public.my_role('inventory') in ('admin','storekeeper') and status = 'open')
  with check (public.my_role('inventory') in ('admin','storekeeper') and status in ('open','cancelled'));
create policy inv_counts_delete on public.inv_counts for delete to authenticated using (public.my_role('inventory') = 'admin');
revoke all on public.inv_counts from anon;

-- record one counted quantity (null = remove it); several people can count at the same time
create or replace function public.inv_count_set(p_count bigint, p_product bigint, p_qty numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if coalesce(public.my_role('inventory'), '') not in ('admin','storekeeper') then raise exception 'You do not have permission to count stock'; end if;
  if p_qty is not null and p_qty < 0 then raise exception 'Counted quantity cannot be negative'; end if;
  update public.inv_counts
     set lines = case when p_qty is null then lines - p_product::text
                      else jsonb_set(lines, array[p_product::text], jsonb_build_object('qty', p_qty, 'by', auth.uid(), 'at', now())) end
   where id = p_count and status = 'open'
  returning lines into v;
  if v is null then raise exception 'This count is closed'; end if;
  return v;
end $$;

-- apply: every counted product gets its stock set to the counted quantity (an ADJUST movement)
create or replace function public.inv_count_apply(p_count bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.inv_counts; r record; v_old numeric; changed jsonb := '[]'::jsonb; n int := 0;
begin
  if coalesce(public.my_role('inventory'), '') <> 'admin' then raise exception 'Only an inventory admin can apply a stock count'; end if;
  select * into c from public.inv_counts where id = p_count for update;
  if not found or c.status <> 'open' then raise exception 'This count is closed'; end if;
  for r in select key::bigint as pid, (value->>'qty')::numeric as q from jsonb_each(c.lines) loop
    select qty into v_old from public.inv_products where id = r.pid;
    if not found then continue; end if;
    n := n + 1;
    if v_old <> r.q then
      perform public.inv_record_movement(r.pid, 'ADJUST', r.q, 'Stock count: ' || c.name, null);
      changed := changed || jsonb_build_object('product_id', r.pid, 'system', v_old, 'counted', r.q, 'diff', r.q - v_old);
    end if;
  end loop;
  update public.inv_counts set status = 'applied', applied_by = auth.uid(), applied_at = now(),
         summary = jsonb_build_object('counted', n, 'changed', changed) where id = p_count;
  return jsonb_build_object('counted', n, 'changed', jsonb_array_length(changed));
end $$;
revoke all on function public.inv_count_set(bigint, bigint, numeric) from public, anon;
revoke all on function public.inv_count_apply(bigint) from public, anon;
grant execute on function public.inv_count_set(bigint, bigint, numeric) to authenticated;
grant execute on function public.inv_count_apply(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- 2. KIOSK PHOTO at check-in / check-out (same as in supabase_setup.sql)
--    The kiosk sends a small photo with the PIN; HR admin and supervisors
--    see it in Attendance. Photos older than 60 days are deleted.
-- ---------------------------------------------------------------------
-- photos the kiosk takes at check-in / check-out (deleted automatically after 60 days)
create table if not exists public.hr_punch_photos (
  id            bigint generated always as identity primary key,
  attendance_id uuid references public.hr_attendance(id) on delete cascade,
  employee_id   uuid references public.hr_employees(id) on delete cascade,
  kind          text not null check (kind in ('in','out')),
  taken_at      timestamptz not null default now(),
  photo         text not null
);
create index if not exists hr_punch_photos_att_idx on public.hr_punch_photos (attendance_id);
alter table public.hr_punch_photos enable row level security;
drop policy if exists hr_punch_photos_read on public.hr_punch_photos;
create policy hr_punch_photos_read on public.hr_punch_photos for select to authenticated using (public.my_role('hr') in ('admin','supervisor'));
revoke all on public.hr_punch_photos from anon;

drop function if exists public.kiosk_punch(uuid, text);
create or replace function public.kiosk_punch(p_employee uuid, p_pin text, p_photo text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  e       public.hr_employees%rowtype;
  a       public.hr_attendance%rowtype;
  v_today date := (now() at time zone 'Asia/Riyadh')::date;
  v_act   text;
  v_tasks json;
  v_att   uuid;
begin
  select * into e from public.hr_employees where id = p_employee and active for update;
  if not found then
    return json_build_object('ok', false, 'error', 'Employee not found');
  end if;
  if e.locked_until is not null and e.locked_until > now() then
    return json_build_object('ok', false, 'error',
      'Too many wrong PINs. Try again after ' || to_char(e.locked_until at time zone 'Asia/Riyadh', 'HH24:MI'));
  end if;
  if e.pin_hash is null or p_pin is null or e.pin_hash is distinct from crypt(p_pin, e.pin_hash) then
    update public.hr_employees
       set failed_attempts = case when failed_attempts + 1 >= 5 then 0 else failed_attempts + 1 end,
           locked_until    = case when failed_attempts + 1 >= 5 then now() + interval '10 minutes' else null end
     where id = e.id;
    return json_build_object('ok', false, 'error', 'Wrong PIN');
  end if;
  update public.hr_employees set failed_attempts = 0, locked_until = null where id = e.id;

  select * into a from public.hr_attendance where employee_id = e.id and work_date = v_today for update;
  if not found then
    insert into public.hr_attendance (employee_id, work_date, status, check_in, source)
    values (e.id, v_today, 'present', now(), 'kiosk');
    v_act := 'in';
  elsif a.check_in is null then
    update public.hr_attendance set check_in = now(), status = 'present', source = 'kiosk' where id = a.id;
    v_act := 'in';
  elsif a.check_out is null then
    if now() - a.check_in < interval '2 minutes' then
      return json_build_object('ok', false, 'error',
        'Already checked in at ' || to_char(a.check_in at time zone 'Asia/Riyadh', 'HH24:MI'));
    end if;
    update public.hr_attendance set check_out = now(), source = 'kiosk' where id = a.id;
    v_act := 'out';
  else
    return json_build_object('ok', false, 'error', 'Already checked out today');
  end if;

  -- photo taken by the kiosk camera (small JPEG), kept for 60 days
  if p_photo is not null and length(p_photo) < 300000 and p_photo like 'data:image/jpeg;base64,%' then
    begin
      select id into v_att from public.hr_attendance where employee_id = e.id and work_date = v_today;
      insert into public.hr_punch_photos (attendance_id, employee_id, kind, photo) values (v_att, e.id, v_act, p_photo);
      delete from public.hr_punch_photos where taken_at < now() - interval '60 days';
    exception when undefined_table then null;
    end;
  end if;

  select coalesce(json_agg(json_build_object('title', t.title, 'details', t.details, 'due', t.due_date,
                                             'priority', t.priority) order by t.due_date nulls last), '[]'::json)
    into v_tasks
    from public.hr_tasks t
   where t.employee_id = e.id and t.status in ('pending','in_progress');

  return json_build_object('ok', true, 'action', v_act, 'name', e.name, 'time', now(), 'tasks', v_tasks);
end $$;
revoke all on function public.kiosk_punch(uuid, text, text) from public;
grant execute on function public.kiosk_punch(uuid, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. WEEKLY AUTOMATIC BACKUP
--    Every Friday night a full copy of the portal's data is saved inside the
--    database (table portal_backups). Portal admins can make one any time and
--    download any copy as Excel / JSON from Users & Access → Backups.
--    Keeps the latest 8 weekly + 5 manual copies. Kiosk PINs are left out.
-- ---------------------------------------------------------------------
create table if not exists public.portal_backups (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('auto','manual')),
  created_at  timestamptz not null default now(),
  created_by  uuid,
  size_bytes  int,
  tables      jsonb,          -- {"docs_documents": 120, …} row counts
  data        jsonb not null
);
alter table public.portal_backups enable row level security;
drop policy if exists portal_backups_read   on public.portal_backups;
drop policy if exists portal_backups_delete on public.portal_backups;
create policy portal_backups_read   on public.portal_backups for select to authenticated using (public.is_portal_admin());
create policy portal_backups_delete on public.portal_backups for delete to authenticated using (public.is_portal_admin());
revoke all on public.portal_backups from anon;

create or replace function public.portal_backup_now(p_kind text default 'manual')
returns bigint language plpgsql security definer set search_path = public as $$
declare
  t text; rows jsonb; d jsonb := '{}'::jsonb; counts jsonb := '{}'::jsonb; v_id bigint;
  tabs text[] := array['portal_users','docs_documents','docs_payments','docs_catalog','inv_suppliers','inv_products','inv_movements','inv_counts',
                       'hr_settings','hr_employees','hr_pay','hr_attendance','hr_tasks','hr_kit','hr_adjustments','hr_advances','hr_payslips','hr_salary_payments'];
begin
  if auth.uid() is not null and not public.is_portal_admin() then raise exception 'Only a portal admin can make a backup'; end if;
  if p_kind not in ('auto','manual') then raise exception 'Unknown backup kind'; end if;
  foreach t in array tabs loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''pin_hash''), ''[]''::jsonb) from public.%I x', t) into rows;
    d := d || jsonb_build_object(t, rows);
    counts := counts || jsonb_build_object(t, jsonb_array_length(rows));
  end loop;
  insert into public.portal_backups (kind, created_by, size_bytes, tables, data)
  values (p_kind, auth.uid(), octet_length(d::text), counts, d) returning id into v_id;
  delete from public.portal_backups b where b.kind = p_kind and b.id not in
    (select id from public.portal_backups where kind = p_kind order by created_at desc limit case when p_kind = 'auto' then 8 else 5 end);
  return v_id;
end $$;
revoke all on function public.portal_backup_now(text) from public, anon;
grant execute on function public.portal_backup_now(text) to authenticated;

-- schedule: every Friday 23:00 Riyadh time (20:00 UTC). Needs the Cron (pg_cron) extension.
do $$
begin
  begin create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    begin create extension if not exists pg_cron; exception when others then null; end;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('portal-weekly-backup', '0 20 * * 5', $c$select public.portal_backup_now('auto')$c$);
  else
    raise notice 'Weekly backup NOT scheduled: turn on Cron in Supabase > Integrations > Cron, then run this file again.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. PHONE NOTIFICATIONS
--    Each phone / computer that turns notifications on is saved in
--    push_subscriptions. The database asks the Edge Function "notify" to send
--    them (via pg_net). The function address and its secret live in
--    app_secrets, which nobody can read through the website.
--    Sends: new document waiting for approval (managers), document approved
--    (its creator), low stock (inventory admin + storekeeper), and a morning
--    summary at 7:30 (overdue invoices, expiring tank certificates, low stock,
--    kit due, overdue tasks).
-- ---------------------------------------------------------------------
do $$ begin create extension if not exists pg_net; exception when others then raise notice 'pg_net not available: %', sqlerrm; end $$;

create table if not exists public.push_subscriptions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references public.portal_users(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  device      text,
  created_at  timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists push_own on public.push_subscriptions;
create policy push_own on public.push_subscriptions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.push_subscriptions from anon;

create table if not exists public.app_secrets (key text primary key, value text not null);
alter table public.app_secrets enable row level security;           -- no policies: not readable from the website
revoke all on public.app_secrets from anon, authenticated;

create table if not exists public.push_log (
  id bigint generated always as identity primary key, created_at timestamptz not null default now(),
  user_ids uuid[], title text, body text, url text, sent boolean
);
alter table public.push_log enable row level security;
drop policy if exists push_log_read on public.push_log;
create policy push_log_read on public.push_log for select to authenticated using (public.is_portal_admin());
revoke all on public.push_log from anon;

-- users who have a role (any role when p_roles is null) in a module
create or replace function public.portal_users_with(p_module text, p_roles text[] default null)
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(id), '{}') from public.portal_users
   where active and case p_module when 'docs' then docs_role when 'inventory' then inv_role when 'hr' then hr_role when 'admin' then case when is_admin then 'admin' end end
         = any(coalesce(p_roles, array['manager','staff','viewer','admin','storekeeper','supervisor']));
$$;

-- queue one notification; never fails the action that triggered it
create or replace function public.portal_push(p_users uuid[], p_title text, p_body text, p_url text default 'index.html', p_tag text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_url text; v_secret text; v_users uuid[]; v_ok boolean := false;
begin
  select array_agg(distinct u) into v_users from unnest(p_users) u where u is not null
     and exists (select 1 from public.push_subscriptions s where s.user_id = u);
  if v_users is null or cardinality(v_users) = 0 then return; end if;
  select value into v_url from public.app_secrets where key = 'notify_url';
  select value into v_secret from public.app_secrets where key = 'notify_secret';
  if v_url is not null and v_secret is not null then
    begin
      execute 'select net.http_post(url := $1, body := $2, headers := $3)'
        using v_url, jsonb_build_object('user_ids', v_users, 'title', p_title, 'body', p_body, 'url', p_url, 'tag', p_tag),
              jsonb_build_object('Content-Type', 'application/json', 'x-notify-secret', v_secret);
      v_ok := true;
    exception when others then v_ok := false;
    end;
  end if;
  insert into public.push_log (user_ids, title, body, url, sent) values (v_users, p_title, p_body, p_url, v_ok);
  delete from public.push_log where id < (select max(id) - 500 from public.push_log);
exception when others then null;
end $$;
revoke all on function public.portal_push(uuid[], text, text, text, text) from public, anon, authenticated;
revoke all on function public.portal_users_with(text, text[]) from public, anon, authenticated;

-- "Send a test" button: only to yourself
create or replace function public.portal_push_test()
returns void language sql security definer set search_path = public as $$
  select public.portal_push(array[auth.uid()], 'Al Hyakel Portal', 'Notifications are working on this device.', 'index.html', 'test');
$$;
revoke all on function public.portal_push_test() from public, anon;
grant execute on function public.portal_push_test() to authenticated;

-- documents: waiting for approval / approved
create or replace function public.docs_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare names jsonb := '{"leak":"Leak Test","tank":"Tank Certificate","quotation":"Quotation","invoice":"Invoice","dn":"Delivery Note","po":"Purchase Order","jobcard":"Job Card","mr":"Material Request","receipt":"Cash Receipt","aramco":"Aramco Inspection Certificate","cow":"Certificate of Origin & Warranty"}';
        nm text := coalesce(names->>new.doc_type, new.doc_type);
begin
  if tg_op = 'INSERT' and new.status = 'draft' then
    perform public.portal_push(array(select u from unnest(public.portal_users_with('docs', array['manager'])) u where u is distinct from new.created_by),
      'Waiting for approval', nm || ' ' || new.doc_no || coalesce(' · ' || new.party_name, ''), 'documents.html#' || new.doc_type || '/' || new.id, 'approve-' || new.id);
  elsif tg_op = 'UPDATE' and new.status = 'approved' and old.status is distinct from 'approved' and new.created_by is distinct from new.approved_by then
    perform public.portal_push(array[new.created_by], 'Approved', nm || ' ' || new.doc_no || ' was approved.', 'documents.html#' || new.doc_type || '/' || new.id, 'approved-' || new.id);
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists docs_notify_trg on public.docs_documents;
create trigger docs_notify_trg after insert or update of status on public.docs_documents for each row execute function public.docs_notify();

-- stock: product just went to or below its minimum
create or replace function public.inv_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare p public.inv_products;
begin
  select * into p from public.inv_products where id = new.product_id;
  if p.min_stock > 0 and new.balance_after <= p.min_stock and (new.balance_after - case when new.type = 'OUT' then -new.qty else new.qty end) > p.min_stock then
    perform public.portal_push(public.portal_users_with('inventory', array['admin','storekeeper']), 'Low stock',
      p.name || ': ' || trim(to_char(new.balance_after, 'FM999999990.###')) || ' ' || p.unit || ' left (minimum ' || trim(to_char(p.min_stock, 'FM999999990.###')) || ')',
      'inventory.html#scan:' || p.sku, 'low-' || p.id);
  end if;
  return null;
exception when others then return null;
end $$;
drop trigger if exists inv_notify_trg on public.inv_movements;
create trigger inv_notify_trg after insert on public.inv_movements for each row execute function public.inv_notify();

-- morning summary for each user, about the parts of the portal they use
create or replace function public.portal_daily_digest()
returns int language plpgsql security definer set search_path = public as $$
declare u record; lines text[]; n int := 0; d date := (now() at time zone 'Asia/Riyadh')::date; v int; s public.hr_settings;
begin
  select * into s from public.hr_settings where id = 1;
  for u in select * from public.portal_users where active and exists (select 1 from public.push_subscriptions ps where ps.user_id = portal_users.id) loop
    lines := '{}';
    if u.docs_role in ('manager','staff') then
      select count(*) into v from public.docs_documents x where x.doc_type = 'invoice' and (x.data->>'due_date') < d::text and (x.data->>'due_date') > '1900'
        and coalesce((x.data->>'grand_total')::numeric, 0) - coalesce((select sum(amount) from public.docs_payments p where p.document_id = x.id), 0) > 0.005;
      if v > 0 then lines := lines || (v || ' overdue invoice' || case when v > 1 then 's' else '' end); end if;
      select count(*) into v from public.docs_documents x where x.doc_type = 'tank' and (x.data->>'valid_until') between d::text and (d + 14)::text;
      if v > 0 then lines := lines || (v || ' tank certificate' || case when v > 1 then 's' else '' end || ' expiring in 14 days'); end if;
      if u.docs_role = 'manager' then
        select count(*) into v from public.docs_documents where status = 'draft';
        if v > 0 then lines := lines || (v || ' waiting for approval'); end if;
      end if;
    end if;
    if u.inv_role in ('admin','storekeeper') then
      select count(*) into v from public.inv_products where min_stock > 0 and qty <= min_stock;
      if v > 0 then lines := lines || (v || ' product' || case when v > 1 then 's' else '' end || ' low on stock'); end if;
    end if;
    if u.hr_role in ('admin','supervisor') then
      select count(*) into v from public.hr_tasks where status in ('pending','in_progress') and due_date < d;
      if v > 0 then lines := lines || (v || ' overdue task' || case when v > 1 then 's' else '' end); end if;
      if to_regclass('public.hr_kit') is not null and exists (select 1 from public.hr_kit where batch is not null) then
        select count(*) into v from public.hr_employees e where e.active and coalesce(
          (select max(issued_on) from public.hr_kit k where k.employee_id = e.id and k.batch is not null) + make_interval(months => coalesce(s.kit_cycle_months, 4)), '1900-01-01'::date) <= d;
        if v > 0 then lines := lines || (v || ' employee' || case when v > 1 then 's' else '' end || ' due for working kit'); end if;
      end if;
    end if;
    if cardinality(lines) > 0 then
      perform public.portal_push(array[u.id], 'Good morning, ' || split_part(coalesce(u.full_name, u.username), ' ', 1), array_to_string(lines, ' · '), 'index.html', 'digest');
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.portal_daily_digest() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('portal-morning-summary', '30 4 * * *', $c$select public.portal_daily_digest()$c$);   -- 7:30 Riyadh
  end if;
end $$;
