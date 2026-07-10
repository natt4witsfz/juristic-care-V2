-- ============================================================================
-- Juristic Care — Forward fix: schema-qualify pgcrypto calls
--
-- Context: migrations 202607090001 and 202607100001 are APPLIED to staging.
-- Linked db lint reported on public.verify_profile_pin:
--   function crypt(text, text) does not exist
-- Cause: the v1 profile-PIN functions run with a fixed
--   set search_path = public
-- but call pgcrypto (crypt / gen_salt) unqualified. On Supabase, pgcrypto is
-- installed in the `extensions` schema, which is not on that fixed path.
--
-- This is a FORWARD migration: the applied migration files are not rewritten
-- and no migration repair is used. It redefines ONLY the two currently-active
-- functions affected by the lint failure, changing nothing but the pgcrypto
-- calls, which become schema-qualified (extensions.crypt / extensions.gen_salt).
-- The fixed search_path stays exactly `public` (no extension schema is added
-- to it), signatures, return types, authorization, validation, audit behavior
-- and PIN format are unchanged, and CREATE OR REPLACE preserves the existing
-- grants. No PIN or hash value is ever exposed.
--
-- NOT touched here (verified classification of all pgcrypto call sites):
--   * v1 create_job (crypt/gen_salt at 202607090001:368) — already replaced
--     by the Stage 1 fail-closed stub; not an active body.
--   * gen_random_uuid() column defaults — built-in (pg_catalog), not pgcrypto.
--   * The unapplied Stage 2 migration (separate branch) — corrected there
--     before it is ever applied.
-- ============================================================================

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
  values (v_room, p_name, p_relation, extensions.crypt(p_pin, extensions.gen_salt('bf')))
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
  return v_hash = extensions.crypt(p_pin, v_hash);
end $$;
