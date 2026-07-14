# Diagnostic - writes to disk before doing ANYTHING else
$log = "C:\Users\Public\diag.txt"
[System.IO.File]::AppendAllText($log, "=== START $(Get-Date) ===`r`n")
[System.IO.File]::AppendAllText($log, "PSScriptRoot: $PSScriptRoot`r`n")
[System.IO.File]::AppendAllText($log, "PSCommandPath: $PSCommandPath`r`n")
[System.IO.File]::AppendAllText($log, "IsAdmin: $( ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator') )`r`n")
[System.IO.File]::AppendAllText($log, "PSVersion: $($PSVersionTable.PSVersion)`r`n")

[System.IO.File]::AppendAllText($log, "Testing Add-Type PresentationFramework...`r`n")
try {
    Add-Type -AssemblyName PresentationFramework
    [System.IO.File]::AppendAllText($log, "PresentationFramework: OK`r`n")
} catch {
    [System.IO.File]::AppendAllText($log, "PresentationFramework FAILED: $($_.Exception.Message)`r`n")
}

[System.IO.File]::AppendAllText($log, "Testing WPF window...`r`n")
try {
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    $w = New-Object System.Windows.Window
    $w.Title = "Test"
    $w.Width = 200
    $w.Height = 100
    [System.IO.File]::AppendAllText($log, "Window object created OK`r`n")
    $w.ShowDialog() | Out-Null
    [System.IO.File]::AppendAllText($log, "Window closed OK`r`n")
} catch {
    [System.IO.File]::AppendAllText($log, "WPF FAILED: $($_.Exception.Message)`r`n")
    [System.IO.File]::AppendAllText($log, "Stack: $($_.ScriptStackTrace)`r`n")
}

[System.IO.File]::AppendAllText($log, "=== END ===`r`n")
