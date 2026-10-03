# Al Hyakel Portal — Supabase + GitHub Pages

One link, one login. Each user sees only the sections they have been given access to.
No server needed: the website runs on **GitHub Pages**, and all data and logins live in **Supabase** (just like the inventory portal).

| Section | What it is | Roles |
|---|---|---|
| **Inventory** | Stock in / out, barcode scan, products, suppliers, low-stock alerts | admin · storekeeper · viewer |
| **Employees** | Attendance, overtime, tasks, salary | admin · supervisor · viewer |
| **Gate kiosk** | Employees check in / check out with a PIN (no login) | — |
| **Users & Access** | Create users, change passwords, grant / remove access | portal admin |
| **Documents** | Leak Test (TS-001), Tank Certificate (HMI-2026-001, English + Arabic), Cash Receipt (CR-2026-001), Quotation (QT-AL000001), Invoice (INV-AL00001, ZATCA QR), Delivery Note (AH-2026-001), Purchase Order (PO-00001), Job Card (JC-2026-001), Material Request (MR-2026-001): draft / approve, history, PDF | manager · staff · viewer |

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
supabase_hr.sql       Employees: working kit, paid tasks, deductions, payslips
manifest.webmanifest, sw.js   for installing on a phone like an app
assets/export.js      Data export to Excel and backups (Users & Access page)
verify.html           public page the certificate QR codes open
supabase_extras.sql   stock count, kiosk photo, weekly backup, phone notifications
supabase/functions/notify/index.ts   Edge Function that sends phone notifications
assets/shell.css      top bar and design (applied to every page automatically)
assets/icon-192.png, icon-512.png   app icon
supabase/functions/admin-users/index.ts   Edge Function that creates users
```

---

## Step 1 — Supabase: database

1. Open your new project → left menu **SQL Editor** → **New query**.
2. Paste the full content of `supabase_setup.sql` → **Run**.
   - If a "destructive operation" warning appears, click **Run this query**. It is only because of `drop policy if exists`; nothing is deleted.
   - You should see **Success** at the bottom. This file also adds the 23 employees.

### Step 1b — Documents (phase 2)

In the same way, open **SQL Editor → New query**, paste the full content of `supabase_docs.sql` and click **Run**. This creates the documents table, numbering, draft / approve rules and private storage for photos (the `docs` bucket). The file is safe to run again; run it again whenever new numbering is added.

### Step 1c — Employees: kit and payroll

Then **Run** `supabase_hr.sql` the same way. This creates the tables for working kit (rounds and standard kit), paid tasks, deductions / violations, payslips and salary payments. It is also safe to run again.

### Step 1d — Extras (stock count, kiosk photo, backups, notifications)

Run `supabase_extras.sql` the same way. If the result says **"Weekly backup NOT scheduled"**, open Supabase → **Integrations → Cron** → enable it, then run the file again.

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
- **Send on WhatsApp:** Leak Test, Tank Certificate, Delivery Note and Job Card have a green **WhatsApp** button (in the open document and on each row of the list). It opens a ready message with a link: certificates link to the **Verified** page; delivery notes and job cards link to their PDF (the portal uploads the latest saved PDF each time you send). Type the customer's mobile (05XXXXXXXX) or leave it empty and pick the contact in WhatsApp; the number is remembered per customer on that device. Save the document first. Invoices and receipts are not sent from here (use Zoho Books).
- **Phone app:** open the portal → Chrome menu → **Install app / Add to Home screen** (iPhone: Safari → Share → Add to Home Screen). `manifest.webmanifest`, `sw.js` and `assets/icon-*.png` are for this.

## Price list, QR certificates, kit and payroll

- **Price List (Documents → Price List):** enter each product once with its category and sub-category (rate, unit, description). When creating a Quotation / Invoice, choose **Category → Sub-category → Product** at the top, enter the qty and click **+ Add**; the line fills in automatically with the rate and 15% VAT. Only manager / staff can edit; only manager can delete.
- **QR on Leak Test and Tank certificates:** generated automatically when a certificate is **saved** (no third-party QR service). Scanning it opens the portal's public **Verified** page (`verify.html`, no login): Al Hyakel's name, an engraved gold seal, a big green **Valid** (orange **Valid, renew soon** in the last 30 days, red **Expired** / **Test failed**, grey **Not found** for a fake code), a validity timeline with the days left, a moving "Genuine record" strip and a running clock (so a screenshot cannot pass as a live check), the main details, and a button to open the PDF. If you change a certificate and **Save** again, the same QR shows the new details and PDF. Save certificates after the custom domain is set up, so the QR uses the new address.
- **Tank Certificate photos:** add up to 4 photos in the **Photos (page 2)** box. The PDF then gets a second page with the photos and the company stamp, just like the Leak Test. Without photos the certificate stays one page. The Arabic certificate text fills in the "Valid Until" date automatically.
- **Working kit (Employees → Working kit):** separate from inventory (you take items out of the store in bulk).
  - **Standard kit** (HR admin only): what the kit contains (coverall, shoes, gloves…) and how often a new kit is issued (every 3 or 4 months).
  - **Issue kit round:** give the full kit to selected employees in one click, e.g. `KIT-2026-10`. Employees whose kit is due are ticked already. Items from the previous kit are marked "Replaced" automatically. Shoe / coverall sizes are filled in from the previous record.
  - **Kit schedule:** each employee's last kit and next kit date; when due, it also shows in the bell (notifications).
  - **Kit forms (PDF):** choose a round at the top → one page per employee; get it signed and file it.
  - **Single items:** for giving something in between (a new joiner, torn shoes); this does not change the next kit date.
  - **Return:** Good / Damaged / Lost. Damaged or Lost items carry a charge; if the HR admin keeps "Deduct from salary" on, it is deducted in the payslip.
- **Paid tasks:** when creating a task, the HR admin ticks **Paid task** and enters the amount. It is added to the salary for the month in which the task is marked "Done".
- **Payroll (HR admin only):** choose a month. Each employee's payslip: basic + overtime + paid tasks + bonus, minus absences (basic ÷ 30 per day, half day = half), violations / deductions. Record these with **+ Deduction / violation / bonus**. **Save** stores the payslip; if something changes later, the row shows "Changed since" — click **Re-save**. Print **Payslip** / **All payslips (PDF)** and have the employee sign.

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

## Friday (weekly off day)

- Friday is set as the weekly off day (change it in **Employees → Settings**, or choose "No weekly off day").
- If someone works on Friday, **all** the hours they work count as overtime (not just the hours above the shift). You can still type a different number of OT hours for that person on that day; "auto" switches back.
- Optional: **Overtime rate on the off day** in Settings. Leave it empty to use each employee's normal overtime rate.
- On Friday, "Mark everyone not in" marks people as **Off day**, not absent. The payslip shows Friday overtime as its own line.
- Needs the latest `supabase_hr.sql` (run it again in the SQL Editor).

## Data export (portal admins)

**Users & Access → Data export**: choose a period (this month, last month, this year, last year, custom dates, or all time) and the sections, then **Download Excel**. You get one `.xlsx` file with a Summary sheet and a separate sheet for each kind of record: every document type, document lines, payments, price list, suppliers, products, stock movements, employees, attendance, tasks, working kit, deductions & bonuses, salary payments, payslips, and (optional) users & roles. Use **All time** once a month as a backup, since the free Supabase plan has no automatic backups. The export only includes sections the logged-in admin has a role in.

## Fresh start (delete all data)

`supabase_reset.sql` wipes all business data and loads the current employee list (23 employees, EMP-01 … EMP-23). **It cannot be undone.**

1. Supabase → **SQL Editor → New query** → paste all of `supabase_reset.sql` → **Run**. The last line should show `employees 23, documents 0, products 0`.
2. Supabase → **Storage** → open the **docs** bucket → select everything → **Delete**. Do the same in the **certs** bucket. (Photos and certificate PDFs are files, so SQL cannot remove them.)

Kept: logins and roles (Users & Access) and HR settings. Document numbers start again from 1 (TS-001, HMI-2026-001, QT-AL000001 …). After the reset, add each employee's salary and kiosk PIN in **Employees → Employees**.

## Salary payments (Employees → Payroll)

- Each row shows the month's **Net**, what has been **Paid** and the **Balance**, with a status: Unpaid, Part paid, Paid or Overpaid.
- **Pay**: record money given to the employee (cash, bank transfer or cheque). You can pay part of the salary during the month and the rest later; each payment is listed under **Salary payments** for that month.
- Tick "Download a payment voucher" (or click **Voucher** on a payment) to print a Salary Payment Voucher for the employee to sign: amount, amount in words, net for the month, paid before and balance left.
- **Pay all balances**: one payment for everyone's remaining balance (for example the monthly bank / WPS transfer).
- The payslip PDF lists the payments made and the balance due.
- Needs the latest `supabase_hr.sql`.

## Cash Receipt (Documents → Cash Receipt)

- A receipt for money received from a customer: number `CR-2026-001` (restarts every year), date, received from, amount (written in words automatically), paid by (cash, cheque, bank transfer, card) with cheque / transfer number and bank, and what it is for.
- **Against invoice**: choose one of the customer's unpaid invoices and the money is also recorded as a payment on that invoice (it shows in the invoice's Payments and in Receivables). Deleting the receipt deletes that payment. Once linked, only a manager can change the amount, date, method or invoice.
- The PDF is bilingual (English / Arabic, سند قبض) with the company stamp, printed twice on one A4 page: the **Original** for the customer and a **Copy** for the file, with a cut line between them.
- Needs the latest `supabase_docs.sql`.

## Stock count (Inventory → Stock count)

1. **Start a new count**: give it a name and choose all products or one category.
2. Walk the store with a phone: scan each barcode (camera or a USB/Bluetooth scanner) or type the SKU, and enter how many there are. Tick **Each scan adds 1** for things you count one by one. Several people can count the same list at once.
3. Storekeepers do not see the system quantity while counting (a blind count, so the count is honest).
4. The inventory admin opens the count, checks **Differences only**, then clicks **Apply count to stock**. Each counted product's stock becomes the counted quantity (shown in Movements as ADJUST "Stock count: …"). Products not counted do not change. **Export CSV** gives the full count sheet.

## Kiosk photo

The gate kiosk now takes a small photo when someone presses OK to check in or out, so nobody can punch in for someone else. The tablet asks once for camera permission: tap **Allow**. HR admin and supervisors see a camera icon next to the name in **Today** and **Attendance**; click it to see the photos. Photos are deleted automatically after 60 days. If the camera is off, the punch still works without a photo.

## Backups (Users & Access → Backups)

Every Friday at 23:00 a full copy of all portal data is saved automatically (the last 8 are kept), plus up to 5 copies made with **Back up now**. Download any copy as **Excel** (one sheet per table) or **JSON** (complete, for restoring). Kiosk PINs and passwords are never included. These copies live inside Supabase, so also download one now and then and keep it on your computer or Google Drive.

## Phone notifications

What you get: a new document **waiting for approval** (managers), your document **approved** (whoever made it), **low stock** the moment an item goes below its minimum (inventory admin + storekeeper), and a **7:30 morning summary** (overdue invoices, tank certificates expiring in 14 days, items to approve, low stock, kit due, overdue tasks), each person only for the parts they use.

One-time setup (about 10 minutes). The private values are in the `PRIVATE-do-not-upload` folder; never put them on GitHub.
1. Supabase → **Edge Functions → Deploy a new function → Via Editor**, name it exactly **`notify`**, paste all of `supabase/functions/notify/index.ts`, **Deploy**. Then turn **Verify JWT off** for this function (same as `admin-users`).
2. Supabase → **Edge Functions → Secrets** → add the four secrets from `push-secrets.txt`: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`, `NOTIFY_SECRET`.
3. Supabase → **SQL Editor** → run `push-secrets.sql` (from the private folder). It tells the database where the function is.
4. Make sure `supabase_extras.sql` has been run (Step 1d).

Each person then turns notifications on for each phone / computer: tap the avatar (top right) → **Notifications on this device** → Allow, then **Send a test notification**. On iPhone this only works in the installed app (Safari → Share → **Add to Home Screen**, then open it from the home screen). To stop, tap the same item again.

## Working faster

- **Phone:** on a phone the module tabs sit at the bottom of the screen like an app, tables turn into cards, and forms open as full-width sheets.
- **Save & New:** every document form has a **Save & New** button that saves and opens a fresh form of the same type.
- **Keyboard:** press <kbd>/</kbd> to jump to search, and <kbd>Ctrl</kbd>+<kbd>S</kbd> (<kbd>Cmd</kbd>+<kbd>S</kbd> on Mac) to save the open form or dialog.
- **Filters are remembered:** list filters (employee, status, category, kit round…) keep your last choice on that device.
