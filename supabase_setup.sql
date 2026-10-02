-- =====================================================================
-- AL HYAKEL PORTAL — one Supabase project for the whole portal
-- (Users & Access, Inventory, Employees; Documents tables come in phase 2).
-- Run this whole file once in Supabase > SQL Editor.
-- Safe to re-run.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- =====================================================================
-- 1. USERS & ACCESS
--    Every login is a Supabase Auth user. portal_users says which parts
--    of the portal that user may open, and with which role.
--    NULL role = no access to that part.
-- =====================================================================
create table if not exists public.portal_users (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text not null unique,
  full_name   text,
  is_admin    boolean not null default false,        -- manages users & access
  active      boolean not null default true,
  docs_role   text check (docs_role in ('manager','staff','viewer')),
  inv_role    text check (inv_role  in ('admin','storekeeper','viewer')),
  hr_role     text check (hr_role   in ('admin','supervisor','viewer')),
  created_at  timestamptz not null default now()
);

-- role of the signed-in user for one part of the portal ('docs' | 'inventory' | 'hr')
create or replace function public.my_role(p_module text)
returns text language sql stable security definer set search_path = public as $$
  select case p_module
           when 'docs'      then docs_role
           when 'inventory' then inv_role
           when 'hr'        then hr_role
         end
    from public.portal_users
   where id = auth.uid() and active;
$$;

create or replace function public.is_portal_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.portal_users where id = auth.uid() and active), false);
$$;

alter table public.portal_users enable row level security;
drop policy if exists portal_users_read on public.portal_users;
-- signed-in users can see names (inventory shows who moved stock); changes go through the server only
create policy portal_users_read on public.portal_users
  for select to authenticated using (true);
revoke insert, update, delete on public.portal_users from anon, authenticated;
revoke all on public.portal_users from anon;

revoke all on function public.my_role(text) from public, anon;
revoke all on function public.is_portal_admin() from public, anon;
grant execute on function public.my_role(text) to authenticated;
grant execute on function public.is_portal_admin() to authenticated;

-- =====================================================================
-- 2. INVENTORY
-- =====================================================================
create table if not exists public.inv_suppliers (
  id             bigint generated always as identity primary key,
  name           text not null,
  contact_person text,
  phone          text,
  email          text,
  notes          text,
  created_at     timestamptz not null default now()
);

create table if not exists public.inv_products (
  id           bigint generated always as identity primary key,
  sku          text not null unique,
  name         text not null,
  category     text not null default 'Other',
  grade        text,
  thickness_mm numeric,
  width_mm     numeric,
  length_mm    numeric,
  size         text,
  unit         text not null default 'pcs',
  weight_kg    numeric,
  min_stock    numeric not null default 0,
  location     text,
  supplier_id  bigint references public.inv_suppliers(id) on delete set null,
  qty          numeric not null default 0,         -- changed only by inv_record_movement()
  created_at   timestamptz not null default now()
);

create table if not exists public.inv_movements (
  id            bigint generated always as identity primary key,
  product_id    bigint not null references public.inv_products(id) on delete cascade,
  type          text not null check (type in ('IN','OUT','ADJUST')),
  qty           numeric not null,
  balance_after numeric not null,
  reference     text,
  note          text,
  user_id       uuid default auth.uid(),
  created_at    timestamptz not null default now()
);
create index if not exists inv_movements_product_idx on public.inv_movements (product_id, created_at desc);

-- stock in / out / count. IN & OUT: admin or storekeeper. ADJUST (count): admin only.
create or replace function public.inv_record_movement(p_product_id bigint, p_type text, p_qty numeric,
                                                      p_reference text default null, p_note text default null)
returns numeric language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.my_role('inventory');
  v_old  numeric;
  v_new  numeric;
begin
  if v_role is null or v_role not in ('admin','storekeeper') then
    raise exception 'You do not have permission to change stock';
  end if;
  if p_qty is null then raise exception 'Enter a quantity'; end if;

  select qty into v_old from public.inv_products where id = p_product_id for update;
  if not found then raise exception 'Product not found'; end if;

  if p_type = 'IN' then
    if p_qty <= 0 then raise exception 'Quantity must be more than 0'; end if;
    v_new := v_old + p_qty;
  elsif p_type = 'OUT' then
    if p_qty <= 0 then raise exception 'Quantity must be more than 0'; end if;
    if p_qty > v_old then raise exception 'Not enough stock. Available: %', v_old; end if;
    v_new := v_old - p_qty;
  elsif p_type = 'ADJUST' then
    if v_role <> 'admin' then raise exception 'Only an inventory admin can adjust stock'; end if;
    if p_qty < 0 then raise exception 'Counted quantity cannot be negative'; end if;
    v_new := p_qty;
  else
    raise exception 'Unknown movement type';
  end if;

  update public.inv_products set qty = v_new where id = p_product_id;
  insert into public.inv_movements (product_id, type, qty, balance_after, reference, note, user_id)
  values (p_product_id, p_type, case when p_type = 'ADJUST' then v_new - v_old else p_qty end, v_new,
          nullif(trim(p_reference), ''), nullif(trim(p_note), ''), auth.uid());
  return v_new;
end $$;

-- qty can never be written directly, only through inv_record_movement
create or replace function public.inv_protect_qty()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.qty := 0;
  elsif new.qty is distinct from old.qty and current_user in ('authenticated', 'anon') then
    new.qty := old.qty;
  end if;
  return new;
end $$;
drop trigger if exists inv_protect_qty_trg on public.inv_products;
create trigger inv_protect_qty_trg before insert or update on public.inv_products
  for each row execute function public.inv_protect_qty();

alter table public.inv_suppliers enable row level security;
alter table public.inv_products  enable row level security;
alter table public.inv_movements enable row level security;

drop policy if exists inv_suppliers_read on public.inv_suppliers;
drop policy if exists inv_suppliers_write on public.inv_suppliers;
drop policy if exists inv_suppliers_update on public.inv_suppliers;
drop policy if exists inv_suppliers_delete on public.inv_suppliers;
create policy inv_suppliers_read   on public.inv_suppliers for select to authenticated using (public.my_role('inventory') is not null);
create policy inv_suppliers_write  on public.inv_suppliers for insert to authenticated with check (public.my_role('inventory') in ('admin','storekeeper'));
create policy inv_suppliers_update on public.inv_suppliers for update to authenticated using (public.my_role('inventory') in ('admin','storekeeper')) with check (public.my_role('inventory') in ('admin','storekeeper'));
create policy inv_suppliers_delete on public.inv_suppliers for delete to authenticated using (public.my_role('inventory') = 'admin');

drop policy if exists inv_products_read on public.inv_products;
drop policy if exists inv_products_write on public.inv_products;
drop policy if exists inv_products_update on public.inv_products;
drop policy if exists inv_products_delete on public.inv_products;
create policy inv_products_read   on public.inv_products for select to authenticated using (public.my_role('inventory') is not null);
create policy inv_products_write  on public.inv_products for insert to authenticated with check (public.my_role('inventory') in ('admin','storekeeper'));
create policy inv_products_update on public.inv_products for update to authenticated using (public.my_role('inventory') in ('admin','storekeeper')) with check (public.my_role('inventory') in ('admin','storekeeper'));
create policy inv_products_delete on public.inv_products for delete to authenticated using (public.my_role('inventory') = 'admin');

drop policy if exists inv_movements_read on public.inv_movements;
create policy inv_movements_read on public.inv_movements for select to authenticated using (public.my_role('inventory') is not null);
-- movements are only ever written by inv_record_movement()

revoke all on public.inv_suppliers, public.inv_products, public.inv_movements from anon;
revoke insert, update, delete on public.inv_movements from authenticated;
revoke all on function public.inv_record_movement(bigint, text, numeric, text, text) from public, anon;
grant execute on function public.inv_record_movement(bigint, text, numeric, text, text) to authenticated;

-- =====================================================================
-- 3. EMPLOYEES (attendance, overtime, tasks) + gate kiosk
--    hr admin: everything, incl. pay and kiosk PINs
--    supervisor: employees (without pay), attendance, overtime hours, tasks
--    viewer: read only (without pay)
-- =====================================================================
create table if not exists public.hr_settings (
  id              int primary key default 1 check (id = 1),
  company_name    text not null default 'Alhyakel Metal Industries',
  shift_hours     numeric(4,2)  not null default 8,
  default_ot_rate numeric(10,2) not null default 50
);
insert into public.hr_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.hr_employees (
  id              uuid primary key default gen_random_uuid(),
  emp_code        text not null unique,
  name            text not null,
  designation     text,
  phone           text,
  active          boolean not null default true,
  pin_hash        text,
  pin_set         boolean generated always as (pin_hash is not null) stored,
  failed_attempts int not null default 0,
  locked_until    timestamptz,
  created_at      timestamptz not null default now()
);

-- pay is kept apart so only the HR admin can read it
create table if not exists public.hr_pay (
  employee_id uuid primary key references public.hr_employees(id) on delete cascade,
  basic_pay   numeric(12,2) not null default 0,
  ot_rate     numeric(10,2)                     -- null = default rate
);

create table if not exists public.hr_attendance (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  work_date   date not null,
  status      text not null default 'present' check (status in ('present','half_day','absent','leave','off')),
  check_in    timestamptz,
  check_out   timestamptz,
  ot_hours    numeric(5,2) not null default 0,
  ot_manual   boolean not null default false,
  note        text,
  source      text not null default 'admin' check (source in ('kiosk','admin')),
  updated_at  timestamptz not null default now(),
  unique (employee_id, work_date)
);
create index if not exists hr_attendance_date_idx on public.hr_attendance (work_date);

create table if not exists public.hr_tasks (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid references public.hr_employees(id) on delete set null,
  title        text not null,
  details      text,
  priority     text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status       text not null default 'pending' check (status in ('pending','in_progress','done','cancelled')),
  assigned_on  date not null default ((now() at time zone 'Asia/Riyadh')::date),
  due_date     date,
  completed_at timestamptz,
  remarks      text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists hr_tasks_emp_status_idx on public.hr_tasks (employee_id, status);

create or replace function public.hr_ot_hours(p_in timestamptz, p_out timestamptz)
returns numeric language sql stable security definer set search_path = public as $$
  select case
    when p_in is null or p_out is null or p_out <= p_in then 0
    else greatest(0, floor(((extract(epoch from (p_out - p_in)) / 3600.0) - s.shift_hours) * 2) / 2.0)
  end
  from public.hr_settings s where s.id = 1;
$$;

create or replace function public.hr_attendance_calc()
returns trigger language plpgsql as $$
begin
  if not coalesce(new.ot_manual, false) then
    new.ot_hours := coalesce(public.hr_ot_hours(new.check_in, new.check_out), 0);
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists hr_attendance_calc_trg on public.hr_attendance;
create trigger hr_attendance_calc_trg before insert or update on public.hr_attendance
  for each row execute function public.hr_attendance_calc();

create or replace function public.hr_task_calc()
returns trigger language plpgsql as $$
begin
  if new.status = 'done' then
    if tg_op = 'INSERT' then new.completed_at := now();
    elsif old.status <> 'done' then new.completed_at := now();
    end if;
  else
    new.completed_at := null;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists hr_task_calc_trg on public.hr_tasks;
create trigger hr_task_calc_trg before insert or update on public.hr_tasks
  for each row execute function public.hr_task_calc();

create or replace function public.set_employee_pin(p_employee uuid, p_pin text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if coalesce(public.my_role('hr'), '') <> 'admin' then
    raise exception 'Only the HR admin can set PINs';
  end if;
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'PIN must be 4 to 6 digits';
  end if;
  update public.hr_employees
     set pin_hash = crypt(p_pin, gen_salt('bf')), failed_attempts = 0, locked_until = null
   where id = p_employee;
end $$;

create or replace function public.kiosk_employees()
returns table (id uuid, emp_code text, name text, state text)
language sql stable security definer set search_path = public as $$
  select e.id, e.emp_code, e.name,
         case when a.check_out is not null then 'done'
              when a.check_in  is not null then 'in'
              else 'out' end
    from public.hr_employees e
    left join public.hr_attendance a
      on a.employee_id = e.id and a.work_date = (now() at time zone 'Asia/Riyadh')::date
   where e.active and e.pin_hash is not null
   order by e.emp_code;
$$;

create or replace function public.kiosk_punch(p_employee uuid, p_pin text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  e       public.hr_employees%rowtype;
  a       public.hr_attendance%rowtype;
  v_today date := (now() at time zone 'Asia/Riyadh')::date;
  v_act   text;
  v_tasks json;
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

  select coalesce(json_agg(json_build_object('title', t.title, 'details', t.details, 'due', t.due_date,
                                             'priority', t.priority) order by t.due_date nulls last), '[]'::json)
    into v_tasks
    from public.hr_tasks t
   where t.employee_id = e.id and t.status in ('pending','in_progress');

  return json_build_object('ok', true, 'action', v_act, 'name', e.name, 'time', now(), 'tasks', v_tasks);
end $$;

alter table public.hr_settings   enable row level security;
alter table public.hr_employees  enable row level security;
alter table public.hr_pay        enable row level security;
alter table public.hr_attendance enable row level security;
alter table public.hr_tasks      enable row level security;

drop policy if exists hr_settings_read   on public.hr_settings;
drop policy if exists hr_settings_write  on public.hr_settings;
create policy hr_settings_read  on public.hr_settings for select to authenticated using (public.my_role('hr') is not null);
create policy hr_settings_write on public.hr_settings for update to authenticated using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');

drop policy if exists hr_employees_read   on public.hr_employees;
drop policy if exists hr_employees_insert on public.hr_employees;
drop policy if exists hr_employees_update on public.hr_employees;
drop policy if exists hr_employees_delete on public.hr_employees;
create policy hr_employees_read   on public.hr_employees for select to authenticated using (public.my_role('hr') is not null);
create policy hr_employees_insert on public.hr_employees for insert to authenticated with check (public.my_role('hr') = 'admin');
create policy hr_employees_update on public.hr_employees for update to authenticated using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');
create policy hr_employees_delete on public.hr_employees for delete to authenticated using (public.my_role('hr') = 'admin');

drop policy if exists hr_pay_admin on public.hr_pay;
create policy hr_pay_admin on public.hr_pay for all to authenticated
  using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');

drop policy if exists hr_attendance_read  on public.hr_attendance;
drop policy if exists hr_attendance_write on public.hr_attendance;
create policy hr_attendance_read  on public.hr_attendance for select to authenticated using (public.my_role('hr') is not null);
create policy hr_attendance_write on public.hr_attendance for all to authenticated
  using (public.my_role('hr') in ('admin','supervisor')) with check (public.my_role('hr') in ('admin','supervisor'));

drop policy if exists hr_tasks_read  on public.hr_tasks;
drop policy if exists hr_tasks_write on public.hr_tasks;
create policy hr_tasks_read  on public.hr_tasks for select to authenticated using (public.my_role('hr') is not null);
create policy hr_tasks_write on public.hr_tasks for all to authenticated
  using (public.my_role('hr') in ('admin','supervisor')) with check (public.my_role('hr') in ('admin','supervisor'));

revoke all on public.hr_settings, public.hr_employees, public.hr_pay, public.hr_attendance, public.hr_tasks from anon;

-- PIN hash and lockout columns are never readable or writable through the API
revoke all on public.hr_employees from authenticated;
grant select (id, emp_code, name, designation, phone, active, pin_set, created_at) on public.hr_employees to authenticated;
grant insert (emp_code, name, designation, phone, active) on public.hr_employees to authenticated;
grant update (emp_code, name, designation, phone, active) on public.hr_employees to authenticated;
grant delete on public.hr_employees to authenticated;

revoke all on function public.hr_ot_hours(timestamptz, timestamptz) from public, anon;
revoke all on function public.set_employee_pin(uuid, text)   from public, anon;
revoke all on function public.kiosk_employees()              from public;
revoke all on function public.kiosk_punch(uuid, text)        from public;
grant execute on function public.hr_ot_hours(timestamptz, timestamptz) to authenticated;
grant execute on function public.set_employee_pin(uuid, text)   to authenticated;
grant execute on function public.kiosk_employees()              to anon, authenticated;
grant execute on function public.kiosk_punch(uuid, text)        to anon, authenticated;

-- starting employee list (from the salary Excel). Safe to re-run.
insert into public.hr_employees (emp_code, name) values
  ('EMP-01','Sajid'),   ('EMP-02','Khaliq'),  ('EMP-03','Waseem'),   ('EMP-04','Ahsan'),
  ('EMP-05','Shareef'), ('EMP-06','Madni'),   ('EMP-07','Shehroze'), ('EMP-08','Qasim'),
  ('EMP-09','Shakir'),  ('EMP-10','Rakib'),   ('EMP-11','Malik'),    ('EMP-12','Khalid'),
  ('EMP-13','Nasir'),   ('EMP-14','Faisal'),  ('EMP-15','Yasir'),    ('EMP-16','Arfat'),
  ('EMP-17','Muzammil'),('EMP-18','Naheed'),  ('EMP-19','Wazeer'),   ('EMP-20','Owais'),
  ('EMP-21','Bilal'),   ('EMP-22','Burhan'),  ('EMP-23','Ibrahim')
on conflict (emp_code) do nothing;
insert into public.hr_pay (employee_id) select id from public.hr_employees on conflict do nothing;
