# Loads KEY=VALUE lines from .env into this PowerShell session (ignores comments)
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#=\s][^=]*)=(.*)$') {
        $name  = $matches[1].Trim()
        $value = ($matches[2] -replace '\s+#.*$', '').Trim()
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
}
Write-Host "Loaded .env"
