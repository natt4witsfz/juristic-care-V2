-- ============================================================================
-- Stage: post-login profile onboarding
--
-- Adds backend-owned account profile selection, one Owner profile per account
-- by RPC enforcement, temporary 6-digit profile PIN challenges, and interface
-- preferences. This is intentionally additive and idempotent for staging first.
-- ============================================================================

create table if not exists public.profile_owner_conflicts (
  account_id uuid primary key references public.app_users(id) on delete cascade,
  owner_count integer not null,
  detected_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.room_profiles
  add column if not exists account_id uuid references public.app_users(id) on delete cascade,
  add column if not exists profile_type text,
  add column if not exists room_number text,
  add column if not exists status text not null default 'ACTIVE',
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists created_by uuid references public.app_users(id) on delete set null;

alter table public.room_profiles alter column room_id drop not null;

update public.room_profiles rp
set
  account_id = coalesce(rp.account_id, au.id),
  profile_type = coalesce(rp.profile_type, upper(rp.relation)),
  room_number = coalesce(rp.room_number, r.room_no),
  status = case when rp.is_active then 'ACTIVE' else 'INACTIVE' end,
  updated_at = coalesce(rp.updated_at, rp.created_at)
from public.rooms r
left join public.app_users au on au.room_id = r.id
where rp.room_id = r.id
  and (rp.account_id is null or rp.profile_type is null or rp.room_number is null);

update public.room_profiles
set profile_type = case
  when profile_type in ('OWNER','TENANT','RESIDENT') then profile_type
  when lower(coalesce(relation, '')) = 'owner' then 'OWNER'
  when lower(coalesce(relation, '')) = 'tenant' then 'TENANT'
  else 'RESIDENT'
end
where profile_type is null
   or profile_type not in ('OWNER','TENANT','RESIDENT');

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'room_profiles_profile_type_chk'
  ) then
    alter table public.room_profiles
      add constraint room_profiles_profile_type_chk
      check (profile_type in ('OWNER','TENANT','RESIDENT')) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'room_profiles_status_chk'
  ) then
    alter table public.room_profiles
      add constraint room_profiles_status_chk
      check (status in ('ACTIVE','INACTIVE','SUSPENDED')) not valid;
  end if;
end $$;

alter table public.room_profiles validate constraint room_profiles_profile_type_chk;
alter table public.room_profiles validate constraint room_profiles_status_chk;

insert into public.profile_owner_conflicts (account_id, owner_count)
select account_id, count(*)
from public.room_profiles
where profile_type = 'OWNER'
  and status <> 'INACTIVE'
  and account_id is not null
group by account_id
having count(*) > 1
on conflict (account_id) do update
set owner_count = excluded.owner_count,
    detected_at = now(),
    resolved_at = null;

do $$
begin
  if not exists (
    select 1
    from public.room_profiles
    where profile_type = 'OWNER'
      and status <> 'INACTIVE'
      and account_id is not null
    group by account_id
    having count(*) > 1
  ) then
    create unique index if not exists idx_room_profiles_one_active_owner
      on public.room_profiles (account_id)
      where profile_type = 'OWNER' and status <> 'INACTIVE';
  end if;
end $$;

insert into public.room_profiles (
  account_id, room_id, display_name, relation, profile_type, room_number,
  status, pin_hash, created_by
)
select
  au.id,
  au.room_id,
  coalesce(nullif(au.display_name, ''), au.login_id),
  'owner',
  'OWNER',
  r.room_no,
  'ACTIVE',
  extensions.crypt(encode(extensions.gen_random_bytes(16), 'hex'), extensions.gen_salt('bf')),
  au.id
from public.app_users au
left join public.rooms r on r.id = au.room_id
where au.is_active
  and not exists (
    select 1 from public.room_profiles rp
    where rp.account_id = au.id and rp.profile_type = 'OWNER'
  );

create table if not exists public.profile_pin_challenges (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.app_users(id) on delete cascade,
  profile_id uuid not null references public.room_profiles(id) on delete cascade,
  session_id text not null,
  pin_hash text not null,
  expires_at timestamptz not null,
  attempt_count integer not null default 0,
  max_attempts integer not null default 5,
  verified_at timestamptz,
  used_at timestamptz,
  invalidated_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_profile_pin_challenges_active
  on public.profile_pin_challenges (account_id, profile_id, session_id)
  where verified_at is null and used_at is null and invalidated_at is null;

create table if not exists public.profile_preferences (
  profile_id uuid primary key references public.room_profiles(id) on delete cascade,
  interface_mode text not null default 'FULL' check (interface_mode in ('FULL','COMPACT')),
  language text,
  updated_at timestamptz not null default now()
);

alter table public.profile_pin_challenges enable row level security;
alter table public.profile_preferences enable row level security;
alter table public.profile_owner_conflicts enable row level security;

revoke all on public.profile_pin_challenges from anon, authenticated;

create or replace function public.ensure_owner_profiles()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_conflicts integer := 0;
  v_created integer := 0;
begin
  insert into public.profile_owner_conflicts (account_id, owner_count)
  select account_id, count(*)
  from public.room_profiles
  where profile_type = 'OWNER'
    and status <> 'INACTIVE'
    and account_id is not null
  group by account_id
  having count(*) > 1
  on conflict (account_id) do update
  set owner_count = excluded.owner_count,
      detected_at = now(),
      resolved_at = null;
  get diagnostics v_conflicts = row_count;

  insert into public.room_profiles (
    account_id, room_id, display_name, relation, profile_type, room_number,
    status, pin_hash, created_by
  )
  select
    au.id,
    au.room_id,
    coalesce(nullif(au.display_name, ''), au.login_id),
    'owner',
    'OWNER',
    r.room_no,
    'ACTIVE',
    extensions.crypt(encode(extensions.gen_random_bytes(16), 'hex'), extensions.gen_salt('bf')),
    au.id
  from public.app_users au
  left join public.rooms r on r.id = au.room_id
  where au.is_active
    and not exists (
      select 1 from public.room_profiles rp
      where rp.account_id = au.id and rp.profile_type = 'OWNER'
    );
  get diagnostics v_created = row_count;

  return jsonb_build_object('created_owner_profiles', v_created, 'conflicts_reported', v_conflicts);
end;
$$;

create or replace function public.list_account_profiles()
returns table (
  profile_id uuid,
  account_id uuid,
  profile_type text,
  display_name text,
  room_number text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  interface_mode text
) language sql security definer set search_path = public as $$
  select
    rp.id,
    rp.account_id,
    rp.profile_type,
    rp.display_name,
    coalesce(rp.room_number, r.room_no),
    rp.status,
    rp.created_at,
    rp.updated_at,
    coalesce(pp.interface_mode, 'FULL')
  from public.room_profiles rp
  left join public.rooms r on r.id = rp.room_id
  left join public.profile_preferences pp on pp.profile_id = rp.id
  where rp.account_id = public.current_app_user_id()
  order by case when rp.profile_type = 'OWNER' then 0 else 1 end, rp.created_at;
$$;

create or replace function public.create_account_profile(
  p_profile_type text,
  p_display_name text,
  p_room_number text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_account uuid := public.current_app_user_id();
  v_id uuid;
begin
  if v_account is null then raise exception 'UNAUTHENTICATED' using errcode = 'P0001'; end if;
  p_profile_type := upper(coalesce(p_profile_type, ''));
  if p_profile_type not in ('TENANT','RESIDENT') then
    raise exception 'PROFILE_TYPE_NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if nullif(btrim(p_display_name), '') is null then
    raise exception 'DISPLAY_NAME_REQUIRED' using errcode = 'P0001';
  end if;

  insert into public.room_profiles (
    account_id, room_id, display_name, relation, profile_type, room_number,
    status, pin_hash, created_by
  )
  select
    au.id,
    au.room_id,
    btrim(p_display_name),
    lower(p_profile_type),
    p_profile_type,
    nullif(btrim(p_room_number), ''),
    'ACTIVE',
    extensions.crypt(encode(extensions.gen_random_bytes(16), 'hex'), extensions.gen_salt('bf')),
    au.id
  from public.app_users au
  where au.id = v_account
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.select_account_profile(p_profile_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_account uuid := public.current_app_user_id();
  v_profile public.room_profiles%rowtype;
begin
  select * into v_profile
  from public.room_profiles
  where id = p_profile_id and account_id = v_account and status = 'ACTIVE';
  if not found then raise exception 'PROFILE_NOT_SELECTABLE' using errcode = 'P0001'; end if;

  return jsonb_build_object(
    'profileId', v_profile.id,
    'accountId', v_profile.account_id,
    'profileType', v_profile.profile_type,
    'displayName', v_profile.display_name
  );
end;
$$;

create or replace function public.issue_profile_pin_challenge(p_profile_id uuid, p_session_id text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_account uuid := public.current_app_user_id();
  v_pin text;
  v_id uuid;
begin
  if v_account is null then raise exception 'UNAUTHENTICATED' using errcode = 'P0001'; end if;
  perform 1 from public.room_profiles
  where id = p_profile_id and account_id = v_account and status = 'ACTIVE';
  if not found then raise exception 'PROFILE_NOT_SELECTABLE' using errcode = 'P0001'; end if;

  update public.profile_pin_challenges
  set invalidated_at = now()
  where account_id = v_account
    and profile_id = p_profile_id
    and session_id = p_session_id
    and verified_at is null
    and used_at is null
    and invalidated_at is null;

  v_pin := lpad((abs(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::int))::bigint) % 1000000)::text, 6, '0');

  insert into public.profile_pin_challenges (
    account_id, profile_id, session_id, pin_hash, expires_at
  )
  values (
    v_account, p_profile_id, p_session_id,
    extensions.crypt(v_pin, extensions.gen_salt('bf')),
    now() + interval '5 minutes'
  )
  returning id into v_id;

  v_pin := null;
  return jsonb_build_object('challengeId', v_id, 'expiresInSeconds', 300, 'cooldownSeconds', 30, 'delivery', 'configured-provider');
end;
$$;

create or replace function public.verify_profile_pin_challenge(
  p_profile_id uuid,
  p_session_id text,
  p_pin text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_account uuid := public.current_app_user_id();
  v_challenge public.profile_pin_challenges%rowtype;
begin
  if p_pin !~ '^\d{6}$' then raise exception 'PIN_FORMAT' using errcode = 'P0001'; end if;

  select * into v_challenge
  from public.profile_pin_challenges
  where account_id = v_account
    and profile_id = p_profile_id
    and session_id = p_session_id
    and invalidated_at is null
  order by created_at desc
  limit 1
  for update;

  if not found then raise exception 'PIN_NOT_FOUND' using errcode = 'P0001'; end if;
  if v_challenge.used_at is not null then raise exception 'PIN_ALREADY_USED' using errcode = 'P0001'; end if;
  if now() > v_challenge.expires_at then
    update public.profile_pin_challenges set invalidated_at = now() where id = v_challenge.id;
    raise exception 'PIN_EXPIRED' using errcode = 'P0001';
  end if;
  if v_challenge.attempt_count >= v_challenge.max_attempts then
    update public.profile_pin_challenges set invalidated_at = now() where id = v_challenge.id;
    raise exception 'PIN_TOO_MANY_ATTEMPTS' using errcode = 'P0001';
  end if;

  if extensions.crypt(p_pin, v_challenge.pin_hash) <> v_challenge.pin_hash then
    update public.profile_pin_challenges
    set attempt_count = attempt_count + 1,
        invalidated_at = case when attempt_count + 1 >= max_attempts then now() else invalidated_at end
    where id = v_challenge.id;
    raise exception 'PIN_INVALID' using errcode = 'P0001';
  end if;

  update public.profile_pin_challenges
  set verified_at = now(), used_at = now()
  where id = v_challenge.id;

  return jsonb_build_object('verified', true, 'profileId', p_profile_id);
end;
$$;

create or replace function public.save_interface_preference(p_profile_id uuid, p_interface_mode text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_account uuid := public.current_app_user_id();
begin
  p_interface_mode := upper(coalesce(p_interface_mode, ''));
  if p_interface_mode not in ('FULL','COMPACT') then
    raise exception 'INTERFACE_MODE_INVALID' using errcode = 'P0001';
  end if;
  perform 1 from public.room_profiles
  where id = p_profile_id and account_id = v_account and status = 'ACTIVE';
  if not found then raise exception 'PROFILE_NOT_SELECTABLE' using errcode = 'P0001'; end if;

  insert into public.profile_preferences (profile_id, interface_mode, updated_at)
  values (p_profile_id, p_interface_mode, now())
  on conflict (profile_id) do update
  set interface_mode = excluded.interface_mode,
      updated_at = now();

  return jsonb_build_object('interfaceMode', p_interface_mode);
end;
$$;

grant execute on function public.ensure_owner_profiles() to authenticated;
grant execute on function public.list_account_profiles() to authenticated;
grant execute on function public.create_account_profile(text, text, text) to authenticated;
grant execute on function public.select_account_profile(uuid) to authenticated;
grant execute on function public.issue_profile_pin_challenge(uuid, text) to authenticated;
grant execute on function public.verify_profile_pin_challenge(uuid, text, text) to authenticated;
grant execute on function public.save_interface_preference(uuid, text) to authenticated;
