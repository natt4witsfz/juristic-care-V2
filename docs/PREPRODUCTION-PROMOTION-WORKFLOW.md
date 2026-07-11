# Pre-Production and Production Promotion Workflow

This project uses two separate Sites projects:

- Pre-Production: tester validation before release
- Production: live deployment, changed only after explicit approval

## Environment URLs

| Environment | Purpose | Sites project |
| --- | --- | --- |
| Pre-Production | User acceptance testing | `appgprj_6a5275267d8481918257207f7d8df2f2` |
| Production | Live app | `appgprj_6a527385dc688191abc5b6c7aa057ee3` |

## Normal Flow

1. Make code changes on a feature branch.
2. Run local verification:
   - `npm run check`
   - `npm test`
   - `npm run build:preprod`
   - `git diff --check`
3. Deploy the validated build to Pre-Production only.
4. Ask testers to validate the Pre-Production URL.
5. Do not deploy Production until the owner explicitly confirms promotion.
6. For Production promotion, the approver must enter the Bit code.
7. For Production promotion, rebuild with:
   - `npm run build:production`
8. Deploy the exact approved commit to Production.

## Guardrails

- Pre-Production and Production use separate Sites project IDs.
- Pre-Production builds include a visible environment banner.
- Production builds do not include the Pre-Production banner.
- Production deployment is not automatic.
- Production deployment requires explicit human confirmation in the task.
- Production bundle creation is blocked unless the approver enters the Bit
  code. The real Bit code is never stored in Git.
- The runtime must provide `PRODUCTION_PROMOTION_BIT_HASH` as the SHA-256
  hex digest of the Bit code before running `npm run build:production`.
- Supabase Production is not touched by this workflow.
- Frontend Secret Keys must never be used; frontend may only contain public
  publishable/anon configuration when a backend cutover is separately approved.

## Current Backend Mode

The committed frontend config still has `SUPABASE_ENABLED: false`, so the
deployed web app remains a pilot/demo frontend unless a separate, approved
backend cutover enables Supabase runtime config.

## Production Bit-Code Setup

Generate the Bit-code hash outside Git and keep only the hash in the secure
operator environment:

```powershell
$bit = Read-Host -AsSecureString "New Production promotion Bit code"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($bit)
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
$bytes = [Text.Encoding]::UTF8.GetBytes($plain)
$hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
$env:PRODUCTION_PROMOTION_BIT_HASH = -join ($hash | ForEach-Object { $_.ToString("x2") })
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
Remove-Variable plain,bytes,hash -ErrorAction SilentlyContinue
```

Then run:

```powershell
npm run build:production
```

The script prompts for the Bit code with `Read-Host -AsSecureString`, compares
it to `PRODUCTION_PROMOTION_BIT_HASH`, and refuses to create the Production
bundle if the code is missing or wrong.
