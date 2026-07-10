-- Legacy note:
-- This file is kept for reference from the earlier Auth + Profiles phase.
-- Production Supabase setup now starts at:
-- supabase/migrations/202607090001_full_supabase_schema.sql

-- =====================================================
-- Juristic Care — Supabase Schema (Phase 1: Auth + Profiles)
-- รันใน SQL Editor ตามลำดับ: 1) seed-rooms.sql  2) ไฟล์นี้
-- หลักการ: 1 ห้อง = 1 บัญชี auth / หลายโปรไฟล์ (Netflix-style)
-- PIN ตรวจฝั่งเซิร์ฟเวอร์ผ่าน RPC เท่านั้น (client ไม่เห็น hash)
-- =====================================================

create extension if not exists pgcrypto;

-- ---------- 1. Profiles (สมาชิกในห้อง) ----------
create table if not exists profiles (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  relation text not null check (relation in ('owner','coowner','tenant','resident')),
  pin_hash text not null,               -- crypt(pin, gen_salt('bf'))
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_profiles_room on profiles(room_id);

-- จำกัด 5 โปรไฟล์ต่อห้อง (บังคับระดับ DB)
create or replace function enforce_profile_limit()
returns trigger language plpgsql as $$
begin
  if (select count(*) from profiles where room_id = new.room_id and is_active) >= 5 then
    raise exception 'PROFILE_LIMIT: ห้องนี้มีโปรไฟล์ครบ 5 คนแล้ว';
  end if;
  return new;
end $$;
drop trigger if exists trg_profile_limit on profiles;
create trigger trg_profile_limit before insert on profiles
  for each row execute function enforce_profile_limit();

-- ---------- 2. Staff roles ----------
create table if not exists staff (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('admin','coadmin','technician','housekeeping','security','garden','office')),
  team text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from staff where id = auth.uid() and is_active) $$;

create or replace function my_room_id() returns uuid
language sql stable security definer set search_path = public as
$$ select id from rooms where auth_user_id = auth.uid() $$;

-- ---------- 3. RPC: จัดการโปรไฟล์ + PIN (server-side only) ----------
-- สร้างโปรไฟล์ในห้องของตัวเอง
create or replace function create_profile(p_name text, p_relation text, p_pin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_room uuid; v_id uuid;
begin
  v_room := my_room_id();
  if v_room is null then raise exception 'NOT_A_ROOM_ACCOUNT'; end if;
  if p_pin !~ '^\d{4}$' then raise exception 'PIN_FORMAT: ต้องเป็นตัวเลข 4 หลัก'; end if;
  insert into profiles (room_id, display_name, relation, pin_hash)
  values (v_room, p_name, p_relation, crypt(p_pin, gen_salt('bf')))
  returning id into v_id;
  return v_id;
end $$;

-- ตรวจ PIN: คืน true/false โดย client ไม่เคยเห็น hash
create or replace function verify_profile_pin(p_profile uuid, p_pin text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_hash text;
begin
  select pin_hash into v_hash from profiles
  where id = p_profile and room_id = my_room_id() and is_active;
  if v_hash is null then return false; end if;
  return v_hash = crypt(p_pin, v_hash);
end $$;

-- เปลี่ยน PIN (ต้องรู้ PIN เดิม)
create or replace function change_profile_pin(p_profile uuid, p_old text, p_new text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not verify_profile_pin(p_profile, p_old) then return false; end if;
  if p_new !~ '^\d{4}$' then raise exception 'PIN_FORMAT'; end if;
  update profiles set pin_hash = crypt(p_new, gen_salt('bf')) where id = p_profile;
  return true;
end $$;

-- Admin รีเซ็ต PIN ให้ลูกบ้าน (กรณีลืม): คืน PIN ชั่วคราว
create or replace function admin_reset_pin(p_profile uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_pin text;
begin
  if not exists (select 1 from staff where id = auth.uid() and role in ('admin','coadmin') and is_active)
    then raise exception 'FORBIDDEN'; end if;
  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  update profiles set pin_hash = crypt(v_pin, gen_salt('bf')) where id = p_profile;
  return v_pin;
end $$;

-- ---------- 4. Row Level Security ----------
alter table rooms enable row level security;
alter table profiles enable row level security;
alter table staff enable row level security;

-- ห้อง: เห็นเฉพาะห้องตัวเอง / เจ้าหน้าที่เห็นทุกห้อง
drop policy if exists rooms_select on rooms;
create policy rooms_select on rooms for select
  using (auth_user_id = auth.uid() or is_staff());

-- โปรไฟล์: อ่านได้เฉพาะของห้องตัวเอง (ผ่าน view ไม่มี pin_hash) หรือเจ้าหน้าที่
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select
  using (room_id = my_room_id() or is_staff());
-- เขียนผ่าน RPC (security definer) เท่านั้น: ไม่เปิด insert/update ตรง

drop policy if exists staff_select on staff;
create policy staff_select on staff for select using (is_staff());

-- View สำหรับ client: ตัด pin_hash ออกเสมอ
create or replace view profiles_public as
  select id, room_id, display_name, relation, is_active, created_at from profiles;
grant select on profiles_public to authenticated;

-- บังคับให้ client อ่านผ่าน view: ถอนสิทธิ์อ่าน column pin_hash
revoke select (pin_hash) on profiles from authenticated, anon;

-- ---------- 5. เชื่อมกับตาราง jobs (เมื่อย้าย jobs มาแล้ว) ----------
-- alter table jobs add column if not exists room_id uuid references rooms(id);
-- alter table jobs add column if not exists reported_by_profile uuid references profiles(id);
-- Policy ตัวอย่าง: ลูกบ้านเห็นเฉพาะงานห้องตัวเอง
-- create policy jobs_room_select on jobs for select
--   using (room_id = my_room_id() or is_staff());

-- ---------- วิธีใช้จากฝั่ง client (แทน localStorage เดิม) ----------
-- login:      supabase.auth.signInWithPassword({ email: room_no + '@rooms.juristic.local', password })
--             (หรือใช้ signInWithPassword แบบ phone/username ผ่าน custom — แนะนำ map room_no เป็น email เทียม)
-- โปรไฟล์:    supabase.from('profiles_public').select('*')
-- สร้าง:      supabase.rpc('create_profile', { p_name, p_relation, p_pin })
-- ตรวจ PIN:   supabase.rpc('verify_profile_pin', { p_profile, p_pin })
