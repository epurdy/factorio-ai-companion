param([string]$taskId, [int]$timeoutSec = 120)

$file = "C:\Users\lveil\AppData\Local\Temp\claude\C--Users-lveil-Desktop-Projects-factorio-ai-companion\tasks\$taskId.output"
$start = Get-Date

while ((Get-Date) -lt $start.AddSeconds($timeoutSec)) {
    if (Test-Path $file) {
        $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
        if ($content -match '\{"companionId"') {
            Write-Output $content
            exit 0
        }
    }
    Start-Sleep -Seconds 2
}

if (Test-Path $file) {
    Get-Content $file -Raw
} else {
    Write-Output "Timeout waiting for message"
}
exit 1
