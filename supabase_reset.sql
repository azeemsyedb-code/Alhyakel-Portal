-- =====================================================================
-- AL HYAKEL PORTAL — FRESH START
-- Deletes ALL business data so you can start clean, and loads the new
-- employee list. Run once in Supabase > SQL Editor. CANNOT BE UNDONE.
--
-- Deleted : documents (all 8 types), invoice payments, price list,
--           inventory products / suppliers / stock movements,
--           employees + attendance, overtime, tasks, pay, working kit,
--           deductions, advances, payslips
-- Kept    : logins (Users & Access), roles, HR settings (shift hours,
--           overtime rate, standard kit), backups, notification devices
-- Numbering starts again from 1 (TS-001, QT-AL000001, INV-AL00001 …)
--
-- Photos and certificate PDFs live in Storage, not in these tables:
-- delete them in Supabase > Storage (buckets "docs" and "certs").
-- =====================================================================
begin;

truncate table
  public.docs_payments, public.docs_documents, public.docs_catalog,
  public.inv_movements, public.inv_products, public.inv_suppliers,
  public.hr_payslips, public.hr_adjustments, public.hr_advances, public.hr_kit,
  public.hr_tasks, public.hr_attendance, public.hr_pay, public.hr_employees
restart identity cascade;

-- tables from supabase_extras.sql (only if that file has been run); backups are kept on purpose
do $$ begin
  if to_regclass('public.inv_counts') is not null then truncate table public.inv_counts restart identity; end if;
  if to_regclass('public.hr_punch_photos') is not null then truncate table public.hr_punch_photos restart identity; end if;
  if to_regclass('public.push_log') is not null then truncate table public.push_log restart identity; end if;
end $$;

insert into public.hr_employees (emp_code, name) values
  ('EMP-01','Sajid'),   ('EMP-02','Khaliq'),  ('EMP-03','Waseem'),   ('EMP-04','Ahsan'),
  ('EMP-05','Shareef'), ('EMP-06','Madni'),   ('EMP-07','Shehroze'), ('EMP-08','Qasim'),
  ('EMP-09','Shakir'),  ('EMP-10','Rakib'),   ('EMP-11','Malik'),    ('EMP-12','Khalid'),
  ('EMP-13','Nasir'),   ('EMP-14','Faisal'),  ('EMP-15','Yasir'),    ('EMP-16','Arfat'),
  ('EMP-17','Muzammil'),('EMP-18','Naheed'),  ('EMP-19','Wazeer'),   ('EMP-20','Owais'),
  ('EMP-21','Bilal'),   ('EMP-22','Burhan'),  ('EMP-23','Ibrahim');
insert into public.hr_pay (employee_id) select id from public.hr_employees on conflict do nothing;

commit;

-- quick check: should show 23 employees and 0 documents
select (select count(*) from public.hr_employees) as employees,
       (select count(*) from public.docs_documents) as documents,
       (select count(*) from public.inv_products)   as products;
