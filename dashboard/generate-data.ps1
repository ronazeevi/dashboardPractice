# Generates SYNTHETIC sample data (labs.csv, workers.csv, monthly_tests.csv) and builds dashboard.html
# NOT real Meuhedet data. Replace the CSVs with real exports when available.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$utf8bom = New-Object System.Text.UTF8Encoding($true)
function Read-Lines($f) { [IO.File]::ReadAllLines((Join-Path $root "seed\$f"), $utf8) | Where-Object { $_.Trim() } }

$cities = Read-Lines 'cities.txt'
$roles = @(Read-Lines 'roles.txt')
$first = @(Read-Lines 'firstnames.txt')
$last = @(Read-Lines 'lastnames.txt')
$prefix = ([IO.File]::ReadAllText((Join-Path $root 'seed/labprefix.txt'), $utf8)).Trim() + ' '
$rnd = New-Object System.Random 2026

$labs = New-Object System.Collections.Generic.List[object]
$n = 0
foreach ($line in $cities) {
  $p = $line.Split('|'); $city = $p[0]; $region = $p[1]; $w = [int]$p[2]
  $count = [Math]::Max(1, [Math]::Floor($w / 3))
  for ($i = 1; $i -le $count; $i++) {
    $n++
    $name = $prefix + $city
    if ($count -gt 1) { $name += " $i" }
    $labs.Add([pscustomobject]@{ lab_id = ('L{0:D3}' -f $n); lab_name = $name; city = $city; region = $region; weight = ($w / $count) })
  }
}

# workers
$workers = New-Object System.Collections.Generic.List[object]
$wn = 0
foreach ($l in $labs) {
  $staff = 3 + [int][Math]::Round($l.weight * 1.2) + $rnd.Next(0, 3)
  for ($i = 0; $i -lt $staff; $i++) {
    $wn++
    $role = if ($i -eq 0) { $roles[0] } else { $roles[1 + $rnd.Next(0, $roles.Count - 1)] }
    $workers.Add([pscustomobject]@{
      worker_id = ('W{0:D4}' -f $wn)
      full_name = ($first[$rnd.Next(0, $first.Count)] + ' ' + $last[$rnd.Next(0, $last.Count)])
      role = $role; lab_id = $l.lab_id; lab_name = $l.lab_name; city = $l.city; region = $l.region
    })
  }
}

# monthly tests 2023-01 .. 2026-10
$rows = New-Object System.Collections.Generic.List[object]
foreach ($l in $labs) {
  $base = 900 * $l.weight
  for ($y = 2023; $y -le 2026; $y++) {
    for ($m = 1; $m -le 12; $m++) {
      if ($y -eq 2026 -and $m -gt 10) { break }
      $season = if ($m -in 11, 12, 1, 2, 3) { 1.10 } elseif ($m -in 7, 8) { 0.92 } else { 1.0 }
      $growth = [Math]::Pow(1.04, ($y - 2023) + ($m - 1) / 12)
      $tests = [int]($base * $season * $growth * (0.93 + $rnd.NextDouble() * 0.14))
      $tat = [Math]::Round(18 + $rnd.NextDouble() * 10 - ($y - 2023) * 0.8, 1)
      $abn = [Math]::Round(11 + $rnd.NextDouble() * 5, 1)
      $rows.Add([pscustomobject]@{ lab_id = $l.lab_id; year = $y; month = $m; tests = $tests; avg_turnaround_hours = $tat; abnormal_pct = $abn })
    }
  }
}

$labs | Select-Object lab_id, lab_name, city, region | Export-Csv (Join-Path $root 'labs.csv') -NoTypeInformation -Encoding UTF8
$workers | Export-Csv (Join-Path $root 'workers.csv') -NoTypeInformation -Encoding UTF8
$rows | Export-Csv (Join-Path $root 'monthly_tests.csv') -NoTypeInformation -Encoding UTF8

# embed data in dashboard
$idx = @{}; for ($i = 0; $i -lt $labs.Count; $i++) { $idx[$labs[$i].lab_id] = $i }
$data = [ordered]@{
  labs = @($labs | ForEach-Object { , @($_.lab_id, $_.lab_name, $_.city, $_.region) })
  workers = @($workers | ForEach-Object { , @($_.worker_id, $_.full_name, $_.role, $idx[$_.lab_id]) })
  rows = @($rows | ForEach-Object { , @($idx[$_.lab_id], $_.year, $_.month, $_.tests, $_.avg_turnaround_hours, $_.abnormal_pct) })
}
$json = $data | ConvertTo-Json -Depth 5 -Compress
$tpl = [IO.File]::ReadAllText((Join-Path $root 'dashboard.template.html'), $utf8)
$html = $tpl.Replace('__DATA__', $json)
$logoPath = Join-Path $root 'logo.png'
if (Test-Path $logoPath) {
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($logoPath))
  $html = $html.Replace('src="logo.png"', 'src="data:image/png;base64,' + $b64 + '"')
}
[IO.File]::WriteAllText((Join-Path $root 'dashboard.html'), $html, $utf8)
"labs=$($labs.Count) workers=$($workers.Count) rows=$($rows.Count)"
