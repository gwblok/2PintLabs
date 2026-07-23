write-host "Checking if we are running in a Task Sequence" -ForegroundColor Yellow
$script:InTaskSequence = ($null -ne (Get-PSDrive -Name TSEnv -ErrorAction SilentlyContinue))

if ($script:InTaskSequence) {
    write-host "We are running in a Task Sequence" -ForegroundColor Green
}
else {
    write-host "We are NOT running in a Task Sequence" -ForegroundColor Red
}

#actual output
$scrpt:InTaskSequence

