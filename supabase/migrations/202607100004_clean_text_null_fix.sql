-- ============================================================================
-- Juristic Care — Forward fix: remove invalid chr(0) construction from
-- public._clean_text
--
-- Context: migration 202607100003 (Stage 2) is APPLIED to staging. Linked
-- db lint then failed on public._clean_text:
--   null character not permitted   (assignment to variable v)
-- Cause: the installed body was
--   v := btrim(replace(p_value, chr(0), ''));
-- PostgreSQL `text` values can never contain the zero byte, so a NUL can
-- never be present in p_value in the first place — and constructing chr(0)
-- itself raises "null character not permitted". The replacement is therefore
-- both invalid and unnecessary; a plain btrim is the correct sanitization.
--
-- This is a FORWARD migration: the applied migration file is not rewritten
-- and no migration repair is used. It redefines ONLY _clean_text, preserving
-- its signature, return type, language, IMMUTABLE attribute, fixed
-- search_path, trimming behavior, empty-string→NULL behavior, maximum-length
-- validation and INVALID_INPUT error behavior. Searched all migrations:
-- no other currently-active function contains this defect.
-- ============================================================================

-- Server-side text sanitization: trim and enforce a length cap. PostgreSQL
-- text cannot contain NUL (the server rejects it at input), so no
-- zero-character stripping is needed or possible here.
create or replace function public._clean_text(p_value text, p_max int)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v text;
begin
  if p_value is null then
    return null;
  end if;
  v := btrim(p_value);
  if v = '' then
    return null;
  end if;
  if char_length(v) > p_max then
    raise exception 'INVALID_INPUT'
      using detail = format('Text field exceeds %s characters', p_max),
            errcode = 'P0001';
  end if;
  return v;
end $$;
