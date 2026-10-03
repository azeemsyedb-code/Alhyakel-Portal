-- =====================================================================
-- AL HYAKEL PORTAL — PHASE 2: DOCUMENTS
-- Run this once in Supabase > SQL Editor (after supabase_setup.sql).
-- Safe to re-run.
--
-- Roles (portal_users.docs_role):
--   manager : create, edit, delete
--   staff   : create, edit
--   viewer  : view and download PDFs only
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. One table for every document type.
--    Common columns for search / history, everything else in "data".
--    "files" holds storage paths (photos, QR) for that document.
-- ---------------------------------------------------------------------
create table if not exists public.docs_documents (
  id          uuid primary key default gen_random_uuid(),
  doc_type    text not null check (doc_type in ('leak','tank','quotation','po','dn','invoice','jobcard','mr')),
  doc_no      text not null,
  doc_date    date not null default ((now() at time zone 'Asia/Riyadh')::date),
  party_name  text,                                   -- client / customer / vendor
  data        jsonb not null default '{}'::jsonb,
  files       jsonb not null default '{}'::jsonb,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_by  uuid,
  updated_at  timestamptz,
  unique (doc_type, doc_no)
);
create index if not exists docs_documents_type_date_idx on public.docs_documents (doc_type, doc_date desc);

-- draft / approved (phase 2d)
alter table public.docs_documents add column if not exists status text not null default 'draft';
alter table public.docs_documents add column if not exists approved_by uuid;
alter table public.docs_documents add column if not exists approved_at timestamptz;
-- document types (cash receipt, Aramco inspection and origin & warranty added later)
alter table public.docs_documents drop constraint if exists docs_documents_doc_type_check;
alter table public.docs_documents add constraint docs_documents_doc_type_check
  check (doc_type in ('leak','tank','quotation','po','dn','invoice','jobcard','mr','receipt','aramco','cow'));
alter table public.docs_documents drop constraint if exists docs_documents_status_check;
alter table public.docs_documents add constraint docs_documents_status_check check (status in ('draft','approved'));

-- ---------------------------------------------------------------------
-- 2. Numbers are given by the database, so two people saving at the
--    same moment never get the same number.
--      leak : TS-001, TS-002, ...
--      dn   : AH-2026-001, AH-2026-002, ... (restarts every year)
--      quotation : QT-AL000001, QT-AL000002, ...
--      po   : PO-00001, PO-00002, ...
--      tank : HMI-2026-001, ... (restarts every year)
--      receipt : CR-2026-001, ... (cash receipt, restarts every year)
--      aramco  : AIC-2026-001, ... (Aramco fuel tanker inspection, restarts every year)
--      cow     : COW-2026-001, ... (certificate of origin & warranty, restarts every year)
--      invoice : INV-AL00001, ...
--      jobcard : JC-2026-001, mr : MR-2026-001 (restart every year)
--    A number typed in the form is used as-is (must be unique).
-- ---------------------------------------------------------------------
create or replace function public.docs_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_n    int;
  v_yr   text;
  v_role text := public.my_role('docs');
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
    new.updated_by := null;
    new.updated_at := null;
    new.status := 'draft';                 -- every document starts as a draft
    new.approved_by := null;
    new.approved_at := null;
    if new.doc_no is null or btrim(new.doc_no) = '' then
      perform pg_advisory_xact_lock(hashtext('docs_no_' || new.doc_type));
      if new.doc_type = 'leak' then
        select coalesce(max((regexp_match(doc_no, '^TS-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'leak';
        new.doc_no := 'TS-' || lpad(v_n::text, 3, '0');
      elsif new.doc_type = 'dn' then
        v_yr := to_char(new.doc_date, 'YYYY');
        select coalesce(max((regexp_match(doc_no, '^AH-' || v_yr || '-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'dn';
        new.doc_no := 'AH-' || v_yr || '-' || lpad(v_n::text, 3, '0');
      elsif new.doc_type = 'tank' then
        v_yr := to_char(new.doc_date, 'YYYY');
        select coalesce(max((regexp_match(doc_no, '^HMI-' || v_yr || '-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'tank';
        new.doc_no := 'HMI-' || v_yr || '-' || lpad(v_n::text, 3, '0');
      elsif new.doc_type = 'po' then
        select coalesce(max((regexp_match(doc_no, '^PO-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'po';
        new.doc_no := 'PO-' || lpad(v_n::text, 5, '0');
      elsif new.doc_type = 'invoice' then
        select coalesce(max((regexp_match(doc_no, '^INV-AL(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'invoice';
        new.doc_no := 'INV-AL' || lpad(v_n::text, 5, '0');
      elsif new.doc_type in ('jobcard', 'mr') then
        v_yr := to_char(new.doc_date, 'YYYY');
        select coalesce(max((regexp_match(doc_no, '^' || case new.doc_type when 'jobcard' then 'JC' else 'MR' end || '-' || v_yr || '-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = new.doc_type;
        new.doc_no := case new.doc_type when 'jobcard' then 'JC-' else 'MR-' end || v_yr || '-' || lpad(v_n::text, 3, '0');
      elsif new.doc_type = 'receipt' then
        v_yr := to_char(new.doc_date, 'YYYY');
        select coalesce(max((regexp_match(doc_no, '^CR-' || v_yr || '-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'receipt';
        new.doc_no := 'CR-' || v_yr || '-' || lpad(v_n::text, 3, '0');
      elsif new.doc_type in ('aramco', 'cow') then
        v_yr := to_char(new.doc_date, 'YYYY');
        select coalesce(max((regexp_match(doc_no, '^' || case new.doc_type when 'aramco' then 'AIC' else 'COW' end || '-' || v_yr || '-(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = new.doc_type;
        new.doc_no := case new.doc_type when 'aramco' then 'AIC-' else 'COW-' end || v_yr || '-' || lpad(v_n::text, 3, '0');
      elsif new.doc_type = 'quotation' then
        select coalesce(max((regexp_match(doc_no, '^QT-AL(\d+)$'))[1]::int), 0) + 1 into v_n
          from public.docs_documents where doc_type = 'quotation';
        new.doc_no := 'QT-AL' || lpad(v_n::text, 6, '0');
      else
        select count(*) + 1 into v_n from public.docs_documents where doc_type = new.doc_type;
        new.doc_no := upper(new.doc_type) || '-' || lpad(v_n::text, 3, '0');
      end if;
    end if;
  else
    -- approved documents: only a docs manager may change them (SQL editor / service key is not limited)
    if auth.uid() is not null and old.status = 'approved' and coalesce(v_role, '') <> 'manager' then
      raise exception 'This document is approved. Only a manager can change it.';
    end if;
    if new.status is distinct from old.status then
      if auth.uid() is not null and coalesce(v_role, '') <> 'manager' then
        raise exception 'Only a manager can approve or reopen a document.';
      end if;
      new.approved_by := case when new.status = 'approved' then auth.uid() end;
      new.approved_at := case when new.status = 'approved' then now() end;
    else
      new.approved_by := old.approved_by;
      new.approved_at := old.approved_at;
    end if;
    -- number, type and creator never change after the first save
    new.doc_type   := old.doc_type;
    new.doc_no     := old.doc_no;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_by := auth.uid();
    new.updated_at := now();
  end if;
  return new;
end $$;

drop trigger if exists docs_before_write_trg on public.docs_documents;
create trigger docs_before_write_trg before insert or update on public.docs_documents
  for each row execute function public.docs_before_write();

-- ---------------------------------------------------------------------
-- 3. Who may do what
-- ---------------------------------------------------------------------
alter table public.docs_documents enable row level security;

drop policy if exists docs_read   on public.docs_documents;
drop policy if exists docs_insert on public.docs_documents;
drop policy if exists docs_update on public.docs_documents;
drop policy if exists docs_delete on public.docs_documents;
create policy docs_read   on public.docs_documents for select to authenticated
  using (public.my_role('docs') is not null);
create policy docs_insert on public.docs_documents for insert to authenticated
  with check (public.my_role('docs') in ('manager','staff'));
create policy docs_update on public.docs_documents for update to authenticated
  using (public.my_role('docs') in ('manager','staff')) with check (public.my_role('docs') in ('manager','staff'));
create policy docs_delete on public.docs_documents for delete to authenticated
  using (public.my_role('docs') = 'manager');

revoke all on public.docs_documents from anon;

-- ---------------------------------------------------------------------
-- 4. Private file storage for certificate photos and QR images
--    (bucket "docs", max 5 MB per file; the portal shrinks photos first)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('docs', 'docs', false, 5242880, array['image/jpeg','image/png'])
on conflict (id) do nothing;

drop policy if exists docs_files_read   on storage.objects;
drop policy if exists docs_files_insert on storage.objects;
drop policy if exists docs_files_update on storage.objects;
drop policy if exists docs_files_delete on storage.objects;
create policy docs_files_read on storage.objects for select to authenticated
  using (bucket_id = 'docs' and public.my_role('docs') is not null);
create policy docs_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'docs' and public.my_role('docs') in ('manager','staff'));
create policy docs_files_update on storage.objects for update to authenticated
  using (bucket_id = 'docs' and public.my_role('docs') in ('manager','staff'))
  with check (bucket_id = 'docs' and public.my_role('docs') in ('manager','staff'));
create policy docs_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'docs' and public.my_role('docs') in ('manager','staff'));

-- ---------------------------------------------------------------------
-- 5. Invoice payments (phase 3). One row per payment received.
--    manager + staff record payments; only a manager deletes one.
-- ---------------------------------------------------------------------
create table if not exists public.docs_payments (
  id          uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.docs_documents(id) on delete cascade,
  paid_on     date not null default ((now() at time zone 'Asia/Riyadh')::date),
  amount      numeric(14,2) not null check (amount > 0),
  method      text,
  reference   text,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now()
);
create index if not exists docs_payments_doc_idx on public.docs_payments (document_id);

create or replace function public.docs_payment_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.docs_documents where id = new.document_id and doc_type = 'invoice') then
    raise exception 'Payments can only be recorded on invoices.';
  end if;
  new.created_by := auth.uid();
  new.created_at := now();
  return new;
end $$;
drop trigger if exists docs_payment_check_trg on public.docs_payments;
create trigger docs_payment_check_trg before insert on public.docs_payments
  for each row execute function public.docs_payment_check();

alter table public.docs_payments enable row level security;
drop policy if exists docs_payments_read   on public.docs_payments;
drop policy if exists docs_payments_insert on public.docs_payments;
drop policy if exists docs_payments_delete on public.docs_payments;
create policy docs_payments_read   on public.docs_payments for select to authenticated using (public.my_role('docs') is not null);
create policy docs_payments_insert on public.docs_payments for insert to authenticated with check (public.my_role('docs') in ('manager','staff'));
create policy docs_payments_delete on public.docs_payments for delete to authenticated using (public.my_role('docs') = 'manager');
revoke all on public.docs_payments from anon;
revoke update on public.docs_payments from authenticated;

-- ---------------------------------------------------------------------
-- 6. Price list for quotations / invoices: Category > Sub-category > Product
--    manager + staff add and edit; only a manager deletes.
-- ---------------------------------------------------------------------
create table if not exists public.docs_catalog (
  id          uuid primary key default gen_random_uuid(),
  category    text not null,
  subcategory text not null default '',
  name        text not null,
  description text,
  unit        text,
  rate        numeric(14,2) not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
create index if not exists docs_catalog_cat_idx on public.docs_catalog (category, subcategory, name);
alter table public.docs_catalog enable row level security;
drop policy if exists docs_catalog_read   on public.docs_catalog;
drop policy if exists docs_catalog_insert on public.docs_catalog;
drop policy if exists docs_catalog_update on public.docs_catalog;
drop policy if exists docs_catalog_delete on public.docs_catalog;
create policy docs_catalog_read   on public.docs_catalog for select to authenticated using (public.my_role('docs') is not null);
create policy docs_catalog_insert on public.docs_catalog for insert to authenticated with check (public.my_role('docs') in ('manager','staff'));
create policy docs_catalog_update on public.docs_catalog for update to authenticated
  using (public.my_role('docs') in ('manager','staff')) with check (public.my_role('docs') in ('manager','staff'));
create policy docs_catalog_delete on public.docs_catalog for delete to authenticated using (public.my_role('docs') = 'manager');
revoke all on public.docs_catalog from anon;

-- ---------------------------------------------------------------------
-- 7. Certificate PDFs that the QR code opens (Leak Test, Tank Certificate).
--    Bucket "certs" is PUBLIC: anyone who scans the QR can open that one PDF.
--    File names are long random codes, so PDFs cannot be guessed or listed.
--    Only docs manager / staff can upload; only a manager deletes.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('certs', 'certs', true, 10485760, array['application/pdf'])
on conflict (id) do update set public = true;

drop policy if exists certs_read   on storage.objects;
drop policy if exists certs_insert on storage.objects;
drop policy if exists certs_update on storage.objects;
drop policy if exists certs_delete on storage.objects;
create policy certs_read on storage.objects for select to authenticated
  using (bucket_id = 'certs' and public.my_role('docs') is not null);
create policy certs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'certs' and public.my_role('docs') in ('manager','staff'));
create policy certs_update on storage.objects for update to authenticated
  using (bucket_id = 'certs' and public.my_role('docs') in ('manager','staff'))
  with check (bucket_id = 'certs' and public.my_role('docs') in ('manager','staff'));
create policy certs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'certs' and public.my_role('docs') = 'manager');

-- ---------------------------------------------------------------------
-- 8. Public "Verified" page (verify.html): scanning a certificate's QR shows
--    whether it is genuine and still valid. Only the certificate with that
--    exact (random, unguessable) code is returned, and only a few fields.
-- ---------------------------------------------------------------------
create or replace function public.cert_verify(p_token text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'type', d.doc_type, 'doc_no', d.doc_no, 'doc_date', d.doc_date, 'party_name', d.party_name,
    'approved', d.status = 'approved',
    'valid_until', d.data->>'valid_until', 'result', d.data->>'result',
    'tank_no', d.data->>'tank_no', 'truck_plate', d.data->>'truck_plate', 'serial_no', d.data->>'serial_no',
    'chassis_no', d.data->>'chassis_no', 'tank_serial', d.data->>'tank_serial', 'capacity', coalesce(d.data->>'capacity', d.data->>'tank_capacity'),
    'vehicle_type', d.data->>'vehicle_type', 'delivery_date', d.data->>'delivery_date', 'warranty_until', d.data->>'warranty_until')
  from public.docs_documents d
  where p_token ~ '^[0-9a-f]{32}$' and d.doc_type in ('leak', 'tank', 'aramco', 'cow') and d.files->>'qr_token' = p_token
  limit 1;
$$;
revoke all on function public.cert_verify(text) from public;
grant execute on function public.cert_verify(text) to anon, authenticated;
