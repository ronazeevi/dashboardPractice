# Builds dashboard.html from Airtable (base "MUEHEDET BASE") instead of the CSV files.
# Requires env vars: AIRTABLE_TOKEN (personal access token, scope data.records:read) and AIRTABLE_BASE_ID (appXXXXXXXX).
# Tables expected: labs, workers, monthly_tests. lab_id may be a linked-record field or plain text.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
  foreach ($line in [IO.File]::ReadAllLines($envFile)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2].Trim('"', "'") }
  }
}
$token = $env:AIRTABLE_TOKEN; $base = $env:AIRTABLE_BASE_ID
if (-not $token -or $token -like 'PASTE_*' -or -not $base -or $base -like 'PASTE_*') { throw 'Fill AIRTABLE_TOKEN and AIRTABLE_BASE_ID in the .env file (same folder as this script).' }
$hdr = @{ Authorization = "Bearer $token" }

function Get-All($table) {
  $out = New-Object System.Collections.Generic.List[object]; $offset = $null
  do {
    $u = "https://api.airtable.com/v0/$base/$([uri]::EscapeDataString($table))?pageSize=100" + $(if ($offset) { "&offset=$offset" })
    $r = Invoke-RestMethod -Uri $u -Headers $hdr
    foreach ($rec in $r.records) {
      # normalise field names: "Lab Id" / "Lab_ID" -> lab_id
      $n = [ordered]@{}
      foreach ($p in $rec.fields.PSObject.Properties) { $n[($p.Name.Trim().ToLower() -replace '\s+', '_')] = $p.Value }
      $out.Add([pscustomobject]@{ id = $rec.id; fields = [pscustomobject]$n })
    }
    $offset = $r.offset
  } while ($offset)
  $out
}

$labsRaw = Get-All 'Labs'
$labs = @($labsRaw | ForEach-Object { [pscustomobject]@{ rid = $_.id; lab_id = [string]$_.fields.lab_id; lab_name = $_.fields.lab_name; city = $_.fields.city; region = $_.fields.region } } | Sort-Object lab_id)
$idx = @{}; $rid2lab = @{}
for ($i = 0; $i -lt $labs.Count; $i++) { $idx[$labs[$i].lab_id] = $i; $rid2lab[$labs[$i].rid] = $labs[$i].lab_id }

function Resolve-Lab($v) {
  if ($v -is [array]) { $v = $v[0] }
  if ($rid2lab.ContainsKey([string]$v)) { return $rid2lab[[string]$v] }
  [string]$v
}

function Get-Month($period) {
  $p = ([string]$period).Trim()
  $names = 'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'
  if ($p -match '^\d{4}[-/.](\d{1,2})') { return [int]$Matches[1] }
  if ($p -match '^(\d{1,2})[-/.]\d{4}') { return [int]$Matches[1] }
  if ($p -match '^\d{1,2}$') { return [int]$p }
  $i = [Array]::IndexOf($names, $p.Substring(0, [Math]::Min(3, $p.Length)).ToLower())
  if ($i -ge 0) { return $i + 1 }
  throw "Cannot read month from period value '$p' - tell Claude this format."
}
$workers = Get-All 'Workers' | ForEach-Object { $f = $_.fields; , @($f.worker_id, $f.full_name, $f.role, $idx[(Resolve-Lab $f.lab)]) }
$rows = Get-All 'Monthly Tests' | ForEach-Object { $f = $_.fields; , @($idx[(Resolve-Lab $f.lab)], [int]$f.year, (Get-Month $f.period), [double]$f.tests, [double]$f.avg_turnaround_hours, [double]$f.'abnormal_%') }

$data = [ordered]@{
  labs = @($labs | ForEach-Object { , @($_.lab_id, $_.lab_name, $_.city, $_.region) })
  workers = @($workers)
  rows = @($rows)
}
$json = $data | ConvertTo-Json -Depth 5 -Compress
$tpl = [IO.File]::ReadAllText((Join-Path $root 'dashboard.template.html'), $utf8)
$apifyJson = '[]'
$apifyFile = Join-Path $root 'apify-labs.json'
if (Test-Path $apifyFile) {
  $cache = [IO.File]::ReadAllText($apifyFile, $utf8) | ConvertFrom-Json
  $places = New-Object System.Collections.Generic.List[object]
  foreach ($c in $cache.PSObject.Properties) {
    foreach ($p in @($c.Value)) { if ($p.name) { $places.Add(@($c.Name, $p.name, $p.address, $p.lat, $p.lng, $p.phone, $p.rating)) } }
  }
  if ($places.Count) { $apifyJson = '[' + (($places | ForEach-Object { '[' + (($_ | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ',') + ']' }) -join ',') + ']' }
}
$html = $tpl.Replace('__DATA__', $json).Replace('__APIFY__', $apifyJson)
$logoPath = Join-Path $root 'logo.png'
if (Test-Path $logoPath) {
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($logoPath))
  $html = $html.Replace('src="logo.png"', 'src="data:image/png;base64,' + $b64 + '"')
}
[IO.File]::WriteAllText((Join-Path $root 'dashboard.html'), $html, $utf8)
"labs=$($labs.Count) workers=$(@($workers).Count) rows=$(@($rows).Count)"
