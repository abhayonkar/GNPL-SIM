# create_baseline.ps1 — Idempotent Phase 0 baseline capture
# Usage: pwsh -File scripts/create_baseline.ps1
# Must be run from the repository root BEFORE any Phase 0 code changes.

param(
    [string]$Tag        = "baseline-v0-phase-c",
    [string]$ArchiveDir = "archive",
    [string]$SourceDir  = "ml_outputs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host " Phase 0 Baseline Capture"
Write-Host "=========================================="

# ── 1. Git tag ──────────────────────────────────────────────────────────────
$existingTag = git tag --list $Tag
if ($existingTag) {
    $tagSha = git rev-parse $Tag
    Write-Host "[tag] '$Tag' already exists → $tagSha (skipping re-creation)"
} else {
    git tag -a $Tag -m "Phase 0 baseline before modifications"
    $tagSha = git rev-parse $Tag
    Write-Host "[tag] Created '$Tag' → $tagSha"
}

# ── 2. Archive ml_outputs ───────────────────────────────────────────────────
if (-not (Test-Path $ArchiveDir)) {
    New-Item -ItemType Directory -Path $ArchiveDir | Out-Null
    Write-Host "[archive] Created directory: $ArchiveDir"
}

$ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
$dst = Join-Path $ArchiveDir "ml_outputs_baseline_$ts.zip"

if (-not (Test-Path $SourceDir)) {
    Write-Warning "[archive] '$SourceDir' not found — skipping archive step"
} else {
    Compress-Archive -Path "$SourceDir\*" -DestinationPath $dst -Force
    # Set read-only
    attrib +R $dst
    # SHA-256 checksum
    $hash = (Get-FileHash $dst -Algorithm SHA256).Hash
    Set-Content -Path "$dst.sha256" -Value "$hash  $dst"
    Write-Host "[archive] Created: $dst"
    Write-Host "[archive] SHA-256: $hash"
}

# ── 3. Verification ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── Verification ──────────────────────────────"
$resolvedTag = git rev-parse $Tag 2>$null
Write-Host "[ok] Tag '$Tag' → $resolvedTag"
$archives = Get-ChildItem "$ArchiveDir\ml_outputs_baseline_*.zip" -ErrorAction SilentlyContinue
Write-Host "[ok] Archive count: $($archives.Count)"
Write-Host "=========================================="
Write-Host " Baseline capture complete."
Write-Host "=========================================="
