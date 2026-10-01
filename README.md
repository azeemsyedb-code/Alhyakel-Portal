# Al Hyakel Portal — Supabase + GitHub Pages

Ek link, ek login. Har user ko sirf wahi hisse nazar aate hain jin ka use access diya gaya hai.
Server ki zaroorat nahi: website **GitHub Pages** par chalti hai, aur saara data aur login **Supabase** mein hai (bilkul inventory portal jaisa).

| Hissa | Kya hai | Roles |
|---|---|---|
| **Inventory** | Stock in / out, barcode scan, products, suppliers, kam stock ke alerts | admin · storekeeper · viewer |
| **Employees** | Attendance, overtime, tasks, salary | admin · supervisor · viewer |
| **Gate kiosk** | Employees PIN se check-in / check-out karte hain (bina login) | — |
| **Users & Access** | Users banana, password badalna, access dena / hatana | portal admin |
| **Documents** | Leak Test (TS-001), Delivery Note (AH-2026-001), Quotation (QT-AL000001), Purchase Order (PO-00001), Tank Certificate (HMI-2026-001, English + Arabic): save, history, PDF | manager · staff · viewer |

---

## Files

```
index.html            portal home (login ke baad)
login.html            login page
access.html           Users & Access (sirf portal admin)
documents.html        Documents (Leak Test, Delivery Note, Quotation, PO, Tank Certificate; PDF browser mein banti hai)
inventory.html        Inventory
employees.html        Employees (attendance, overtime, tasks)
kiosk.html            gate tablet ke liye
assets/config.js      <- yahan Supabase URL aur key daalni hai
assets/portal.js      login check + portal ki upar wali patti
assets/portal.css, logo_mark.png, favicon.png
assets/header.jpg, footer.jpg, stamp.png   PDF ke liye letterhead aur company stamp
supabase_setup.sql    database (ek dafa chalana hai)
supabase_docs.sql     Documents ka database + photos ki storage (phase 2, ek dafa chalana hai)
supabase/functions/admin-users/index.ts   users banane wala Edge Function
```

---

## Step 1 — Supabase: database

1. Apna naya project kholein → left menu **SQL Editor** → **New query**.
2. `supabase_setup.sql` ka poora content paste karein → **Run**.
   - "destructive operation" ki warning aaye to **Run this query** dabayein. Yeh sirf `drop policy if exists` ki wajah se hai, kuch delete nahi hota.
   - Neeche **Success** aana chahiye. Is file se 26 employees bhi add ho jate hain.

### Step 1b — Documents (phase 2)

Isi tarah **SQL Editor → New query** mein `supabase_docs.sql` ka poora content paste karke **Run** karein. Is se documents ki table, numbering (TS-001, AH-2026-001, QT-AL000001, PO-00001, HMI-2026-001) aur photos ke liye private storage (`docs` bucket) ban jati hai. File dobara chalana safe hai; nayi numbering aaye to dobara chalayein.

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

## Roles ka matlab

| | admin / manager | beech wala | viewer |
|---|---|---|---|
| **Inventory** | admin: sab kuch + delete + stock count (adjust) | storekeeper: products, suppliers, stock in / out | sirf dekhna |
| **Employees** | admin: sab kuch + salary + PIN + settings | supervisor: attendance, overtime ghante, tasks (salary nahi) | sirf dekhna (salary nahi) |
| **Documents** | manager: sab kuch + delete | staff: naya banana aur edit | sirf dekhna aur PDF download |

**Portal admin** (Users & Access) alag tick hai. Aap khud apna admin access nahi hata sakte, na apna account band ya delete kar sakte hain.

---

## Purani cheezein

- **Purane GitHub Pages sites** (`alhyakel-inventory`, `emoplyees-tracker`): un repos mein **Settings → Pages → Unpublish site**.
- **Purane Supabase projects**: sab test data tha, **pause** ya **delete** kar sakte hain.
- **Render wala AHMI portal**: Leak Test, Delivery Note, Quotation, PO aur Tank Certificate ab yahin bante hain. Invoice, Job Card aur Material Request jab tak yahan na aa jayein, Render wala portal **chalta rehne dein**.

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
| Kiosk par koi naam nahi | Kisi employee ka PIN set nahi (Employees → Employees) |

Free Supabase project agar **7 din** tak bilkul istemal na ho to pause ho jata hai. Roz ke istemal mein yeh nahi hoga. Agar ho jaye to Supabase dashboard mein **Restore** dabayein.

---

## Technical

- **Login:** Supabase Auth. User ID `ahmed` andar `ahmed@alhyakel.local` hota hai. Har page `assets/portal.js` se login aur access check karta hai.
- **Access:** `portal_users` table. Database ke RLS rules har role ko rokte hain. Menu chhupana sirf dikhawa hai, asli rok database mein hai.
- **Salary:** `hr_pay` alag table, jo sirf HR admin padh sakta hai. Kiosk PIN bcrypt hash mein hai. 5 ghalat PIN par employee 10 minute ke liye lock ho jata hai.
- **Users banana, password, band / delete:** Edge Function `admin-users`. Yeh har request par check karta hai ke bulane wala portal admin hai.
