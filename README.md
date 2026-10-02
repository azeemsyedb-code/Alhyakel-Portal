# Al Hyakel Portal — Supabase + GitHub Pages

One link, one login. Each user sees only the sections they have been given access to.
No server needed: the website runs on **GitHub Pages**, and all data and logins live in **Supabase** (just like the inventory portal).

| Section | What it is | Roles |
|---|---|---|
| **Inventory** | Stock in / out, barcode scan, products, suppliers, low-stock alerts | admin · storekeeper · viewer |
| **Employees** | Attendance, overtime, tasks, salary | admin · supervisor · viewer |
| **Gate kiosk** | Employees check in / check out with a PIN (no login) | — |
| **Users & Access** | Create users, change passwords, grant / remove access | portal admin |
| **Documents** | Leak Test (TS-001), Tank Certificate (HMI-2026-001, English + Arabic), Quotation (QT-AL000001), Invoice (INV-AL00001, ZATCA QR), Delivery Note (AH-2026-001), Purchase Order (PO-00001), Job Card (JC-2026-001), Material Request (MR-2026-001): draft / approve, history, PDF | manager · staff · viewer |

---

## Files

```
index.html            portal home (after login)
login.html            login page
access.html           Users & Access (portal admin only)
documents.html        Documents (8 types; PDFs are generated in the browser)
inventory.html        Inventory
employees.html        Employees (attendance, overtime, tasks, working kit, payroll)
kiosk.html            for the gate tablet
assets/config.js      <- put the Supabase URL and key here
assets/portal.js      login check + the portal's top bar
assets/portal.css, logo_mark.png, favicon.png
assets/header.jpg, footer.jpg, stamp.png   letterhead and company stamp for PDFs
supabase_setup.sql    database (run once)
supabase_docs.sql     Documents database, price list, storage for photos and certificates
supabase_hr.sql       Employees: working kit, paid tasks, deductions, advances, payslips
manifest.webmanifest, sw.js   for installing on a phone like an app
assets/shell.css      top bar and design (applied to every page automatically)
assets/icon-192.png, icon-512.png   app icon
supabase/functions/admin-users/index.ts   Edge Function that creates users
```

---

## Step 1 — Supabase: database

1. Open your new project → left menu **SQL Editor** → **New query**.
2. Paste the full content of `supabase_setup.sql` → **Run**.
   - If a "destructive operation" warning appears, click **Run this query**. It is only because of `drop policy if exists`; nothing is deleted.
   - You should see **Success** at the bottom. This file also adds the 26 employees.

### Step 1b — Documents (phase 2)

In the same way, open **SQL Editor → New query**, paste the full content of `supabase_docs.sql` and click **Run**. This creates the documents table, numbering, draft / approve rules and private storage for photos (the `docs` bucket). The file is safe to run again; run it again whenever new numbering is added.

### Step 1c — Employees: kit and payroll

Then **Run** `supabase_hr.sql` the same way. This creates the tables for working kit (rounds and standard kit), paid tasks, deductions / violations, advances and payslips. It is also safe to run again.

## Step 2 — Supabase: login settings

**Authentication → Sign In / Providers**:
- Keep the **Email** provider **on**.
- Turn **"Allow new users to sign up"** **off**. Users are created only from the portal's Users & Access page; nobody can create their own account.

## Step 3 — Supabase: Edge Function (for creating users)

Creating a new user needs Supabase's secret key, which must never be put in the website. So a small function inside Supabase does this job.

1. Left menu **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Name the function exactly: **`admin-users`**
3. Delete the code already in the editor. Paste the full content of `supabase/functions/admin-users/index.ts`.
4. Click **Deploy function**.

Turn the "Verify JWT" setting **off** (in new Supabase projects it stops requests from reaching the function). The function itself checks on every request that the caller is logged in and is a portal admin. Supabase gives the secret key to the function automatically; you don't need to paste it anywhere.

If you get an error on Users & Access: check **Edge Functions → admin-users → Logs**. `ReferenceError ... index.ts:1:1` means something other than the code was pasted into the editor; paste the full code again in the Code tab and Deploy.

## Step 4 — First admin (one time only)

1. **Authentication → Users → Add user → Create new user**
   - Email: `azeem@alhyakel.local` (User ID `azeem` + `@alhyakel.local`)
   - Password: your password (at least 8 characters)
   - Tick **Auto Confirm User** ✔ → **Create user**
2. Run this in the **SQL Editor**:
   ```sql
   insert into public.portal_users (id, username, full_name, is_admin, docs_role, inv_role, hr_role)
   select id, 'azeem', 'Azeem Bukhari', true, 'manager', 'admin', 'admin'
   from auth.users where email = 'azeem@alhyakel.local';
   ```
   The result should be `INSERT 0 1`. If you get `INSERT 0 0`, the email did not match; check it again.

All other users are created from the portal's **Users & Access** page, not from the Supabase dashboard.

## Step 5 — `assets/config.js`

Copy these two things from Supabase → **Project Settings → API Keys**:
- **Project URL** (also found under **Project Settings → Data API**)
- The **anon public** key or the **publishable** key (`sb_publishable_…`), either one

Paste them into `assets/config.js`:
```js
window.PORTAL_CONFIG = {
  SUPABASE_URL: 'https://abcdefghijklmnop.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi…   or   sb_publishable_…',
  LOGIN_DOMAIN: 'alhyakel.local'
};
```

⚠️ **Never put the service_role / secret key (`sb_secret_…`) here.** This file is public. The anon or publishable key is designed to be public; the data is protected by the database rules.

## Step 6 — GitHub Pages

1. Create a **new repository** on GitHub, e.g. `alhyakel-portal`, **Public**.
2. **Add file → Upload files**: upload **all files and folders** in this folder (including `assets` and `supabase`) → **Commit changes**.
   - `index.html` must be at the top level of the repo, not inside another folder.
3. Repo → **Settings → Pages** → Source: **Deploy from a branch** → Branch: **main**, folder **/(root)** → **Save**.
4. After 1-2 minutes the link will be ready: `https://azeemsyedb-code.github.io/alhyakel-portal/`

## Step 7 — First use

1. Open the link → User ID `azeem` and your password → **Login**.
2. **Users & Access** → **+ Add a new user** → choose the name, User ID, password and a role for each section.
3. **Employees → Employees** → click each employee and enter their **salary** and **kiosk PIN**.
4. On the gate tablet, open `…/alhyakel-portal/kiosk.html` → Chrome menu → **Add to Home screen**.

---

## New features (design update)

- **Top bar:** logo, search (documents, products and employees from one place), notification bell (waiting for approval, overdue invoices, low stock, tank certificates expiring within 30 days, overdue tasks) and user menu (Logout).
- **Home dashboard:** live numbers, a "Needs attention" list and quick actions.
- **Invoice payments:** open an invoice and record payments under **Payments**. The list shows Paid / Partially paid / Unpaid / Overdue. **Receivables** button: each customer's outstanding balance and how many days it has been due (Excel/CSV download).
- **Share:** every document has a **Share** button. On a phone the PDF goes straight to WhatsApp / email; on a computer the PDF downloads and WhatsApp Web or email opens.
- **Phone app:** open the portal → Chrome menu → **Install app / Add to Home screen** (iPhone: Safari → Share → Add to Home Screen). `manifest.webmanifest`, `sw.js` and `assets/icon-*.png` are for this.

## Price list, QR certificates, kit and payroll

- **Price List (Documents → Price List):** enter each product once with its category and sub-category (rate, unit, description). When creating a Quotation / Invoice, choose **Category → Sub-category → Product** at the top, enter the qty and click **+ Add**; the line fills in automatically with the rate and 15% VAT. Only manager / staff can edit; only manager can delete.
- **QR on Leak Test and Tank certificates:** the QR is now generated automatically. As soon as a certificate is **saved**, its PDF goes to the `certs` folder in Supabase and the QR is a link to that PDF; no third-party QR service. Scanning it opens the PDF directly (no login). If you change a certificate and **Save** again, the same QR shows the new PDF. For **old certificates**, open each one once and click **Save** to create its QR.
- **Tank Certificate photos:** add up to 4 photos in the **Photos (page 2)** box. The PDF then gets a second page with the photos and the company stamp, just like the Leak Test. Without photos the certificate stays one page. The Arabic certificate text fills in the "Valid Until" date automatically.
- **Working kit (Employees → Working kit):** separate from inventory (you take items out of the store in bulk).
  - **Standard kit** (HR admin only): what the kit contains (coverall, shoes, gloves…) and how often a new kit is issued (every 3 or 4 months).
  - **Issue kit round:** give the full kit to selected employees in one click, e.g. `KIT-2026-10`. Employees whose kit is due are ticked already. Items from the previous kit are marked "Replaced" automatically. Shoe / coverall sizes are filled in from the previous record.
  - **Kit schedule:** each employee's last kit and next kit date; when due, it also shows in the bell (notifications).
  - **Kit forms (PDF):** choose a round at the top → one page per employee; get it signed and file it.
  - **Single items:** for giving something in between (a new joiner, torn shoes); this does not change the next kit date.
  - **Return:** Good / Damaged / Lost. Damaged or Lost items carry a charge; if the HR admin keeps "Deduct from salary" on, it is deducted in the payslip.
- **Paid tasks:** when creating a task, the HR admin ticks **Paid task** and enters the amount. It is added to the salary for the month in which the task is marked "Done".
- **Payroll (HR admin only):** choose a month. Each employee's payslip: basic + overtime + paid tasks + bonus, minus absences (basic ÷ 30 per day, half day = half), violations / deductions and the advance installment. Record these with **+ Deduction / violation / bonus** and **+ Advance** (advance installments start being deducted from the next month). **Save** stores the payslip and counts the advance repayment; if something changes later, the row shows "Changed since" — click **Re-save**. Print **Payslip** / **All payslips (PDF)** and have the employee sign.

## Invoice and ZATCA

Invoices automatically get the ZATCA (phase 1) QR code: company name, VAT number, date, total and VAT. If the company falls under ZATCA phase 2 (Fatoora e-invoicing integration), the legal tax invoice must be issued from an accounting system connected to ZATCA; in that case treat the portal invoice as an internal / proforma copy.

## What the roles mean

| | admin / manager | middle role | viewer |
|---|---|---|---|
| **Inventory** | admin: everything + delete + stock count (adjust) | storekeeper: products, suppliers, stock in / out | view only |
| **Employees** | admin: everything + salary + PIN + settings + payroll | supervisor: attendance, overtime hours, tasks, working kit (no salary) | view only (no salary) |
| **Documents** | manager: everything + approve / reopen + delete | staff: create new and edit drafts (not approved ones) | view and download PDF only |

**Portal admin** (Users & Access) is a separate tick. You cannot remove your own admin access, and you cannot block or delete your own account.

---

## Old systems

- **Old GitHub Pages sites** (`alhyakel-inventory`, `emoplyees-tracker`): in those repos go to **Settings → Pages → Unpublish site**.
- **Old Supabase projects**: they only had test data; you can **pause** or **delete** them.
- **AHMI portal on Render**: all 8 documents are now created here. Download the PDFs of old documents (from Render) and keep them, then you can shut down the Render service.

---

## Troubleshooting

| What you see | Cause / fix |
|---|---|
| "Setup needed: …assets/config.js" | The URL / key was not added to `config.js`, or the wrong file was uploaded |
| "Incorrect User ID or password" on login | The password or User ID is wrong. For the first admin, check the email from Step 4 |
| "This login has not been added to the portal" on login | The Step 4 SQL (`insert into portal_users`) was not run |
| "Could not reach the Edge Function …admin-users…" on Users & Access | Repeat Step 3. The name must be exactly `admin-users` |
| "Database error: … does not exist" on any page | `supabase_setup.sql` did not run completely. Run Step 1 again |
| 404 on the GitHub link | Pages is not turned on, or `index.html` is inside a folder (Step 6) |
| "Database error" on Documents | `supabase_docs.sql` was not run (Step 1b) |
| Certificate saved but the image did not upload | Run Step 1b again (storage bucket), then click Save again |
| "Database error" on Payroll / Working kit | `supabase_hr.sql` was not run (Step 1c) |
| Certificate saved but the QR PDF did not upload | Run `supabase_docs.sql` again (`certs` bucket), then Save again |
| No names on the kiosk | No employee has a PIN set (Employees → Employees) |

A free Supabase project is paused if it is not used at all for **7 days**. With daily use this will not happen. If it does, click **Restore** in the Supabase dashboard.

---

## Technical

- **Login:** Supabase Auth. User ID `ahmed` is stored internally as `ahmed@alhyakel.local`. Every page checks login and access through `assets/portal.js`.
- **Access:** the `portal_users` table. The database's RLS rules enforce each role. Hiding menu items is only cosmetic; the real restriction is in the database.
- **Salary:** `hr_pay` is a separate table that only the HR admin can read. The kiosk PIN is stored as a bcrypt hash. After 5 wrong PINs, the employee is locked for 10 minutes.
- **Creating users, passwords, blocking / deleting:** Edge Function `admin-users`. It checks on every request that the caller is a portal admin.

## Fresh start (delete all data)

`supabase_reset.sql` wipes all business data and loads the current employee list (23 employees, EMP-01 … EMP-23). **It cannot be undone.**

1. Supabase → **SQL Editor → New query** → paste all of `supabase_reset.sql` → **Run**. The last line should show `employees 23, documents 0, products 0`.
2. Supabase → **Storage** → open the **docs** bucket → select everything → **Delete**. Do the same in the **certs** bucket. (Photos and certificate PDFs are files, so SQL cannot remove them.)

Kept: logins and roles (Users & Access) and HR settings. Document numbers start again from 1 (TS-001, HMI-2026-001, QT-AL000001 …). After the reset, add each employee's salary and kiosk PIN in **Employees → Employees**.

## Working faster

- **Phone:** on a phone the module tabs sit at the bottom of the screen like an app, tables turn into cards, and forms open as full-width sheets.
- **Save & New:** every document form has a **Save & New** button that saves and opens a fresh form of the same type.
- **Keyboard:** press <kbd>/</kbd> to jump to search, and <kbd>Ctrl</kbd>+<kbd>S</kbd> (<kbd>Cmd</kbd>+<kbd>S</kbd> on Mac) to save the open form or dialog.
- **Filters are remembered:** list filters (employee, status, category, kit round…) keep your last choice on that device.
