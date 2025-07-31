# MiscHelper.psm1 - Main Helper Module
# Purpose: Consolidated helper module that imports all specialized helper modules
# Author: Thomas VO (ST02392)
# Date: 30-07-2025
# Version: 1.7.1 - Modularized into specialized helper files

# Get the directory where this module resides
$ModuleDirectory = $PSScriptRoot

# Import all specialized helper modules
try {
    # Import Student Data Helper
    $StudentDataHelperPath = Join-Path -Path $ModuleDirectory -ChildPath "StudentDataHelper.psm1"
    if (Test-Path $StudentDataHelperPath) {
        Import-Module -Name $StudentDataHelperPath -Force
        Write-Verbose "[Utils] StudentDataHelper.psm1 imported successfully"
    } else {
        Write-Warning "[Utils] StudentDataHelper.psm1 not found at: $StudentDataHelperPath"
    }

    # Import Email Notification Helper
    $EmailHelperPath = Join-Path -Path $ModuleDirectory -ChildPath "EmailNotificationHelper.psm1"
    if (Test-Path $EmailHelperPath) {
        Import-Module -Name $EmailHelperPath -Force
        Write-Verbose "[Utils] EmailNotificationHelper.psm1 imported successfully"
    } else {
        Write-Warning "[Utils] EmailNotificationHelper.psm1 not found at: $EmailHelperPath"
    }

    # Import PDF Generation Helper
    $PDFHelperPath = Join-Path -Path $ModuleDirectory -ChildPath "PDFGenerationHelper.psm1"
    if (Test-Path $PDFHelperPath) {
        Import-Module -Name $PDFHelperPath -Force
        Write-Verbose "[Utils] PDFGenerationHelper.psm1 imported successfully"
    } else {
        Write-Warning "[Utils] PDFGenerationHelper.psm1 not found at: $PDFHelperPath"
    }

    # Import Utility Helper
    $UtilityHelperPath = Join-Path -Path $ModuleDirectory -ChildPath "UtilityHelper.psm1"
    if (Test-Path $UtilityHelperPath) {
        Import-Module -Name $UtilityHelperPath -Force
        Write-Verbose "[Utils] UtilityHelper.psm1 imported successfully"
    } else {
        Write-Warning "[Utils] UtilityHelper.psm1 not found at: $UtilityHelperPath"
    }

} catch {
    Write-Error "[Utils] Failed to import one or more helper modules: $($_.Exception.Message)"
    throw "Critical error loading helper modules. Cannot continue."
}

# Re-export all functions from the imported modules to maintain compatibility
# This ensures existing scripts continue to work without modification
Export-ModuleMember -Function `
    Compare-StudentLists, `
    Test-DuplicationEntry, `
    Send-NotificationEmail, `
    Get-AdminErrorEmailBody, `
    Get-ProcessSummaryEmailBody, `
    Generate-StudentListPDF, `
    Generate-StudentListHTML, `
    Convert-HTMLToPDF, `
    Test-EdgeWebView2Available, `
    Test-ChromeAvailable, `
    Test-WkHtmlToPdfAvailable, `
    Convert-HTMLToPDF-EdgeWebView2, `
    Convert-HTMLToPDF-Chrome, `
    Convert-HTMLToPDF-WkHtmlToPdf, `
    Convert-HTMLToText, `
    Get-RandomPasswordSimple, `
    Invoke-FileCleanUp, `
    Get-UserFriendlySummary

Write-Log "[Utils] MiscHelper.psm1 $($Global:Config.ScriptBehavior.ScriptVersion) loaded with modular architecture."
