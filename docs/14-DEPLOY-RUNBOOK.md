# Deploy Runbook

## 1. Create Supabase Project

Create a Supabase project and copy:

- Project URL
- anon/publishable key
- service role key for Edge Functions only

## 2. Run Migration

Run:

```sql
supabase/migrations/202607090001_full_supabase_schema.sql
```

Confirm:

- tables exist
- RLS enabled
- buckets are private
- RPC functions exist

## 3. Deploy Edge Functions

Deploy:

- `admin-users`
- `google-forms-ingest`
- `secure-file-access`

Set secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `GOOGLE_FORMS_INGEST_SECRET`

## 4. Configure Frontend

Edit `config.js`:

```js
SUPABASE_ENABLED: true,
SUPABASE_URL: "https://PROJECT.supabase.co",
SUPABASE_ANON_KEY: "public-anon-key"
```

Do not add service role key to frontend.

## 5. Smoke Test

Run the QA checklist in `10-QA-CHECKLIST.md`.
