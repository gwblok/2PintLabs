<# Grab Info about file C:\Windows\System32\GroupPolicy\Machine\Registry.pol
Report Size and last date modified

Run .\LGPO.exe /m .\Machine.pol inside a start-process and capture the output, and report the results

then once again grab info about that file and confirm it's changed
#>

$polFile = 'C:\Windows\System32\GroupPolicy\Machine\Registry.pol'

# --- Before: Grab file info ---
Write-Output "=== BEFORE ==="
if (Test-Path $polFile) {
    $before = Get-Item $polFile
    Write-Output "  File:          $($before.FullName)"
    Write-Output "  Size (bytes):  $($before.Length)"
    Write-Output "  Last Modified: $($before.LastWriteTime)"
} else {
    Write-Output "  File does not exist: $polFile"
    $before = $null
}

# --- Run LGPO.exe /m .\Machine.pol and capture output ---
Write-Output "`n=== Running LGPO.exe ==="
$lgpoExe = Join-Path $PSScriptRoot 'LGPO.exe'
$machinePol = Join-Path $PSScriptRoot 'Machine.pol'

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $lgpoExe
$psi.Arguments = "/m `"$machinePol`""
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

Write-Output "  Exit Code: $($proc.ExitCode)"
if ($stdout) { Write-Output "  StdOut:`n$stdout" }
if ($stderr) { Write-Output "  StdErr:`n$stderr" }

# --- After: Grab file info again ---
Write-Output "=== AFTER ==="
if (Test-Path $polFile) {
    $after = Get-Item $polFile
    Write-Output "  File:          $($after.FullName)"
    Write-Output "  Size (bytes):  $($after.Length)"
    Write-Output "  Last Modified: $($after.LastWriteTime)"

    # --- Compare ---
    Write-Output "`n=== COMPARISON ==="
    if ($before) {
        $sizeChanged = $before.Length -ne $after.Length
        $dateChanged = $before.LastWriteTime -ne $after.LastWriteTime
        Write-Output "  Size changed:          $sizeChanged  ($($before.Length) -> $($after.Length))"
        Write-Output "  Last Modified changed: $dateChanged  ($($before.LastWriteTime) -> $($after.LastWriteTime))"
        if ($sizeChanged -or $dateChanged) {
            Write-Output "  Result: Registry.pol was UPDATED"
        } else {
            Write-Output "  Result: Registry.pol was NOT changed"
        }
    } else {
        Write-Output "  Result: File was CREATED (did not exist before)"
    }
} else {
    Write-Output "  File does not exist after LGPO run: $polFile"
}>

