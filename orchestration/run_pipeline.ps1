# ==============================================================================
#  Run the full migration pipeline for one batch  (Windows PowerShell)
#
#    .\orchestration\run_pipeline.ps1                 # BATCH_001
#    .\orchestration\run_pipeline.ps1 -Batch BATCH_002
#
#  If PowerShell blocks the script, run once:
#    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# ==============================================================================
param([string]$Batch = "BATCH_001")

$vars = "{batch_id: $Batch}"
Push-Location (Join-Path $PSScriptRoot "..\dbt")

function Step($text) {
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host " $text" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}

try {
    Step "1/6  Load source extracts into RAW            (SP_LOAD_RAW)"
    dbt run-operation load_raw --vars $vars
    if ($LASTEXITCODE -ne 0) { throw "load_raw failed" }

    Step "2/6  Profile source data + client report     (SP_PROFILE_ALL)"
    dbt run-operation profile_source --vars $vars
    if ($LASTEXITCODE -ne 0) { throw "profile_source failed" }

    Step "3/6  Clear old keyword files"
    dbt run-operation clear_keyword_files --vars $vars
    if ($LASTEXITCODE -ne 0) { throw "clear_keyword_files failed" }

    Step "4/6  dbt build: crosswalks, transformations, validation gate, keyword files"
    dbt build --vars $vars
    $dbtStatus = $LASTEXITCODE
    if ($dbtStatus -ne 0) {
        Write-Host "!! dbt build reported errors - entities that failed validation have NO keyword file." -ForegroundColor Yellow
        Write-Host "!! Continuing so the scorecard shows exactly what did and did not load." -ForegroundColor Yellow
    }

    Step "5/6  Load keyword files into FACETS_TGT       (SP_LOAD_FACETS_TARGET)"
    dbt run-operation load_target --vars $vars
    $loadStatus = $LASTEXITCODE

    Step "6/6  Build reconciliation scorecard           (SP_BUILD_SCORECARD)"
    dbt run-operation build_scorecard --vars $vars
    if ($LASTEXITCODE -ne 0) { throw "build_scorecard failed" }

    Write-Host ""
    Write-Host "Done. In Snowsight run:  SELECT * FROM HC_MIGRATION_DB.AUDIT.V_SCORECARD WHERE BATCH_ID = '$Batch';" -ForegroundColor Green
    if ($dbtStatus -ne 0 -or $loadStatus -ne 0) { exit 1 }
}
catch {
    Write-Host "Pipeline stopped: $_" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
