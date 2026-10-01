# Al Hyakel Portal — Supabase + GitHub Pages

Ek link, ek login. Har user ko sirf wahi hisse nazar aate hain jin ka use access diya gaya hai.
Server ki zaroorat nahi: website **GitHub Pages** par chalti hai, aur saara data aur login **Supabase** mein hai (bilkul inventory portal jaisa).

| Hissa | Kya hai | Roles |
|---|---|---|
| **Inventory** | Stock in / out, barcode scan, products, suppliers, kam stock ke alerts | admin · storekeeper · viewer |
| **Employees** | Attendance, overtime, tasks, salary | admin · supervisor · viewer |
| **Gate kiosk** | Employees PIN se check-in / check-out karte hain (bina login) | — |
| **Users & Access** | Users banana, password badalna, access dena / hatana | portal admin |
| **Documents** | Leak Test (TS-001), Tank Certificate (HMI-2026-001, English + Arabic), Quotation (QT-AL000001), Invoice (INV-AL00001, ZATCA QR), Delivery Note (AH-2026-001), Purchase Order (PO-00001), Job Card (JC-2026-001), Material Request (MR-2026-001): draft / approve, history, PDF | manager · staff · viewer |

---

## Files

```
index.html            portal home (login ke baad)
login.html            login page
access.html           Users & Access (sirf portal admin)
documents.html        Documents (8 types; PDF browser mein banti hai)
inventory.html        Inventory
employees.html        Employees (attendance, overtime, tasks, working kit, payroll)
kiosk.html            gate tablet ke liye
assets/config.js      <- yahan Supabase URL aur key daalni hai
assets/portal.js      login check + portal ki upar wali patti
assets/portal.css, logo_mark.png, favicon.png
assets/header.jpg, footer.jpg, stamp.png   PDF ke liye letterhead aur company stamp
supabase_setup.sql    database (ek dafa chalana hai)
supabase_docs.sql     Documents ka database, price list, photos aur certificates ki storage
supabase_hr.sql       Employees: working kit, paid tasks, deductions, advances, payslips
manifest.webmanifest, sw.js   phone par app ki tarah install karne ke liye
assets/shell.css      upar ki patti aur design (har page par khud lagta hai)
assets/icon-192.png, icon-512.png   app icon
supabase/functions/admin-users/index.ts   users banane wala Edge Function
```

---

## Step 1 — Supabase: database

1. Apna naya project kholein → left menu **SQL Editor** → **New query**.
2. `supabase_setup.sql` ka poora content paste karein → **Run**.
   - "destructive operation" ki warning aaye to **Run this query** dabayein. Yeh sirf `drop policy if exists` ki wajah se hai, kuch delete nahi hota.
   - Neeche **Success** aana chahiye. Is file se 26 employees bhi add ho jate hain.

### Step 1b — Documents (phase 2)

Isi tarah **SQL Editor → New query** mein `supabase_docs.sql` ka poora content paste karke **Run** karein. Is se documents ki table, numbering, draft / approve ke rules aur photos ke liye private storage (`docs` bucket) ban jati hai. File dobara chalana safe hai; nayi numbering aaye to dobara chalayein.

### Step 1c — Employees: kit aur payroll

Phir `supabase_hr.sql` bhi isi tarah **Run** karein. Is se working kit (rounds aur standard kit), paid tasks, deductions / violations, advances aur payslips ki tables ban jati hain. Yeh bhi dobara chalana safe hai.

## Step 2 — Supabase: login settings

**Authentication → Sign In / Providers**:
- **Email** provider **on** rahe.
- **"Allow new users to sign up"** ko **off** kar dein. Users sirf portal ke Users & Access page se banenge, koi khud account nahi bana sakega.

## Step 3 — Supabase: Edge Function (users banane ke liye)

Naya user banane ke liye Supabase ki secret key chahiye, jo website mein kabhi nahi daali ja sakti. Is liye yeh kaam ek chhota function Supabase ke andar karta hai.

1. Left menu **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Function ka naam bilkul yeh rakhein: **`admin-users`**
3. Editor mein pehle se likha code mita dein. `supabase/functions/admin-users/index.ts` ka poora content paste karein.
4. **Deploy function** dabayein.

"Verify JWT" wali setting **off** kar dein (naye Supabase projects mein yeh request ko function tak pohanchne nahi deti). Function khud har request par check karta hai ke bulane wala login hai aur portal admin hai. Secret key Supabase function ko khud de deta hai, aapko kahin paste nahi karni.

Agar Users & Access par error aaye: **Edge Functions → admin-users → Logs** dekhein. `ReferenceError ... index.ts:1:1` ka matlab hai editor mein code ki jagah kuch aur paste ho gaya, Code tab mein poora code dobara paste karke Deploy karein.

## Step 4 — Pehla admin (sirf ek dafa)

1. **Authentication → Users → Add user → Create new user**
   - Email: `azeem@alhyakel.local` (User ID `azeem` + `@alhyakel.local`)
   - Password: apna password (kam az kam 8)
   - **Auto Confirm User** ✔ tick karein → **Create user**
2. **SQL Editor** mein yeh chalayein:
   ```sql
   insert into public.portal_users (id, username, full_name, is_admin, docs_role, inv_role, hr_role)
   select id, 'azeem', 'Azeem Bukhari', true, 'manager', 'admin', 'admin'
   from auth.users where email = 'azeem@alhyakel.local';
   ```
   Result mein `INSERT 0 1` aana chahiye. Agar `INSERT 0 0` aaye to email match nahi hua, dobara check karein.

Baaqi saare users portal ke **Users & Access** page se banenge, dashboard se nahi.

## Step 5 — `assets/config.js`

Supabase → **Project Settings → API Keys** se yeh do cheezein copy karein:
- **Project URL** (ya **Project Settings → Data API** par milta hai)
- **anon public** key ya **publishable** key (`sb_publishable_…`), dono mein se koi ek

`assets/config.js` mein paste karein:
```js
window.PORTAL_CONFIG = {
  SUPABASE_URL: 'https://abcdefghijklmnop.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi…   ya   sb_publishable_…',
  LOGIN_DOMAIN: 'alhyakel.local'
};
```

⚠️ **service_role / secret key (`sb_secret_…`) kabhi yahan na daalein.** Yeh file public hoti hai. anon ya publishable key public hone ke liye hi bani hai, data database ke rules se mehfooz hai.

## Step 6 — GitHub Pages

1. GitHub par **naya repository** banayein, maslan `alhyakel-portal`, **Public**.
2. **Add file → Upload files**: is folder ki **saari files aur folders** (`assets`, `supabase` bhi) upload karein → **Commit changes**.
   - `index.html` repo ke andar seedha top level par ho, kisi aur folder ke andar nahi.
3. Repo → **Settings → Pages** → Source: **Deploy from a branch** → Branch: **main**, folder **/(root)** → **Save**.
4. 1-2 minute baad link banega: `https://azeemsyedb-code.github.io/alhyakel-portal/`

## Step 7 — Pehli dafa istemal

1. Link kholein → User ID `azeem` aur apna password → **Login**.
2. **Users & Access** → **+ Naya user banayein** → naam, User ID, password aur har hisse ka role chunein.
3. **Employees → Employees** → har employee par click karke **salary** aur **kiosk PIN** dalein.
4. Gate ke tablet par `…/alhyakel-portal/kiosk.html` kholein → Chrome menu → **Add to Home screen**.

---

## Naye features (design update)

- **Upar ki patti:** logo, search (documents, products, employees ek jagah se), notifications ki ghanti (approval ka intezar, overdue invoices, kam stock, 30 din mein expire hone wale tank certificates, overdue tasks) aur user menu (Logout).
- **Home dashboard:** live numbers, "Needs attention" list aur quick actions.
- **Invoice payments:** invoice khol kar **Payments** mein payment darj karein. List mein Paid / Partially paid / Unpaid / Overdue nazar aata hai. **Receivables** button: har customer ka baqi paisa, kitne din se (Excel/CSV download).
- **Share:** har document par **Share** button. Phone par PDF seedha WhatsApp / email mein jati hai; computer par PDF download ho kar WhatsApp Web ya email khulta hai.
- **Phone app:** portal kholein → Chrome menu → **Install app / Add to Home screen** (iPhone: Safari → Share → Add to Home Screen). `manifest.webmanifest`, `sw.js` aur `assets/icon-*.png` is ke liye hain.

## Price list, QR certificates, kit aur payroll

- **Price List (Documents → Price List):** har product category aur sub-category ke saath ek dafa likh dein (rate, unit, tafseel). Quotation / Invoice banate waqt upar **Category → Sub-category → Product** chunein, qty daalein aur **+ Add**; line rate aur 15% VAT ke saath khud bhar jati hai. Edit sirf manager / staff, delete sirf manager.
- **Leak Test aur Tank certificate ka QR:** ab QR khud banta hai. Certificate **Save** karte hi uski PDF Supabase ke `certs` folder mein chali jati hai aur QR usi PDF ka link hota hai, koi third-party QR nahi. Scan karne par PDF seedha khulti hai (bina login). Certificate badal kar dobara Save karein to wahi QR nayi PDF dikhata hai. **Purane certificates** ko ek dafa khol kar **Save** dabayein, tab un ka QR banega.
- **Working kit (Employees → Working kit):** inventory se alag hai (store se saman aap bulk mein nikalte hain).
  - **Standard kit** (sirf HR admin): kit mein kya kya hai (coverall, shoes, gloves…) aur nayi kit har kitne mahine (3 ya 4) baad.
  - **Issue kit round:** ek click mein chune hue employees ko poori kit, maslan `KIT-2026-10`. Jin ki kit due hai woh pehle se tick hote hain. Pichli kit ke items khud "Replaced" ho jate hain. Shoes / coverall ka size pichle record se khud aa jata hai.
  - **Kit schedule:** har employee ki pichli kit aur agli kit ki tareekh; due hone par ghanti (notifications) mein bhi aata hai.
  - **Kit forms (PDF):** upar se round chunein → har employee ka ek page, sign karwa kar file kar lein.
  - **Single items:** beech mein kuch dena ho (naya joiner, phati hui shoes) to; is se agli kit ki tareekh nahi badalti.
  - **Return:** Good / Damaged / Lost. Damaged ya Lost par charge, HR admin "Salary se kaatein" rakhe to payslip mein katauti.
- **Paid tasks:** task banate waqt HR admin **Paid task** tick karke raqam likhe. Task jis mahine "Done" ho, us mahine ki salary mein judta hai.
- **Payroll (sirf HR admin):** mahina chunein. Har employee ki payslip: basic + overtime + paid tasks + bonus, minus absent (basic ÷ 30 har din, half day aadha), violations / deductions aur advance ki qist. **+ Deduction / violation / bonus** aur **+ Advance** se record karein (advance ki qist agle mahine se katni shuru hoti hai). **Save** se payslip mehfooz hoti hai aur advance ki wapsi hisaab mein aati hai; baad mein kuch badle to row par "Changed since" aata hai, **Re-save** karein. **Payslip** / **All payslips (PDF)** print karke employee se sign karwayein.

## Invoice aur ZATCA

Invoice par ZATCA (phase 1) wala QR code khud lagta hai: company ka naam, VAT number, date, total aur VAT. Agar company ZATCA phase 2 (Fatoora e-invoicing integration) mein shamil hai, to legal tax invoice ZATCA se juray hue accounting system se hi jari honi chahiye; yeh portal wala invoice us surat mein andaruni / proforma copy samjhein.

## Roles ka matlab

| | admin / manager | beech wala | viewer |
|---|---|---|---|
| **Inventory** | admin: sab kuch + delete + stock count (adjust) | storekeeper: products, suppliers, stock in / out | sirf dekhna |
| **Employees** | admin: sab kuch + salary + PIN + settings + payroll | supervisor: attendance, overtime ghante, tasks, working kit (salary nahi) | sirf dekhna (salary nahi) |
| **Documents** | manager: sab kuch + approve / reopen + delete | staff: naya banana aur draft edit karna (approved nahi) | sirf dekhna aur PDF download |

**Portal admin** (Users & Access) alag tick hai. Aap khud apna admin access nahi hata sakte, na apna account band ya delete kar sakte hain.

---

## Purani cheezein

- **Purane GitHub Pages sites** (`alhyakel-inventory`, `emoplyees-tracker`): un repos mein **Settings → Pages → Unpublish site**.
- **Purane Supabase projects**: sab test data tha, **pause** ya **delete** kar sakte hain.
- **Render wala AHMI portal**: saare 8 documents ab yahin bante hain. Purane documents ki PDFs (Render se) download karke rakh lein, phir Render service band kar sakte hain.

---

## Agar masla aaye

| Kya dikhe | Wajah / hal |
|---|---|
| "Setup needed: assets/config.js …" | `config.js` mein URL / key nahi daali, ya ghalat file upload hui |
| Login par "Ghalat User ID ya password" | Password ya User ID ghalat hai. Pehle admin ke liye Step 4 ka email check karein |
| Login par "Yeh login portal mein add nahi hai" | Step 4 ka SQL (`insert into portal_users`) nahi chala |
| Users & Access par "Edge Function admin-users nahi mila" | Step 3 dobara karein. Naam bilkul `admin-users` ho |
| Kisi page par "Database error: … does not exist" | `supabase_setup.sql` poori nahi chali. Step 1 dobara chalayein |
| GitHub link par 404 | Pages on nahi hua ya `index.html` kisi folder ke andar hai (Step 6) |
| Documents par "Database error" | `supabase_docs.sql` nahi chali (Step 1b) |
| Certificate save hua lekin "Image upload nahi hui" | Step 1b dobara chalayein (storage bucket), phir Save dobara dabayein |
| Payroll / Working kit par "Database error" | `supabase_hr.sql` nahi chali (Step 1c) |
| Certificate save hua lekin "QR wali PDF upload nahi hui" | `supabase_docs.sql` dobara chalayein (`certs` bucket), phir Save dobara |
| Kiosk par koi naam nahi | Kisi employee ka PIN set nahi (Employees → Employees) |

Free Supabase project agar **7 din** tak bilkul istemal na ho to pause ho jata hai. Roz ke istemal mein yeh nahi hoga. Agar ho jaye to Supabase dashboard mein **Restore** dabayein.

---

## Technical

- **Login:** Supabase Auth. User ID `ahmed` andar `ahmed@alhyakel.local` hota hai. Har page `assets/portal.js` se login aur access check karta hai.
- **Access:** `portal_users` table. Database ke RLS rules har role ko rokte hain. Menu chhupana sirf dikhawa hai, asli rok database mein hai.
- **Salary:** `hr_pay` alag table, jo sirf HR admin padh sakta hai. Kiosk PIN bcrypt hash mein hai. 5 ghalat PIN par employee 10 minute ke liye lock ho jata hai.
- **Users banana, password, band / delete:** Edge Function `admin-users`. Yeh har request par check karta hai ke bulane wala portal admin hai.
