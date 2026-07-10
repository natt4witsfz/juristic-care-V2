-- Juristic Care Supabase migration v1.
-- Supabase-first backend with RLS, private Storage, RPC workflows, and a JSONB bridge.

create extension if not exists pgcrypto;

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  room_no text not null unique,
  room_no_alt text,
  building text,
  floor text,
  common_fee_status text not null default 'paid',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  login_id text not null unique,
  room_id uuid references public.rooms(id) on delete set null,
  display_name text not null,
  en_name text,
  first_name text,
  last_name text,
  nickname text,
  position text,
  phone text,
  app_role text not null check (app_role in ('admin','coadmin','staff','resident')),
  department text not null default 'resident',
  role_key text,
  is_co_admin boolean not null default false,
  assign_l1 boolean not null default false,
  assign_l2 boolean not null default false,
  can_assign boolean not null default false,
  permissions jsonb not null default '{}'::jsonb,
  profile_image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.room_profiles (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  relation text not null check (relation in ('owner','coowner','tenant','resident')),
  pin_hash text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.jobs (
  id text primary key,
  source text not null default 'WebApp',
  room_id uuid references public.rooms(id) on delete set null,
  reported_by uuid references public.app_users(id) on delete set null,
  assigned_by uuid references public.app_users(id) on delete set null,
  assignee_id uuid references public.app_users(id) on delete set null,
  status text not null default 'open',
  sub_status text not null default '',
  main_category text,
  category text,
  priority text,
  job_date date,
  due_date date,
  next_update_date date,
  share_public boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.job_close_pins (
  job_id text primary key references public.jobs(id) on delete cascade,
  pin_hash text not null,
  created_at timestamptz not null default now(),
  rotated_at timestamptz
);

create table if not exists public.job_timeline (
  id uuid primary key default gen_random_uuid(),
  job_id text not null references public.jobs(id) on delete cascade,
  actor_id uuid references public.app_users(id) on delete set null,
  action text not null,
  from_status text,
  to_status text,
  message text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.job_attachments (
  id uuid primary key default gen_random_uuid(),
  job_id text not null references public.jobs(id) on delete cascade,
  timeline_id uuid references public.job_timeline(id) on delete set null,
  uploaded_by uuid references public.app_users(id) on delete set null,
  bucket text not null default 'job-attachments',
  object_path text not null,
  original_name text,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now()
);

create table if not exists public.resident_people (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  first_name text,
  last_name text,
  nickname text,
  phone text,
  resident_type text not null default 'resident',
  is_current_resident boolean not null default true,
  sort_order integer not null default 0,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.resident_cars (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  plate_prefix text,
  plate_number text,
  province text,
  brand text,
  model text,
  color text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.permissions (
  user_id uuid primary key references public.app_users(id) on delete cascade,
  sidebar jsonb not null default '{}'::jsonb,
  actions jsonb not null default '{}'::jsonb,
  updated_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.sidebar_preferences (
  user_id uuid primary key references public.app_users(id) on delete cascade,
  ordered_keys text[] not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title jsonb not null default '{}'::jsonb,
  summary jsonb not null default '{}'::jsonb,
  audience jsonb not null default '{}'::jsonb,
  announcement_type text not null default 'image',
  pages jsonb not null default '[]'::jsonb,
  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_assignments (
  slot_key text primary key,
  user_id uuid references public.app_users(id) on delete set null,
  updated_by uuid references public.app_users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.app_users(id) on delete set null,
  actor_role text not null default 'system',
  actor_department text,
  actor_room text,
  action text not null,
  detail text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.google_form_submissions (
  id uuid primary key default gen_random_uuid(),
  external_id text unique,
  status text not null default 'new',
  payload jsonb not null default '{}'::jsonb,
  job_id text references public.jobs(id) on delete set null,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create table if not exists public.app_snapshots (
  id uuid primary key default gen_random_uuid(),
  snapshot jsonb not null,
  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_app_users_auth_user on public.app_users(auth_user_id);
create index if not exists idx_jobs_room on public.jobs(room_id);
create index if not exists idx_jobs_assignee on public.jobs(assignee_id);
create index if not exists idx_jobs_status on public.jobs(status);
create index if not exists idx_audit_logs_created on public.audit_logs(created_at desc);
create index if not exists idx_job_timeline_job on public.job_timeline(job_id, created_at desc);

create or replace function public.current_app_user_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.app_users where auth_user_id = auth.uid() and is_active limit 1
$$;

create or replace function public.current_app_role()
returns text language sql stable security definer set search_path = public as $$
  select app_role from public.app_users where auth_user_id = auth.uid() and is_active limit 1
$$;

create or replace function public.current_room_id()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(au.room_id, r.id)
  from public.app_users au
  left join public.rooms r on r.auth_user_id = auth.uid()
  where au.auth_user_id = auth.uid() and au.is_active
  limit 1
$$;

create or replace function public.is_staff_account()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_users
    where auth_user_id = auth.uid()
      and is_active
      and app_role in ('admin','coadmin','staff')
  )
$$;

create or replace function public.is_admin_account()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.app_users
    where auth_user_id = auth.uid()
      and is_active
      and (app_role = 'admin' or is_co_admin)
  )
$$;

create or replace function public.can_read_job(p_job_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.jobs j
    where j.id = p_job_id
      and (
        public.is_admin_account()
        or j.share_public
        or j.assignee_id = public.current_app_user_id()
        or j.assigned_by = public.current_app_user_id()
        or j.reported_by = public.current_app_user_id()
        or j.room_id = public.current_room_id()
      )
  )
$$;

create or replace function public.can_update_job(p_job_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.jobs j
    where j.id = p_job_id
      and (
        public.is_admin_account()
        or j.assignee_id = public.current_app_user_id()
        or j.assigned_by = public.current_app_user_id()
      )
  )
$$;

create or replace function public.append_audit_log(p_action text, p_detail text default '', p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_actor public.app_users%rowtype;
  v_id uuid;
begin
  select * into v_actor from public.app_users where auth_user_id = auth.uid() and is_active limit 1;
  insert into public.audit_logs (actor_id, actor_role, actor_department, actor_room, action, detail, payload)
  values (
    v_actor.id,
    coalesce(v_actor.app_role, 'system'),
    v_actor.department,
    v_actor.login_id,
    p_action,
    p_detail,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.create_profile(p_name text, p_relation text, p_pin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_room uuid;
  v_id uuid;
begin
  v_room := public.current_room_id();
  if v_room is null then raise exception 'NOT_A_ROOM_ACCOUNT'; end if;
  if p_pin !~ '^\d{4}$' then raise exception 'PIN_FORMAT'; end if;
  if (select count(*) from public.room_profiles where room_id = v_room and is_active) >= 5 then
    raise exception 'PROFILE_LIMIT';
  end if;
  insert into public.room_profiles (room_id, display_name, relation, pin_hash)
  values (v_room, p_name, p_relation, crypt(p_pin, gen_salt('bf')))
  returning id into v_id;
  perform public.append_audit_log('PROFILE_CREATED', p_name, jsonb_build_object('profile_id', v_id));
  return v_id;
end $$;

create or replace function public.verify_profile_pin(p_profile uuid, p_pin text)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_hash text;
begin
  select pin_hash into v_hash
  from public.room_profiles
  where id = p_profile
    and room_id = public.current_room_id()
    and is_active;
  if v_hash is null then return false; end if;
  return v_hash = crypt(p_pin, v_hash);
end $$;

create or replace function public.create_job(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := public.current_app_user_id();
  v_job_id text := coalesce(p_payload->>'id', 'JC-' || to_char(now(), 'YYMMDD-HH24MISSMS'));
  v_close_pin text := coalesce(p_payload->>'closePin', lpad((floor(random() * 10000))::int::text, 4, '0'));
  v_room uuid := null;
  v_job jsonb;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select id into v_room from public.rooms where room_no = coalesce(p_payload->>'roomNo', p_payload->>'room') limit 1;
  insert into public.jobs (
    id, source, room_id, reported_by, assigned_by, assignee_id, status, sub_status,
    main_category, category, priority, job_date, due_date, next_update_date, share_public, payload
  )
  values (
    v_job_id,
    coalesce(p_payload->>'source', 'WebApp'),
    v_room,
    v_user,
    nullif(p_payload->>'assignedBy', '')::uuid,
    nullif(p_payload->>'assignee', '')::uuid,
    coalesce(p_payload->>'status', 'open'),
    coalesce(p_payload->>'subStatus', ''),
    p_payload->>'mainCategory',
    p_payload->>'category',
    p_payload->>'priority',
    nullif(p_payload->>'jobDate', '')::date,
    nullif(p_payload->>'dueDate', '')::date,
    nullif(p_payload->>'nextUpdateDate', '')::date,
    coalesce((p_payload->>'sharePublic')::boolean, false),
    p_payload - 'closePin'
  )
  on conflict (id) do update set
    payload = excluded.payload,
    updated_at = now()
  returning payload || jsonb_build_object('id', id) into v_job;
  insert into public.job_close_pins (job_id, pin_hash)
  values (v_job_id, crypt(v_close_pin, gen_salt('bf')))
  on conflict (job_id) do nothing;
  perform public.append_audit_log('JOB_CREATED', v_job_id, jsonb_build_object('job_id', v_job_id));
  return v_job;
end $$;

create or replace function public.assign_job(p_job_id text, p_assignee_id uuid, p_extra jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_job jsonb;
begin
  if not public.can_update_job(p_job_id) and not public.is_admin_account() then raise exception 'FORBIDDEN'; end if;
  update public.jobs
  set assignee_id = p_assignee_id,
      assigned_by = public.current_app_user_id(),
      status = 'received',
      payload = payload || p_extra || jsonb_build_object('assignee', p_assignee_id, 'status', 'received'),
      updated_at = now()
  where id = p_job_id
  returning payload || jsonb_build_object('id', id) into v_job;
  perform public.append_audit_log('JOB_ASSIGNED', p_job_id, jsonb_build_object('job_id', p_job_id, 'assignee_id', p_assignee_id));
  return v_job;
end $$;

create or replace function public.update_job_status(p_job_id text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_job jsonb;
begin
  if not public.can_update_job(p_job_id) then raise exception 'FORBIDDEN'; end if;
  update public.jobs
  set status = coalesce(p_payload->>'status', status),
      sub_status = coalesce(p_payload->>'subStatus', sub_status),
      next_update_date = nullif(p_payload->>'nextUpdateDate', '')::date,
      payload = payload || p_payload,
      updated_at = now()
  where id = p_job_id
  returning payload || jsonb_build_object('id', id) into v_job;
  perform public.append_audit_log('JOB_STATUS_UPDATED', p_job_id, jsonb_build_object('job_id', p_job_id, 'status', p_payload->>'status'));
  return v_job;
end $$;

create or replace function public.verify_job_completion(p_job_id text)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.can_update_job(p_job_id) and not public.is_admin_account() then raise exception 'FORBIDDEN'; end if;
  update public.jobs
  set status = 'completed',
      sub_status = '',
      payload = payload || jsonb_build_object('status', 'completed', 'subStatus', '', 'completedAt', now()),
      updated_at = now()
  where id = p_job_id;
  perform public.append_audit_log('JOB_COMPLETION_VERIFIED', p_job_id, jsonb_build_object('job_id', p_job_id));
  return true;
end $$;

create or replace function public.save_client_snapshot(p_snapshot jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if not public.is_staff_account() then raise exception 'FORBIDDEN'; end if;
  insert into public.app_snapshots (snapshot, created_by)
  values (p_snapshot, public.current_app_user_id())
  returning id into v_id;
  perform public.append_audit_log('SNAPSHOT_SAVED', 'Client bridge snapshot saved', jsonb_build_object('snapshot_id', v_id));
  return v_id;
end $$;

create or replace function public.get_app_bootstrap()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_snapshot jsonb;
begin
  if public.is_staff_account() then
    select snapshot into v_snapshot from public.app_snapshots order by created_at desc limit 1;
    if v_snapshot is not null then return v_snapshot; end if;
  end if;
  return jsonb_build_object(
    'jobs', coalesce((select jsonb_agg(j.payload || jsonb_build_object('id', j.id)) from public.jobs j where public.can_read_job(j.id)), '[]'::jsonb),
    'adminLogs', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.audit_logs l where public.is_admin_account()), '[]'::jsonb),
    'staffLogs', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.audit_logs l where public.is_staff_account()), '[]'::jsonb),
    'residentLogs', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.audit_logs l where l.actor_id = public.current_app_user_id()), '[]'::jsonb),
    'residentRooms', '[]'::jsonb,
    'teamOverrides', '{}'::jsonb,
    'customUsers', '[]'::jsonb,
    'deletedUserIds', '[]'::jsonb,
    'announcements', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.announcements a), '[]'::jsonb),
    'organizationAssignments', '{}'::jsonb
  );
end $$;

alter table public.rooms enable row level security;
alter table public.app_users enable row level security;
alter table public.room_profiles enable row level security;
alter table public.jobs enable row level security;
alter table public.job_close_pins enable row level security;
alter table public.job_timeline enable row level security;
alter table public.job_attachments enable row level security;
alter table public.resident_people enable row level security;
alter table public.resident_cars enable row level security;
alter table public.permissions enable row level security;
alter table public.sidebar_preferences enable row level security;
alter table public.announcements enable row level security;
alter table public.organization_assignments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.google_form_submissions enable row level security;
alter table public.app_snapshots enable row level security;

drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms for select to authenticated
using (auth_user_id = auth.uid() or public.is_staff_account());

drop policy if exists app_users_select on public.app_users;
create policy app_users_select on public.app_users for select to authenticated
using (auth_user_id = auth.uid() or public.is_staff_account());

drop policy if exists jobs_select on public.jobs;
create policy jobs_select on public.jobs for select to authenticated
using (public.can_read_job(id));

drop policy if exists jobs_insert on public.jobs;
create policy jobs_insert on public.jobs for insert to authenticated
with check (public.current_app_user_id() is not null);

drop policy if exists jobs_update on public.jobs;
create policy jobs_update on public.jobs for update to authenticated
using (public.can_update_job(id) or public.is_admin_account())
with check (public.can_update_job(id) or public.is_admin_account());

drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs for select to authenticated
using (public.is_admin_account() or actor_id = public.current_app_user_id());

drop policy if exists audit_logs_insert on public.audit_logs;
create policy audit_logs_insert on public.audit_logs for insert to authenticated
with check (actor_id = public.current_app_user_id() or public.is_admin_account());

drop policy if exists no_audit_updates on public.audit_logs;
create policy no_audit_updates on public.audit_logs for update to authenticated using (false);

drop policy if exists no_audit_deletes on public.audit_logs;
create policy no_audit_deletes on public.audit_logs for delete to authenticated using (false);

drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select to authenticated using (true);

drop policy if exists staff_manage_announcements on public.announcements;
create policy staff_manage_announcements on public.announcements for all to authenticated
using (public.is_staff_account()) with check (public.is_staff_account());

drop policy if exists staff_manage_permissions on public.permissions;
create policy staff_manage_permissions on public.permissions for all to authenticated
using (public.is_admin_account()) with check (public.is_admin_account());

drop policy if exists sidebar_pref_own on public.sidebar_preferences;
create policy sidebar_pref_own on public.sidebar_preferences for all to authenticated
using (user_id = public.current_app_user_id()) with check (user_id = public.current_app_user_id());

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('job-attachments', 'job-attachments', false, 5242880, array['image/png','image/jpeg','image/webp','application/pdf']),
  ('announcement-files', 'announcement-files', false, 12582912, array['image/png','image/jpeg','image/webp','application/pdf']),
  ('profile-images', 'profile-images', false, 5242880, array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_access_storage_object(p_bucket text, p_name text)
returns boolean language plpgsql stable security definer set search_path = public, storage as $$
declare
  v_folder text[] := storage.foldername(p_name);
begin
  if p_bucket = 'announcement-files' then
    return auth.uid() is not null;
  end if;
  if p_bucket = 'profile-images' then
    return public.is_admin_account()
      or (array_length(v_folder, 1) >= 2 and v_folder[1] = 'profiles' and v_folder[2] = public.current_app_user_id()::text);
  end if;
  if p_bucket = 'job-attachments' then
    if public.is_staff_account() then return true; end if;
    if array_length(v_folder, 1) >= 2 and v_folder[1] = 'jobs' then
      return public.can_read_job(v_folder[2]);
    end if;
  end if;
  return false;
end $$;

drop policy if exists juristic_storage_select on storage.objects;
create policy juristic_storage_select on storage.objects for select to authenticated
using (
  bucket_id in ('job-attachments','announcement-files','profile-images')
  and public.can_access_storage_object(bucket_id, name)
);

drop policy if exists juristic_storage_insert on storage.objects;
create policy juristic_storage_insert on storage.objects for insert to authenticated
with check (
  bucket_id in ('job-attachments','announcement-files','profile-images')
  and auth.uid() is not null
);

drop policy if exists juristic_storage_update on storage.objects;
create policy juristic_storage_update on storage.objects for update to authenticated
using (public.is_staff_account() or owner_id = (select auth.uid()::text))
with check (public.is_staff_account() or owner_id = (select auth.uid()::text));

drop policy if exists juristic_storage_delete on storage.objects;
create policy juristic_storage_delete on storage.objects for delete to authenticated
using (public.is_admin_account());
