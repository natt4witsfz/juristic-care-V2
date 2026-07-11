$ErrorActionPreference = "Stop"

if (-not $env:PRODUCTION_PROMOTION_BIT_HASH) {
  Write-Error "PRODUCTION_PROMOTION_BIT_HASH must be set before production promotion."
}

$bstr = [IntPtr]::Zero
$plain = $null

try {
  $secure = Read-Host -AsSecureString "Production promotion Bit code"
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

  $env:PRODUCTION_PROMOTION_BIT_CODE = $plain
  $env:PRODUCTION_PROMOTION_CONFIRM = "PROMOTE_TO_PRODUCTION"

  node scripts/build-sites-static.mjs --environment production
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}
finally {
  Remove-Item Env:\PRODUCTION_PROMOTION_BIT_CODE -ErrorAction SilentlyContinue
  Remove-Item Env:\PRODUCTION_PROMOTION_CONFIRM -ErrorAction SilentlyContinue
  if ($bstr -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
  $plain = $null
  Remove-Variable plain -ErrorAction SilentlyContinue
}
