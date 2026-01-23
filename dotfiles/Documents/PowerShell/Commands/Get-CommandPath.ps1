function Get-CommandPath ([string[]]$Name, [switch]$All) {
    foreach ($n in $Name) {
        try {
            Get-Command $n -All:$All -ErrorAction Stop |
                ForEach-Object { $_.Path ?? $_.Source }
        } catch {
            Write-Error "Command '$n' not found."
        }
    }
}
