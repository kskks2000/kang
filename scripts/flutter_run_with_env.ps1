[CmdletBinding()]
param(
    [string]$Device = "chrome",
    [string]$Flutter = "C:\src\flutter\bin\flutter.bat",
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$frontendDir = Join-Path $repoRoot "frontend"

function Read-DotEnv {
    param([string]$Path)

    $values = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $values
    }

    foreach ($rawLine in Get-Content -Encoding utf8 $Path) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            continue
        }

        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if ($value.Length -ge 2) {
            $first = $value.Substring(0, 1)
            $last = $value.Substring($value.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        if ($key.Length -gt 0) {
            $values[$key] = $value
        }
    }

    return $values
}

function Test-UsableValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $trimmed = $Value.Trim()
    return -not ($trimmed.StartsWith("<") -and $trimmed.EndsWith(">"))
}

$dotenv = [ordered]@{}
foreach ($path in @((Join-Path $repoRoot ".env"), (Join-Path $repoRoot "backend\.env"))) {
    $fileValues = Read-DotEnv -Path $path
    foreach ($key in $fileValues.Keys) {
        $dotenv[$key] = $fileValues[$key]
    }
}

$dartDefineKeys = @(
    "API_BASE_URL",
    "FIREBASE_API_KEY",
    "FIREBASE_PROJECT_ID",
    "FIREBASE_WEB_APP_ID",
    "FIREBASE_MESSAGING_SENDER_ID",
    "FIREBASE_AUTH_DOMAIN",
    "FIREBASE_STORAGE_BUCKET",
    "FIREBASE_ANDROID_APP_ID",
    "FIREBASE_IOS_APP_ID",
    "FIREBASE_IOS_BUNDLE_ID"
)

$defineArgs = @()
foreach ($key in $dartDefineKeys) {
    $value = [Environment]::GetEnvironmentVariable($key, "Process")
    if (-not (Test-UsableValue -Value $value) -and $dotenv.Contains($key)) {
        $value = [string]$dotenv[$key]
    }

    if (Test-UsableValue -Value $value) {
        $defineArgs += "--dart-define=$key=$value"
    }
}

Push-Location $frontendDir
try {
    & $Flutter run -d $Device @defineArgs @ExtraArgs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
