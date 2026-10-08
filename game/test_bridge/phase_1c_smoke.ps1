param(
    [string]$BridgeUrl = 'http://127.0.0.1:18765'
)

$ErrorActionPreference = 'Stop'
$wsUrl = $BridgeUrl -replace '^http', 'ws'
$ws = [System.Net.WebSockets.ClientWebSocket]::new()
[void]$ws.ConnectAsync(
    [Uri]"$wsUrl/events",
    [Threading.CancellationToken]::None
).GetAwaiter().GetResult()

function Get-BridgeSnapshot {
    (Invoke-RestMethod "$BridgeUrl/world/state" -TimeoutSec 5).data
}

function New-SessionCommand([object]$snapshot) {
    $id = [guid]::NewGuid().ToString()
    @{
        commandId = $id
        idempotencyKey = $id
        expectedSessionId = $snapshot.sessionId
        expectedWorldGeneration = $snapshot.worldGeneration
        expectedStateVersion = $snapshot.stateVersion
        timeoutMs = 120000
    }
}

function Invoke-BridgeCommand([string]$name, [hashtable]$command) {
    $body = $command | ConvertTo-Json -Compress
    Invoke-RestMethod "$BridgeUrl/commands/$name" `
        -Method Post `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 8
}

function Wait-BridgeCommand([string]$commandId) {
    $deadline = [DateTime]::UtcNow.AddSeconds(120)
    $lastPollError = ''
    do {
        try {
            $receipt = Invoke-RestMethod "$BridgeUrl/commands/$commandId" -TimeoutSec 5
            $lastPollError = ''
            if ($receipt.data.status -in @('completed', 'failed')) {
                return $receipt.data
            }
        } catch {
            # A formal load can temporarily occupy the game main thread while it
            # replaces the scene. Keep the same command ID and poll again; never
            # submit a second load just because one status request timed out.
            $lastPollError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Command wait timed out: $commandId. Last poll error: $lastPollError"
}

function Receive-BridgeEvent {
    $buffer = [byte[]]::new(8192)
    $segment = [ArraySegment[byte]]::new($buffer)
    $text = [Text.StringBuilder]::new()
    do {
        $cancel = [Threading.CancellationTokenSource]::new(3000)
        try {
            $part = $ws.ReceiveAsync($segment, $cancel.Token).GetAwaiter().GetResult()
        } catch [OperationCanceledException] {
            return $null
        } finally {
            $cancel.Dispose()
        }
        if ($part.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            return $null
        }
        [void]$text.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $part.Count))
    } while (-not $part.EndOfMessage)
    $text.ToString() | ConvertFrom-Json
}

$before = Get-BridgeSnapshot
if ($before.residentCount -ne 15) {
    throw "Expected 15 residents, got residentCount=$($before.residentCount)"
}

$saveCommand = New-SessionCommand $before
$saveAccepted = Invoke-BridgeCommand 'save' $saveCommand
if ($saveAccepted.data.status -ne 'running') {
    throw 'Save command did not enter running state.'
}
Write-Host "SAVE_ACCEPTED commandId=$($saveCommand.commandId)"
$saved = Wait-BridgeCommand $saveCommand.commandId
if ($saved.status -ne 'completed' -or $saved.result.saveRevision -lt 1) {
    throw "Formal save did not complete: $($saved | ConvertTo-Json -Depth 8)"
}
Write-Host "SAVE_COMPLETED revision=$($saved.result.saveRevision)"

$preload = Get-BridgeSnapshot
$loadCommand = New-SessionCommand $preload
$loadAccepted = Invoke-BridgeCommand 'load' $loadCommand
if ($loadAccepted.data.status -ne 'running') {
    throw 'Load command did not enter running state.'
}
Write-Host "LOAD_ACCEPTED commandId=$($loadCommand.commandId)"
$loaded = Wait-BridgeCommand $loadCommand.commandId
if ($loaded.status -ne 'completed') {
    throw "Formal load did not complete: $($loaded | ConvertTo-Json -Depth 8)"
}
Write-Host "LOAD_COMPLETED revision=$($loaded.result.saveRevision)"

$after = Get-BridgeSnapshot
if ($after.sessionId -ne $before.sessionId) {
    throw 'sessionId changed after load.'
}
if ($after.worldGeneration -eq $preload.worldGeneration) {
    throw 'worldGeneration did not change after load.'
}
if ($after.residentCount -ne 15) {
    throw "Resident count after load was $($after.residentCount), expected 15."
}

$events = @()
for ($i = 0; $i -lt 24; $i++) {
    $eventItem = Receive-BridgeEvent
    if ($null -eq $eventItem) { break }
    $events += $eventItem
    $types = @($events | ForEach-Object { $_.eventType })
    $commandIds = @($events | ForEach-Object { $_.commandId })
    if (
        'state-version-changed' -in $types -and
        $saveCommand.commandId -in $commandIds -and
        $loadCommand.commandId -in $commandIds
    ) { break }
}

$eventTypes = @($events | ForEach-Object { $_.eventType })
$eventCommandIds = @($events | ForEach-Object { $_.commandId })
if ('state-version-changed' -notin $eventTypes) {
    throw 'Missing state-version-changed event.'
}
if ($saveCommand.commandId -notin $eventCommandIds) {
    throw 'Missing save completion event.'
}
if ($loadCommand.commandId -notin $eventCommandIds) {
    throw 'Missing load completion event.'
}

$ws.Dispose()
[pscustomobject]@{
    Result = 'PHASE_1C_SMOKE_PASS'
    SessionId = $after.sessionId
    ResidentCount = $after.residentCount
    SavedRevision = $saved.result.saveRevision
    PreviousWorldGeneration = $preload.worldGeneration
    CurrentWorldGeneration = $after.worldGeneration
    EventCount = $events.Count
    EventTypes = ($eventTypes -join ',')
}
