-- ============================================================================
-- Juristic Care — Forward fix: valid objectPath check in
-- public._legacy_evidence_kind
--
-- Context: migrations 202607110001/202607110002 are APPLIED to staging. The
-- Stage 5 smoke test then failed with SQLSTATE 2201B
--   invalid regular expression: invalid repetition count(s)
-- at the classifier's objectPath pattern. Cause: the bounded quantifier
-- {2,510} exceeds PostgreSQL's maximum regex repetition bound (255).
--
-- This is a FORWARD migration: the applied files are not rewritten and no
-- manual repair is performed. It recreates ONLY _legacy_evidence_kind,
-- replacing the bounded regex with an explicit length check plus an
-- unbounded safe character-class regex (hyphen last to avoid dialect
-- ambiguity):
--   char_length(v_path) between 3 and 511
--   and v_path ~ '^[A-Za-z0-9][A-Za-z0-9/_.-]*$'
-- Accepted-path semantics are unchanged: 3..511 chars, ASCII alphanumeric
-- first character, then only ASCII letters/digits/slash/underscore/dot/
-- hyphen. Embedded dataURL/base64/blob/local-file evidence is still
-- classified 'binary'; unusable entries stay 'invalid'; no Storage behavior
-- is added. Signature, return type, language, volatility (IMMUTABLE),
-- search_path and privileges (preserved by CREATE OR REPLACE) are unchanged,
-- and import_legacy_job itself is untouched.
-- ============================================================================

-- Classify one attachment entry.
--   'stable'  : object with a safe managed objectPath (no embedded data)
--   'binary'  : dataURL/base64/blob/local-file → record must fail
--   'invalid' : anything else unusable
create or replace function public._legacy_evidence_kind(p_item jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_path text;
begin
  if p_item is null then return 'invalid'; end if;
  if jsonb_typeof(p_item) = 'string' then
    return 'binary'; -- bare strings in legacy data are dataURL previews
  end if;
  if jsonb_typeof(p_item) <> 'object' then return 'invalid'; end if;
  -- any embedded payload marker anywhere in the object → binary
  if coalesce(p_item->>'dataUrl', p_item->>'src', p_item->>'previewUrl', '') like 'data:%'
     or coalesce(p_item->>'objectPath', p_item->>'path', '') like 'data:%'
     or p_item ? 'blob' or p_item ? 'file' then
    return 'binary';
  end if;
  v_path := coalesce(p_item->>'objectPath', p_item->>'path', '');
  if v_path = '' then
    -- an attachment object with no managed reference is unrecoverable
    return 'binary';
  end if;
  if char_length(v_path) between 3 and 511
     and v_path ~ '^[A-Za-z0-9][A-Za-z0-9/_.-]*$' then
    return 'stable';
  end if;
  return 'invalid';
end $$;
