-- =====================================================================
-- AL HYAKEL PORTAL — EMPLOYEES: working kit, paid tasks, deductions /
-- violations, advances and monthly payslips.
-- Run once in Supabase > SQL Editor (after supabase_setup.sql). Safe to re-run.
--
--   working kit       : hr admin + supervisor record; everyone in Employees can see
--   pay items          : hr admin only (deductions, violations, bonuses, advances, payslips)
-- =====================================================================

-- tasks can carry a payment, added to salary when the task is done
alter table public.hr_tasks add column if not exists paid   boolean not null default false;
alter table public.hr_tasks add column if not exists amount numeric(10,2) not null default 0;

-- ---------- working kit (helmets, shoes, tools …) ----------
create table if not exists public.hr_kit (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references public.hr_employees(id) on delete cascade,
  item             text not null,
  size             text,
  qty              numeric(10,2) not null default 1 check (qty > 0),
  issued_on        date not null default ((now() at time zone 'Asia/Riyadh')::date),
  returned_on      date,
  return_condition text check (return_condition in ('good','damaged','lost')),
  charge           numeric(10,2) not null default 0,     -- amount charged for damage / loss
  note             text,
  created_by       uuid default auth.uid(),
  created_at       timestamptz not null default now()
);
create index if not exists hr_kit_emp_idx on public.hr_kit (employee_id, issued_on);

-- ---------- deductions, violations and bonuses ----------
create table if not exists public.hr_adjustments (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  adj_date    date not null default ((now() at time zone 'Asia/Riyadh')::date),
  kind        text not null check (kind in ('violation','deduction','bonus')),
  amount      numeric(10,2) not null default 0 check (amount >= 0),
  reason      text not null,
  kit_id      uuid references public.hr_kit(id) on delete set null,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists hr_adj_emp_idx on public.hr_adjustments (employee_id, adj_date);

-- ---------- salary advances / loans, recovered in monthly installments ----------
create table if not exists public.hr_advances (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  given_on    date not null default ((now() at time zone 'Asia/Riyadh')::date),
  amount      numeric(10,2) not null check (amount > 0),
  installment numeric(10,2) not null check (installment > 0),
  note        text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);

-- ---------- saved payslips (one per employee per month) ----------
create table if not exists public.hr_payslips (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  month       text not null check (month ~ '^\d{4}-\d{2}$'),
  data        jsonb not null,          -- every line of the payslip as it was saved
  net         numeric(12,2) not null,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  unique (employee_id, month)
);

alter table public.hr_kit         enable row level security;
alter table public.hr_adjustments enable row level security;
alter table public.hr_advances    enable row level security;
alter table public.hr_payslips    enable row level security;

drop policy if exists hr_kit_read   on public.hr_kit;
drop policy if exists hr_kit_insert on public.hr_kit;
drop policy if exists hr_kit_update on public.hr_kit;
drop policy if exists hr_kit_delete on public.hr_kit;
create policy hr_kit_read   on public.hr_kit for select to authenticated using (public.my_role('hr') is not null);
create policy hr_kit_insert on public.hr_kit for insert to authenticated with check (public.my_role('hr') in ('admin','supervisor'));
create policy hr_kit_update on public.hr_kit for update to authenticated
  using (public.my_role('hr') in ('admin','supervisor')) with check (public.my_role('hr') in ('admin','supervisor'));
create policy hr_kit_delete on public.hr_kit for delete to authenticated using (public.my_role('hr') in ('admin','supervisor'));   -- undo a wrong entry

drop policy if exists hr_adj_admin  on public.hr_adjustments;
drop policy if exists hr_adv_admin  on public.hr_advances;
drop policy if exists hr_slip_admin on public.hr_payslips;
create policy hr_adj_admin  on public.hr_adjustments for all to authenticated using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');
create policy hr_adv_admin  on public.hr_advances    for all to authenticated using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');
create policy hr_slip_admin on public.hr_payslips    for all to authenticated using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');

revoke all on public.hr_kit, public.hr_adjustments, public.hr_advances, public.hr_payslips from anon;

-- only the HR admin may set a task's payment
create or replace function public.hr_task_pay_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and coalesce(public.my_role('hr'), '') <> 'admin' then
    if tg_op = 'INSERT' then
      new.paid := false; new.amount := 0;
    else
      new.paid := old.paid; new.amount := old.amount;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists hr_task_pay_guard_trg on public.hr_tasks;
create trigger hr_task_pay_guard_trg before insert or update on public.hr_tasks
  for each row execute function public.hr_task_pay_guard();

-- ---------- kit rounds: a standard kit given to everyone every few months ----------
-- batch = the kit round (e.g. KIT-2026-10); 'replaced' = old item taken back when the new kit was given
alter table public.hr_kit add column if not exists batch text;
create index if not exists hr_kit_batch_idx on public.hr_kit (batch);
alter table public.hr_kit drop constraint if exists hr_kit_return_condition_check;
alter table public.hr_kit add constraint hr_kit_return_condition_check
  check (return_condition in ('good','damaged','lost','replaced'));

-- how often a new kit is due (months) and what the standard kit contains
alter table public.hr_settings add column if not exists kit_cycle_months int not null default 4;
alter table public.hr_settings drop constraint if exists hr_settings_kit_cycle_check;
alter table public.hr_settings add constraint hr_settings_kit_cycle_check check (kit_cycle_months between 1 and 12);
alter table public.hr_settings add column if not exists kit_template jsonb not null default
  '[{"item":"Coverall","qty":2},{"item":"Safety shoes","qty":1},{"item":"Safety helmet","qty":1},{"item":"Safety goggles","qty":1},{"item":"Welding gloves","qty":2},{"item":"Cotton gloves","qty":6},{"item":"Ear plugs","qty":2},{"item":"Dust mask","qty":4}]'::jsonb;

-- ---------- weekly off day (Friday) ----------
-- off_day: 0 = Sunday … 5 = Friday … 6 = Saturday, null = no weekly off day.
-- On the off day every hour worked is overtime (not just the hours above the shift),
-- paid at the employee's own overtime rate x offday_ot_multiplier (2 by default).
alter table public.hr_settings add column if not exists off_day int default 5;
alter table public.hr_settings add column if not exists offday_ot_rate numeric(10,2);
-- off-day overtime = each employee's own overtime rate x this multiplier (default 2 = double)
alter table public.hr_settings add column if not exists offday_ot_multiplier numeric(4,2) not null default 2;
alter table public.hr_settings drop constraint if exists hr_settings_offday_mult_check;
alter table public.hr_settings add constraint hr_settings_offday_mult_check check (offday_ot_multiplier between 1 and 5);
alter table public.hr_settings drop constraint if exists hr_settings_off_day_check;
alter table public.hr_settings add constraint hr_settings_off_day_check check (off_day is null or off_day between 0 and 6);

create or replace function public.hr_attendance_calc()
returns trigger language plpgsql as $$
declare s public.hr_settings;
begin
  if not coalesce(new.ot_manual, false) then
    select * into s from public.hr_settings where id = 1;
    if s.off_day is not null and extract(dow from new.work_date) = s.off_day then
      new.ot_hours := case when new.check_in is null or new.check_out is null or new.check_out <= new.check_in then 0
                           else floor((extract(epoch from (new.check_out - new.check_in)) / 3600.0) * 2) / 2.0 end;
    else
      new.ot_hours := coalesce(public.hr_ot_hours(new.check_in, new.check_out), 0);
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- ---------- salary payments (part payments during the month are allowed) ----------
create table if not exists public.hr_salary_payments (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  month       text not null check (month ~ '^\d{4}-\d{2}$'),      -- the salary month this payment is for
  paid_on     date not null default ((now() at time zone 'Asia/Riyadh')::date),
  amount      numeric(12,2) not null check (amount > 0),
  method      text not null default 'Cash' check (method in ('Cash','Bank transfer','Cheque')),
  reference   text,
  note        text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists hr_salpay_month_idx on public.hr_salary_payments (month, employee_id);
alter table public.hr_salary_payments enable row level security;
drop policy if exists hr_salpay_admin on public.hr_salary_payments;
create policy hr_salpay_admin on public.hr_salary_payments for all to authenticated using (public.my_role('hr') = 'admin') with check (public.my_role('hr') = 'admin');
revoke all on public.hr_salary_payments from anon;
