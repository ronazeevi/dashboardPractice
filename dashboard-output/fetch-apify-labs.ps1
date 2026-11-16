# Fetches real blood-test laboratory locations near each lab city (cities come from Airtable "Labs")
# using the Apify Actor "Google Maps Scraper" (compass/crawler-google-places).
# Results are cached in apify-labs.json, so each city is only fetched once (saves Apify credits).
# Requires .env: AIRTABLE_TOKEN, AIRTABLE_BASE_ID, APIFY_TOKEN.  Optional: APIFY_MAX_PER_CITY (default 3).
# Run:  powershell -ExecutionPolicy Bypass -File fetch-apify-labs.ps1   [-Refresh to re-fetch everything]
param([switch]$Refresh)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
  foreach ($line in [IO.File]::ReadAllLines($envFile)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim('"', "'") }
  }
}
foreach ($k in 'AIRTABLE_TOKEN', 'AIRTABLE_BASE_ID', 'APIFY_TOKEN') {
  $v = [Environment]::GetEnvironmentVariable($k)
  if (-not $v -or $v -like 'PASTE_*') { throw "Fill $k in the .env file." }
}
$max = if ($env:APIFY_MAX_PER_CITY) { [int]$env:APIFY_MAX_PER_CITY } else { 3 }

# 1. distinct cities from Airtable
$hdr = @{ Authorization = "Bearer $env:AIRTABLE_TOKEN" }
$cities = New-Object System.Collections.Generic.HashSet[string]; $offset = $null
do {
  $u = "https://api.airtable.com/v0/$env:AIRTABLE_BASE_ID/Labs?pageSize=100" + $(if ($offset) { "&offset=$offset" })
  $r = Invoke-RestMethod -Uri $u -Headers $hdr
  foreach ($rec in $r.records) {
    foreach ($p in $rec.fields.PSObject.Properties) { if ($p.Name.Trim().ToLower() -eq 'city' -and $p.Value) { [void]$cities.Add([string]$p.Value) } }
  }
  $offset = $r.offset
} while ($offset)

# 2. cache
$cacheFile = Join-Path $root 'apify-labs.json'
$cache = @{}
if ((Test-Path $cacheFile) -and -not $Refresh) {
  $obj = [IO.File]::ReadAllText($cacheFile, $utf8) | ConvertFrom-Json
  foreach ($p in $obj.PSObject.Properties) { $cache[$p.Name] = @($p.Value) }
}

# 3. one Apify run per missing city
$apify = @{ Authorization = "Bearer $env:APIFY_TOKEN" }
$todo = @($cities | Where-Object { -not $cache.ContainsKey($_) } | Sort-Object)
"cities=$($cities.Count) cached=$($cities.Count - $todo.Count) to fetch=$($todo.Count) (max $max places each)"
foreach ($city in $todo) {
  try {
    $body = @{ searchStringsArray = @('blood test laboratory'); locationQuery = "$city, Israel"; maxCrawledPlacesPerSearch = $max; language = 'iw' } | ConvertTo-Json
    $res = Invoke-RestMethod -Method Post -Uri 'https://api.apify.com/v2/acts/compass~crawler-google-places/run-sync-get-dataset-items' -Headers $apify -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 280
    $cache[$city] = @($res | Where-Object { $_.location -and -not $_.permanentlyClosed } | ForEach-Object {
        [pscustomobject]@{ name = $_.title; address = $_.address; lat = $_.location.lat; lng = $_.location.lng; phone = $_.phone; rating = $_.totalScore; url = $_.url }
      })
    "ok   $city -> $($cache[$city].Count) places"
  } catch { "FAIL $city : $($_.Exception.Message) $($_.ErrorDetails.Message)" }
  [IO.File]::WriteAllText($cacheFile, ($cache | ConvertTo-Json -Depth 5), $utf8)   # save progress after each city
}
$total = ($cache.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
"saved apify-labs.json: cities=$($cache.Count) places=$total"
