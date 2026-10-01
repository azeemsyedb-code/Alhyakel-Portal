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

-- ---------------------------------------------------------------------
-- 2. Numbers are given by the database, so two people saving at the
--    same moment never get the same number.
--      leak : TS-001, TS-002, ...
--      dn   : AH-2026-001, AH-2026-002, ... (restarts every year)
--      quotation : QT-AL000001, QT-AL000002, ...
--    A number typed in the form is used as-is (must be unique).
-- ---------------------------------------------------------------------
create or replace function public.docs_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_n   int;
  v_yr  text;
begin
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.created_at := now();
    new.updated_by := null;
    new.updated_at := null;
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
