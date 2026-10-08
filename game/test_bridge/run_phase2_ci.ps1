# Updated: 2026-10-02 12:20:00 +08:00 (Asia/Shanghai)
[CmdletBinding()]
param(
    [ValidateSet('all', 'preflight', 'static', 'pytest', 'godot', 'newman', 'evidence')]
    [string]$Stage = 'all',
    [string]$RunId = '',
    [string]$BuildNumber = 'local',
    [string]$ArtifactsRoot = '',
    [string]$PythonPath = '',
    [string]$GodotPath = '',
    [string]$NewmanPath = '',
    [ValidateSet('local', 'github-actions', 'jenkins')]
    [string]$ExecutionMode = 'local'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptRoot '..\..')).Path
$gameRoot = Join-Path $repoRoot 'game'
if ([string]::IsNullOrWhiteSpace($ArtifactsRoot)) {
    $ArtifactsRoot = Join-Path $scriptRoot 'artifacts'
}
$ArtifactsRoot = [System.IO.Path]::GetFullPath($ArtifactsRoot)
if (-not (Test-Path -LiteralPath $ArtifactsRoot -PathType Container)) {
    throw "Evidence directory must already exist: $ArtifactsRoot"
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = 'local-{0}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
}
$RunId = $RunId -replace '[^A-Za-z0-9_.-]', '-'

function Resolve-ToolPath {
    param([string]$Configured, [string[]]$Commands, [string]$LocalFallback)
    if (-not [string]::IsNullOrWhiteSpace($Configured)) {
        return [System.IO.Path]::GetFullPath($Configured)
    }
    if (Test-Path -LiteralPath $LocalFallback -PathType Leaf) {
        return $LocalFallback
    }
    foreach ($commandName in $Commands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    throw "Required tool not found; pass its explicit path: $($Commands -join ', ')"
}

$pythonPath = Resolve-ToolPath -Configured $PythonPath -Commands @('python.exe', 'python') -LocalFallback 'D:\Anaconda\envs\gametest-phase2\python.exe'
$godotPath = Resolve-ToolPath -Configured $GodotPath -Commands @('godot.exe', 'godot') -LocalFallback 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'
$newmanPath = Resolve-ToolPath -Configured $NewmanPath -Commands @('newman.cmd', 'newman') -LocalFallback 'C:\Users\Administrator\AppData\Roaming\npm\newman.cmd'
$expectedStages = @('preflight', 'static', 'pytest', 'godot', 'newman')
$stageReportPaths = @()

function Get-TextSha256 {
    param([AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-DirectoryBytes {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [int64]0
    }
    $measurement = Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($null -eq $measurement) {
        return [int64]0
    }
    return [int64]($measurement.Sum)
}

function Get-NativeOutput {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    # Windows PowerShell 5.1 turns native stderr into ErrorRecords. Preserve it
    # without treating a warning as a terminating error before reading the exit code.
    $previousNativeErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousNativeErrorAction
    }
    if ($exitCode -ne 0) {
        throw "Command failed with exit code $exitCode`: $FilePath $($Arguments -join ' ')`n$($output | Out-String)"
    }
    return (($output | Out-String).Trim())
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$LogPath,
        [switch]$Append
    )
    $header = "COMMAND: $FilePath $($Arguments -join ' ')"
    if ($Append) {
        Add-Content -LiteralPath $LogPath -Value $header -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $LogPath -Value $header -Encoding UTF8
    }
    $previousNativeErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousNativeErrorAction
    }
    # Tee-Object in Windows PowerShell 5.1 would append UTF-16 to our UTF-8 header.
    $output | ForEach-Object {
        Add-Content -LiteralPath $LogPath -Value $_ -Encoding UTF8
        Write-Host $_
    }
    if ($exitCode -ne 0) {
        throw "Command failed with exit code $exitCode`: $FilePath $($Arguments -join ' ')"
    }
}

function Get-SourceFingerprint {
    $head = Get-NativeOutput -FilePath 'git' -Arguments @('-C', $repoRoot, 'rev-parse', 'HEAD')
    $trackedDiff = Get-NativeOutput -FilePath 'git' -Arguments @('-C', $repoRoot, 'diff', '--binary')
    $untrackedPaths = @(
        Get-NativeOutput -FilePath 'git' -Arguments @(
            '-C', $repoRoot, 'ls-files', '--others', '--exclude-standard'
        )
    ) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object
    $untrackedManifest = foreach ($relativePath in $untrackedPaths) {
        $fullPath = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            "$relativePath|$hash"
        }
    }
    $status = Get-NativeOutput -FilePath 'git' -Arguments @('-C', $repoRoot, 'status', '--porcelain')
    return [ordered]@{
        head = $head.Trim()
        dirty = -not [string]::IsNullOrWhiteSpace($status)
        trackedDiffSha256 = Get-TextSha256 -Text $trackedDiff
        untrackedSha256 = Get-TextSha256 -Text ($untrackedManifest -join "`n")
        untrackedFileCount = @($untrackedManifest).Count
    }
}

function Write-JsonFile {
    param(
        [object]$Value,
        [string]$Path
    )
    $json = ($Value | ConvertTo-Json -Depth 12) + "`n"
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8WithoutBom)
}

function Invoke-PreflightStage {
    foreach ($path in @($pythonPath, $godotPath, $newmanPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required tool is missing: $path"
        }
    }
    $listener = Get-NetTCPConnection -LocalPort 18865 -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        throw "Port 18865 is already in use by PID $($listener[0].OwningProcess)"
    }

    $versions = [ordered]@{
        python = Get-NativeOutput -FilePath $pythonPath -Arguments @('--version')
        pytest = Get-NativeOutput -FilePath $pythonPath -Arguments @('-m', 'pytest', '--version')
        pylint = (Get-NativeOutput -FilePath $pythonPath -Arguments @('-m', 'pylint', '--version')).Split("`n")[0]
        godot = Get-NativeOutput -FilePath $godotPath -Arguments @('--version')
        node = Get-NativeOutput -FilePath 'node' -Arguments @('--version')
        newman = Get-NativeOutput -FilePath $newmanPath -Arguments @('--version')
    }
    $expected = [ordered]@{
        python = 'Python 3.11.'
        pytest = 'pytest 8.3.4'
        pylint = 'pylint 2.14.5'
        godot = '4.7.2.stable.official.ed1daf0bf'
        node = 'v24.19.0'
        newman = '6.2.2'
    }
    foreach ($name in $expected.Keys) {
        if (-not $versions[$name].StartsWith($expected[$name], [StringComparison]::OrdinalIgnoreCase)) {
            throw "Tool version mismatch for $name`: expected '$($expected[$name])', got '$($versions[$name])'"
        }
    }

    # PS 5.1's provider Free can be null when CIM access is unavailable.
    # Query the filesystem directly; never interpret missing telemetry as zero.
    $drive = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($repoRoot))
    $driveFreeBytes = $drive.AvailableFreeSpace
    if ($driveFreeBytes -lt 10GB) {
        throw "Less than 10 GiB free on $($drive.Name) drive"
    }
    $artifactsBytes = Get-DirectoryBytes -Path $ArtifactsRoot
    if ($artifactsBytes -gt 5GB) {
        throw "Evidence directory exceeds 5 GiB; manual review is required before adding builds"
    }

    $metadataPath = Join-Path $ArtifactsRoot "$RunId-preflight-metadata.json"
    $metadata = [ordered]@{
        runId = $RunId
        buildNumber = $BuildNumber
        recordedAt = [DateTime]::UtcNow.ToString('o')
        sourceFingerprint = Get-SourceFingerprint
        toolVersions = $versions
        disk = [ordered]@{
            driveFreeBytes = [int64]$driveFreeBytes
            artifactsBytes = $artifactsBytes
            warningThresholdBytes = 5GB
        }
    }
    Write-JsonFile -Value $metadata -Path $metadataPath
    $script:stageReportPaths = @($metadataPath)
    Write-Host "CI_PREFLIGHT_PASS runId=$RunId artifactsBytes=$artifactsBytes"
}

function Invoke-StaticStage {
    $logPath = Join-Path $ArtifactsRoot "$RunId-static.log"
    Invoke-LoggedCommand -FilePath $pythonPath -Arguments @(
        '-B', '-c',
        'from pathlib import Path; files = [p for p in Path(''game/test_bridge'').rglob(''*.py'') if ''artifacts'' not in p.parts]; [compile(p.read_text(encoding=''utf-8''), str(p), ''exec'') for p in files]; print(''PYTHON_SYNTAX_PASS files='' + str(len(files)))'
    ) -LogPath $logPath
    Invoke-LoggedCommand -FilePath $pythonPath -Arguments @(
        '-B', '-m', 'pylint',
        '--persistent=no',
        'game/test_bridge/evidence_store.py',
        'game/test_bridge/evidence_import.py',
        'game/test_bridge/phase2_tests'
    ) -LogPath $logPath -Append
    $script:stageReportPaths = @($logPath)
}

function Invoke-PytestStage {
    $junitPath = Join-Path $ArtifactsRoot "$RunId-pytest-junit.xml"
    $logPath = Join-Path $ArtifactsRoot "$RunId-pytest.log"
    $tempPath = Join-Path $ArtifactsRoot "$RunId-pytest-temp"
    if (Test-Path -LiteralPath $tempPath) {
        throw 'Refusing to reuse pytest basetemp: existing evidence must be retained'
    }
    Invoke-LoggedCommand -FilePath $pythonPath -Arguments @(
        '-B',
        '-m', 'pytest',
        '-p', 'no:cacheprovider',
        '-c', 'game/test_bridge/pytest.ini',
        'game/test_bridge/phase2_tests',
        '-q',
        "--godot-bin=$godotPath",
        "--evidence-root=$ArtifactsRoot",
        "--basetemp=$tempPath",
        "--junitxml=$junitPath"
    ) -LogPath $logPath
    $script:stageReportPaths = @($junitPath, $logPath)
}

function Invoke-GodotStage {
    $logPath = Join-Path $ArtifactsRoot "$RunId-godot.log"
    $script:stageReportPaths = @($logPath)
    Invoke-LoggedCommand -FilePath $godotPath -Arguments @(
        '--headless',
        '--path', $gameRoot,
        '--log-file', (Join-Path $ArtifactsRoot "$RunId-godot-engine.log"),
        '--script', 'res://tests/game_test_bridge_test.gd',
        '--', '--gametest-isolated-test'
    ) -LogPath $logPath
    $content = Get-Content -LiteralPath $logPath -Raw
    if ($content -notmatch 'GAMETEST_BRIDGE_PASS checks=') {
        throw 'Godot test exited without the GAMETEST_BRIDGE_PASS marker'
    }
}

function Invoke-NewmanStage {
    $stdoutPath = Join-Path $ArtifactsRoot "$RunId-newman-server.log"
    $stderrPath = Join-Path $ArtifactsRoot "$RunId-newman-server-error.log"
    $jsonPath = Join-Path $ArtifactsRoot "$RunId-newman.json"
    $junitPath = Join-Path $ArtifactsRoot "$RunId-newman-junit.xml"
    $logPath = Join-Path $ArtifactsRoot "$RunId-newman.log"
    $importLogPath = Join-Path $ArtifactsRoot "$RunId-newman-import.log"
    $bridgeProcess = $null
    try {
        $bridgeProcess = Start-Process -FilePath $godotPath -ArgumentList @(
            '--headless',
            '--path', $gameRoot,
            '--log-file', (Join-Path $ArtifactsRoot "$RunId-newman-engine.log"),
            '--script', 'res://tests/game_test_bridge_test.gd',
            '--', '--gametest-isolated-test', '--bridge-smoke-server'
        ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

        $deadline = [DateTime]::UtcNow.AddSeconds(40)
        $ready = $false
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($bridgeProcess.HasExited) {
                throw "Bridge fixture exited before readiness with code $($bridgeProcess.ExitCode)"
            }
            try {
                $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18865/health' -TimeoutSec 2
                if ($health.ok -and $health.data.bridgeReady -and $health.data.worldReady) {
                    $ready = $true
                    break
                }
            }
            catch {
                Start-Sleep -Milliseconds 250
            }
        }
        if (-not $ready) {
            throw 'Bridge fixture did not become ready within 40 seconds'
        }

        Invoke-LoggedCommand -FilePath $newmanPath -Arguments @(
            'run',
            'game/test_bridge/postman/GameTestBridge.postman_collection.json',
            '-e', 'game/test_bridge/postman/local-isolated.postman_environment.json',
            '-r', 'cli,json,junit',
            '--reporter-json-export', $jsonPath,
            '--reporter-junit-export', $junitPath
        ) -LogPath $logPath
        Invoke-LoggedCommand -FilePath $pythonPath -Arguments @(
            '-B',
            '-m', 'game.test_bridge.evidence_import',
            '--evidence-root', $ArtifactsRoot,
            'newman', '--report', $jsonPath
        ) -LogPath $importLogPath
    }
    finally {
        if ($null -ne $bridgeProcess -and -not $bridgeProcess.HasExited) {
            Stop-Process -Id $bridgeProcess.Id -Force
            $bridgeProcess.WaitForExit(5000) | Out-Null
        }
    }
    $script:stageReportPaths = @(
        $stdoutPath,
        $stderrPath,
        $jsonPath,
        $junitPath,
        $logPath,
        $importLogPath
    )
}

function Invoke-EvidenceStage {
    $metadataPath = Join-Path $ArtifactsRoot "$RunId-preflight-metadata.json"
    if (Test-Path -LiteralPath $metadataPath) {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    }
    else {
        $metadata = [pscustomobject]@{
            sourceFingerprint = Get-SourceFingerprint
            toolVersions = [ordered]@{}
            disk = [ordered]@{}
        }
    }

    $records = @()
    foreach ($name in $expectedStages) {
        $recordPath = Join-Path $ArtifactsRoot "$RunId-stage-$name.json"
        if (Test-Path -LiteralPath $recordPath) {
            $records += Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
        }
        else {
            $records += [pscustomobject]@{
                name = $name
                status = 'skipped'
                durationMs = 0.0
                exitCode = $null
                errorType = 'StageNotRun'
                message = 'Stage did not run because an earlier stage failed or the summary was requested early.'
                reportPaths = @()
            }
        }
    }
    $failed = @($records | Where-Object { $_.status -eq 'failed' }).Count
    $skipped = @($records | Where-Object { $_.status -eq 'skipped' }).Count
    $summaryPath = Join-Path $ArtifactsRoot "$RunId-ci-summary.json"
    $summary = [ordered]@{
        runId = $RunId
        buildNumber = $BuildNumber
        executionMode = $ExecutionMode
        status = if ($failed -eq 0 -and $skipped -eq 0) { 'passed' } else { 'failed' }
        durationMs = [double](($records | Measure-Object -Property durationMs -Sum).Sum)
        sourceFingerprint = $metadata.sourceFingerprint
        toolVersions = $metadata.toolVersions
        disk = [ordered]@{
            driveFreeBytes = $metadata.disk.driveFreeBytes
            artifactsBytesBefore = $metadata.disk.artifactsBytes
            artifactsBytesAfter = Get-DirectoryBytes -Path $ArtifactsRoot
            warningThresholdBytes = 5GB
        }
        stages = $records
    }
    Write-JsonFile -Value $summary -Path $summaryPath
    $importLogPath = Join-Path $ArtifactsRoot "$RunId-ci-import.log"
    Invoke-LoggedCommand -FilePath $pythonPath -Arguments @(
        '-m', 'game.test_bridge.evidence_import',
        '--evidence-root', $ArtifactsRoot,
        'ci', '--summary', $summaryPath
    ) -LogPath $importLogPath
    $script:stageReportPaths = @($summaryPath, $importLogPath)
}

function Invoke-CiStage {
    param([string]$Name)
    $script:stageReportPaths = @()
    $started = [System.Diagnostics.Stopwatch]::StartNew()
    $status = 'passed'
    $exitCode = 0
    $errorType = $null
    $message = $null
    try {
        switch ($Name) {
            'preflight' { Invoke-PreflightStage }
            'static' { Invoke-StaticStage }
            'pytest' { Invoke-PytestStage }
            'godot' { Invoke-GodotStage }
            'newman' { Invoke-NewmanStage }
            'evidence' { Invoke-EvidenceStage }
            default { throw "Unsupported CI stage: $Name" }
        }
    }
    catch {
        $status = 'failed'
        $exitCode = 1
        $errorType = $_.Exception.GetType().Name
        $message = $_.Exception.Message
        throw
    }
    finally {
        $started.Stop()
        if ($Name -ne 'evidence') {
            $recordPath = Join-Path $ArtifactsRoot "$RunId-stage-$Name.json"
            Write-JsonFile -Path $recordPath -Value ([ordered]@{
                name = $Name
                status = $status
                durationMs = $started.Elapsed.TotalMilliseconds
                exitCode = $exitCode
                errorType = $errorType
                message = $message
                reportPaths = @($script:stageReportPaths | ForEach-Object {
                    [System.IO.Path]::GetFullPath($_)
                })
            })
        }
        Write-Host "CI_STAGE_RESULT name=$Name status=$status durationMs=$([Math]::Round($started.Elapsed.TotalMilliseconds, 1))"
    }
}

Set-Location $repoRoot
if ($Stage -eq 'all') {
    $allFailed = $false
    foreach ($name in $expectedStages) {
        try {
            Invoke-CiStage -Name $name
        }
        catch {
            Write-Error -ErrorAction Continue $_
            $allFailed = $true
            break
        }
    }
    try {
        Invoke-CiStage -Name 'evidence'
    }
    catch {
        Write-Error -ErrorAction Continue $_
        $allFailed = $true
    }
    if ($allFailed) {
        exit 1
    }
    exit 0
}

Invoke-CiStage -Name $Stage
