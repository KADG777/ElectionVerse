param([string]$ScanFile = '')
$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Inspect staged blobs, never print a matched line or credential value.
$rules = [ordered]@{
    'GitHub token' = '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})'
    'API secret key' = '\bsk-[A-Za-z0-9_-]{20,}'
    'AWS access key' = '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'
    'Private key' = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
    'Credential in URL' = 'https?://[^\s/:@]+:[^\s/@]+@'
}
$assignment = '(?i)\b(?:api[_-]?key|github[_-]?token|gh[_-]?token|access[_-]?token|refresh[_-]?token|password)\b["'']?\s*[:=]\s*["''](?<value>[^"''\r\n]{8,})["'']'
$findings = [System.Collections.Generic.List[string]]::new()
$root = ''
if ([string]::IsNullOrWhiteSpace($ScanFile)) {
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Run this check inside the Git repository.' }
    $files = @(& git -c core.quotepath=false diff --cached --name-only --diff-filter=ACMR)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate staged files.' }
} else {
    $files = @($ScanFile)
}
foreach ($file in $files) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }
    $path = $file.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($ScanFile)) {
        if ($path -match '(^|/)(\.env(?:\..*)?|auth\.json|hosts\.yml|token\.txt|tokens\.json)$' -and $path -notmatch '(^|/)\.env\.example$') {
            $findings.Add("${path}: local credential/configuration file")
        }
        $blob = @(& git -c core.quotepath=false show (':' + $path) 2>$null)
        if ($LASTEXITCODE -ne 0) { throw ('Could not read staged file: ' + $path) }
        $content = $blob -join "`n"
    } else {
        $content = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $file).Path, [Text.Encoding]::UTF8)
    }
    $lines = $content -split "`n"
    for ($index = 0; $index -lt $lines.Count; $index++) {
        foreach ($kind in $rules.Keys) {
            if ([regex]::IsMatch($lines[$index], $rules[$kind])) {
                $findings.Add(('{0}:{1}: {2}' -f $path, ($index + 1), $kind))
            }
        }
        foreach ($match in [regex]::Matches($lines[$index], $assignment)) {
            $value = $match.Groups['value'].Value
            $placeholder = $value -match '^(?:YOUR_[A-Z_]+|<[^>]+>)$'
            $testFixture = $path.StartsWith('tests/') -and $value -match '(?:^|[-_])(?:fixture|tests?|testing|unit|mock|dummy|fake)(?:$|[-_])'
            if (-not $placeholder -and -not $testFixture) {
                $findings.Add(('{0}:{1}: literal credential assignment' -f $path, ($index + 1)))
            }
        }
    }
}
if ($findings.Count -gt 0) {
    Write-Output 'Blocked: possible credentials. Only locations and categories are shown.'
    $findings | Sort-Object -Unique | ForEach-Object { Write-Output $_ }
    exit 1
}
Write-Output ('Credential check passed: {0} staged file(s); no values printed.' -f $files.Count)
exit 0
