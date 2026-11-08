-- WA Rotator — Supabase schema
-- Jalankan seluruh file ini di Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'admin' check (role in ('admin','owner')),
  created_at timestamptz not null default now()
);

create or replace function public.is_rotator_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(select 1 from public.admin_users where user_id = auth.uid());
$$;

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null,
  phone text not null check (phone ~ '^[0-9]{8,16}$'),
  sort_order integer not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists sales_project_order_idx on public.sales(project_id, sort_order);

create table if not exists public.rotator_state (
  project_id uuid primary key references public.projects(id) on delete cascade,
  last_sales_id uuid null references public.sales(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.project_settings (
  project_id uuid primary key references public.projects(id) on delete cascade,
  message_template text not null default 'Halo, saya tertarik dengan informasi {nama_proyek}. Mohon info lebih lanjut.',
  updated_at timestamptz not null default now()
);

create table if not exists public.click_logs (
  id bigint generated always as identity primary key,
  project_id uuid not null references public.projects(id) on delete restrict,
  sales_id uuid null references public.sales(id) on delete set null,
  sales_name text not null,
  sales_phone text not null,
  campaign text,
  utm_source text,
  utm_medium text,
  utm_content text,
  utm_term text,
  fbclid text,
  message text,
  created_at timestamptz not null default now()
);
create index if not exists click_logs_project_created_idx on public.click_logs(project_id, created_at desc);
create index if not exists click_logs_sales_idx on public.click_logs(sales_id, created_at desc);

alter table public.admin_users enable row level security;
alter table public.projects enable row level security;
alter table public.sales enable row level security;
alter table public.rotator_state enable row level security;
alter table public.project_settings enable row level security;
alter table public.click_logs enable row level security;

drop policy if exists "admin users read" on public.admin_users;
create policy "admin users read" on public.admin_users for select to authenticated using (public.is_rotator_admin());
drop policy if exists "projects admin all" on public.projects;
create policy "projects admin all" on public.projects for all to authenticated using (public.is_rotator_admin()) with check (public.is_rotator_admin());
drop policy if exists "sales admin all" on public.sales;
create policy "sales admin all" on public.sales for all to authenticated using (public.is_rotator_admin()) with check (public.is_rotator_admin());
drop policy if exists "rotator state admin read" on public.rotator_state;
create policy "rotator state admin read" on public.rotator_state for select to authenticated using (public.is_rotator_admin());
drop policy if exists "settings admin all" on public.project_settings;
create policy "settings admin all" on public.project_settings for all to authenticated using (public.is_rotator_admin()) with check (public.is_rotator_admin());
drop policy if exists "logs admin read" on public.click_logs;
create policy "logs admin read" on public.click_logs for select to authenticated using (public.is_rotator_admin());

-- Hak akses tabel untuk sesi admin yang sudah login (tetap dibatasi RLS).
grant select on public.admin_users to authenticated;
grant select, insert, update, delete on public.projects to authenticated;
grant select, insert, update, delete on public.sales to authenticated;
grant select on public.rotator_state to authenticated;
grant select, insert, update, delete on public.project_settings to authenticated;
grant select on public.click_logs to authenticated;

-- Atomic allocation: concurrent clicks lock the per-project state row, then advance round-robin.
create or replace function public.allocate_whatsapp_lead(
  p_project_slug text,
  p_campaign text default null,
  p_source text default null,
  p_medium text default null,
  p_content text default null,
  p_term text default null,
  p_fbclid text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project public.projects%rowtype;
  v_state public.rotator_state%rowtype;
  v_sales public.sales%rowtype;
  v_message text;
  v_campaign text := nullif(left(coalesce(p_campaign,''),250),'');
begin
  select * into v_project from public.projects where slug = p_project_slug and is_active = true;
  if not found then raise exception 'Project tidak ditemukan atau nonaktif'; end if;

  insert into public.rotator_state(project_id) values(v_project.id)
  on conflict(project_id) do nothing;
  select * into v_state from public.rotator_state where project_id=v_project.id for update;

  select * into v_sales
  from public.sales
  where project_id=v_project.id and is_active=true
  order by
    case when v_state.last_sales_id is null then 0
         when id = v_state.last_sales_id then 1 else 0 end,
    sort_order asc, created_at asc
  offset case when v_state.last_sales_id is null then 0 else 0 end
  limit 1;

  -- Select the next sales after last_sales_id, wrapping to the first active sales.
  if v_state.last_sales_id is not null then
    select * into v_sales from public.sales
    where project_id=v_project.id and is_active=true
      and (sort_order, created_at) > (
        select sort_order, created_at from public.sales where id=v_state.last_sales_id
      )
    order by sort_order, created_at limit 1;
    if not found then
      select * into v_sales from public.sales where project_id=v_project.id and is_active=true
      order by sort_order, created_at limit 1;
    end if;
  end if;
  if v_sales.id is null then raise exception 'Belum ada sales aktif untuk project ini'; end if;

  select message_template into v_message from public.project_settings where project_id=v_project.id;
  v_message := coalesce(v_message,'Halo, saya tertarik dengan informasi {nama_proyek}. Mohon info lebih lanjut.');
  v_message := replace(v_message,'{nama_sales}',v_sales.name);
  v_message := replace(v_message,'{nama_proyek}',v_project.name);
  v_message := replace(v_message,'{campaign}',coalesce(v_campaign,''));

  update public.rotator_state set last_sales_id=v_sales.id, updated_at=now() where project_id=v_project.id;
  insert into public.click_logs(project_id,sales_id,sales_name,sales_phone,campaign,utm_source,utm_medium,utm_content,utm_term,fbclid,message)
  values(v_project.id,v_sales.id,v_sales.name,v_sales.phone,v_campaign,
    nullif(left(coalesce(p_source,''),100),''),nullif(left(coalesce(p_medium,''),100),''),
    nullif(left(coalesce(p_content,''),250),''),nullif(left(coalesce(p_term,''),250),''),
    nullif(left(coalesce(p_fbclid,''),500),''),v_message);

  return jsonb_build_object('project_name',v_project.name,'sales_name',v_sales.name,'phone',v_sales.phone,'message',v_message);
end;
$$;

revoke all on function public.allocate_whatsapp_lead(text,text,text,text,text,text,text) from public;
grant execute on function public.allocate_whatsapp_lead(text,text,text,text,text,text,text) to service_role;

-- Initial owner setup:
-- 1) Create the first user in Authentication > Users.
-- 2) Copy its UUID and run:
-- insert into public.admin_users(user_id,email,role)
-- values ('UUID_DARI_AUTH','email-admin-anda','owner');


-- =====================================================
-- ADMIN PERTAMA (JALANKAN SETELAH USER DIBUAT DI AUTH)
-- Buat user di Authentication > Users terlebih dahulu.
-- Lalu jalankan query berikut dengan email admin yang benar:
-- =====================================================
-- INSERT INTO public.admin_users (user_id, email, role)
-- SELECT id, email, 'owner' FROM auth.users
-- WHERE email = 'ihsan@admin.com'
-- ON CONFLICT (user_id) DO UPDATE SET email = EXCLUDED.email, role = 'owner';
