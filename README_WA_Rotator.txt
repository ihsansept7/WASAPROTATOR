WA ROTATOR — PAKET SUPABASE + VERCEL

ISI PAKET
- index.html: dashboard admin dan halaman aplikasi.
- config.js: konfigurasi frontend (Project URL + publishable/anon key).
- supabase.sql: database, RLS, dan fungsi round-robin.
- api/admins.js: API server untuk membuat/mengubah/menghapus admin.
- api/rotate.js: endpoint redirect WhatsApp.
- vercel.json: rewrite /r/slug-project ke endpoint rotator.

A. BUAT USER ADMIN PERTAMA
1. Supabase > Authentication > Users > Add User > Create New User.
2. Buat email admin yang akan dipakai login dan password yang diinginkan.
3. Aktifkan Auto Confirm User bila tersedia.
4. Setelah user dibuat, jalankan query admin owner di bagian akhir supabase.sql (ubah email jika berbeda).
5. Password tidak disimpan di public.admin_users; password dikelola Supabase Auth.

B. JALANKAN DATABASE
1. Supabase > SQL Editor > New Query.
2. Salin seluruh supabase.sql, lalu Run.
3. Jika SQL dijalankan sebelum user dibuat, bagian pendaftaran admin di bawah file masih berupa contoh komentar. Jalankan INSERT admin setelah membuat user Auth.

C. HUBUNGKAN FRONTEND
1. Buka config.js.
2. Isi SUPABASE_URL dengan Project URL Supabase.
3. Isi SUPABASE_ANON_KEY dengan Publishable key (sb_publishable_...) atau anon key lama.
4. Jangan isi service_role/secret key di config.js.

D. ENVIRONMENT VARIABLES DI VERCEL
Tambahkan pada Project > Settings > Environment Variables:
- SUPABASE_URL = Project URL
- SUPABASE_ANON_KEY = Publishable/anon key
- SUPABASE_SERVICE_ROLE_KEY = Secret service_role key
Pilih Production, Preview, Development sesuai kebutuhan, lalu Save dan Redeploy.
Catatan: Environment variables server-side Vercel dipakai api/*.js; browser menggunakan config.js.

E. DEPLOY GITHUB
1. Upload semua isi folder ini ke root repository GitHub (termasuk folder api).
2. Pastikan package.json dan vercel.json ada di root.
3. Commit & push. Vercel akan deploy otomatis.
4. Setelah deploy, buka domain dan login menggunakan email/password yang dibuat di Supabase Auth. Password diketik manual; tidak ada password default yang ditanam di HTML.

F. LINK ROTATOR
Setelah project dan sales dibuat di dashboard, gunakan:
https://DOMAIN-VERCEL-ANDA/r/slug-project

TROUBLESHOOTING LOGIN
- Invalid login credentials: cek email/password di Authentication > Users; reset password jika perlu.
- Supabase URL/key not configured: periksa config.js, pastikan bukan placeholder, lalu push ulang.
- Login berhasil tetapi bukan admin: pastikan user UUID/email sudah masuk public.admin_users dengan role owner/admin.
- Failed to fetch: cek URL, key publik, koneksi jaringan, dan Console browser.
- API admin gagal: cek ketiga Environment Variables di Vercel dan Redeploy.

KEAMANAN
- Jangan commit service_role key ke GitHub atau config.js.
- Jangan menambahkan kolom password plaintext ke public.admin_users.
- Gunakan password kuat dan aktifkan MFA bila tersedia.
