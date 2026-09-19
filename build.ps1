$ErrorActionPreference = "Stop"
$DO_CLEAN    = $false
$DO_RUN      = $false
$DO_DEV      = $false
$DO_INSTALL  = $false
$BUILD_TYPE  = "Release"

foreach ($a in $args) {
    switch -Exact ($a) {
        "--clean"   { $DO_CLEAN  = $true }
        "--run"     { $DO_RUN    = $true }
        "--dev"     { $DO_DEV    = $true }
        "--install" { $DO_INSTALL= $true }
        "--debug"   { $BUILD_TYPE = "Debug" }
        "--release" { $BUILD_TYPE = "Release" }
        default {
            Write-Host "Unknown argument: $a"
            Write-Host "Usage: $($MyInvocation.MyCommand.Name) [--clean] [--run | --dev] [--install] [--debug|--release]"
            exit 1
        }
    }
}

if ($DO_DEV) { $BUILD_TYPE = "Debug" }

$SCRIPT_DIR = $PSScriptRoot
$BUILD_DIR  = Join-Path $SCRIPT_DIR "build"
$UI_DIR     = Join-Path $SCRIPT_DIR "ui"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "cmake not found on PATH."
    exit 1
}

function Find-Qt {
    if ($env:QT_DIR -and (Test-Path "$env:QT_DIR\lib\cmake\Qt6\Qt6Config.cmake")) {
        return $env:QT_DIR
    }

    if (Get-Command qmake6 -ErrorAction SilentlyContinue) {
        $p = & qmake6 -query QT_INSTALL_PREFIX 2>$null
        if ($LASTEXITCODE -eq 0 -and $p -and (Test-Path "$p\lib\cmake\Qt6\Qt6Config.cmake")) {
            return $p
        }
    }
    if (Get-Command qmake -ErrorAction SilentlyContinue) {
        $p = & qmake -query QT_INSTALL_PREFIX 2>$null
        if ($LASTEXITCODE -eq 0 -and $p -and (Test-Path "$p\lib\cmake\Qt6\Qt6Config.cmake")) {
            return $p
        }
    }

    $roots = @("C:\Qt", (Join-Path $env:USERPROFILE "Qt"), (Join-Path $env:LOCALAPPDATA "Qt"))
    $best  = $null
    $bestVersion = $null

    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[56]\.' } | ForEach-Object {
            Get-ChildItem $_.FullName -Directory -Filter "msvc*_64" -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-Path (Join-Path $_.FullName "lib\cmake\Qt6\Qt6Config.cmake")) {
                    $v = $null
                    if ([version]::TryParse($_.Parent.Name, [ref]$v)) {
                        if (-not $bestVersion -or $v -gt $bestVersion) {
                            $bestVersion = $v
                            $best = $_.FullName
                        }
                    }
                }
            }
        }
    }
    return $best
}

$QT_PREFIX = Find-Qt
if (-not $QT_PREFIX) {
    Write-Host "Could not locate a Qt 6 installation."
    Write-Host "Install one, for example:"
    Write-Host "  aqt install-qt windows desktop 6.8.3 win64_msvc2022_64 -O C:\Qt -m qtwebengine qtwebchannel qtlocation qtpositioning"
    exit 1
}
Write-Host "Using Qt at: $QT_PREFIX"

# ── clean ───────────────────────────────────────────────────────────────
if ($DO_CLEAN -and (Test-Path $BUILD_DIR)) {
    Write-Host "Removing build directory..."
    Remove-Item -Recurse -Force $BUILD_DIR
}

# ── configure ───────────────────────────────────────────────────────────
if (-not (Test-Path "$BUILD_DIR\CMakeCache.txt")) {
    Write-Host "Configuring..."
    & cmake -S $SCRIPT_DIR -B $BUILD_DIR -G "Visual Studio 17 2022" -A x64 `
        -DCMAKE_PREFIX_PATH="$QT_PREFIX"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# ── build ───────────────────────────────────────────────────────────────
Write-Host "Building ($BUILD_TYPE)..."
& cmake --build $BUILD_DIR --config $BUILD_TYPE --parallel $env:NUMBER_OF_PROCESSORS
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$APP_DIR    = Join-Path $BUILD_DIR $BUILD_TYPE
$APP_BINARY = Join-Path $APP_DIR "QT_Illuminate.exe"
if (-not (Test-Path $APP_BINARY)) {
    Write-Host "Build finished but binary not found: $APP_BINARY"
    exit 1
}

# ── deploy Qt runtime (windeployqt) ─────────────────────────────────────
$DEPLOY_QT = Join-Path $QT_PREFIX "bin\windeployqt.exe"
if (Test-Path $DEPLOY_QT) {
    $deployMode = If ($BUILD_TYPE -eq "Debug") { "--debug" } Else { "--release" }
    Write-Host "Deploying Qt runtime into $APP_DIR ..."
    & $DEPLOY_QT $APP_BINARY --qmldir $UI_DIR $deployMode --no-translations --compiler-runtime
    if ($LASTEXITCODE -ne 0) { Write-Host "windeployqt reported errors; app may be incomplete."; exit 1 }
} else {
    Write-Host "windeployqt not found ($DEPLOY_QT) - skipping deploy (app may not run)."
}

Write-Host "Build succeeded: $APP_BINARY"

# ── install (copy to AppData + Start Menu shortcut) ────────────────────
if ($DO_INSTALL) {
    $DEST_ROOT = Join-Path $env:LOCALAPPDATA "Programs\Illuminate"
    Write-Host "Installing to $DEST_ROOT ..."
    New-Item -ItemType Directory -Force -Path $DEST_ROOT | Out-Null
    Copy-Item "$APP_DIR\*" $DEST_ROOT -Recurse -Force

    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    if (-not (Test-Path $startMenuDir)) { $startMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs" }
    $lnkPath = Join-Path $startMenuDir "Illuminate.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath       = Join-Path $DEST_ROOT "QT_Illuminate.exe"
    $lnk.WorkingDirectory = $DEST_ROOT
    $lnk.IconLocation     = "$lnk.TargetPath,0"
    $lnk.Description      = "Illuminate web browser"
    $lnk.Save()
    Write-Host "Installed. Shortcut created: $lnkPath"
}

$LOG_FILE = Join-Path $env:LOCALAPPDATA "QT_Illuminate\QT_Illuminate\logs\browser.log"

# ── run (detached) ──────────────────────────────────────────────────────
if ($DO_RUN) {
    if ($DO_DEV) {
        Write-Host "Launching (dev, live logs)..."
        $logDir = Split-Path $LOG_FILE
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $outLog = Join-Path $logDir "dev.out.log"
        $errLog = Join-Path $logDir "dev.err.log"
        Remove-Item $outLog, $errLog -ErrorAction SilentlyContinue

        $proc = Start-Process -FilePath $APP_BINARY -WorkingDirectory $APP_DIR -NoNewWindow `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
        Write-Host "  PID: $($proc.Id)"
        Write-Host "  Log file: $LOG_FILE"

        $outCursor = 0
        $errCursor = 0
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 400
            if (Test-Path $outLog) {
                $lines = @(Get-Content $outLog -ErrorAction SilentlyContinue)
                if ($lines.Count -gt $outCursor) {
                    $lines[$outCursor..($lines.Count - 1)]
                    $outCursor = $lines.Count
                }
            }
            if (Test-Path $errLog) {
                $lines = @(Get-Content $errLog -ErrorAction SilentlyContinue)
                if ($lines.Count -gt $errCursor) {
                    $lines[$errCursor..($lines.Count - 1)]
                    $errCursor = $lines.Count
                }
            }
        }
        Write-Host "app exited."
    }
    else {
        Write-Host "Launching (detached)..."
        $proc = Start-Process -FilePath $APP_BINARY -WorkingDirectory $APP_DIR -PassThru
        Write-Host "  PID: $($proc.Id)"
        Write-Host "  Log file: $LOG_FILE"
    }
}