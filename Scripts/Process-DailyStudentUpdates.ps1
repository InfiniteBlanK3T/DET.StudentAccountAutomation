# Version 1.4
# Purpose: Automate daily updates to student accounts, configurable via an external JSON file.
#          Supports new directory structure for scripts and data.
#          Refactored email notification system.
# Author: Thomas VO (ST02392)
# Date: 16-05-2025 (Original)
# Modified: 26-05-2025 
<#
.SYNOPSIS
    Automates daily updates to student accounts, using a specific directory structure.
.DESCRIPTION
    This script performs daily student account updates.
    Expected Directory Structure:
    /StudentAccountAutomation/
        Scripts/  (This script, StudentDataUtils.psm1, config.json, Logs/)
            Process-DailyStudentUpdates.ps1
            StudentDataUtils.psm1
            config.json
            Logs/
                DailyStudentProcessLog_YYYYMMDD.log
        Data/     (All student data files and subdirectories)
            MasterStudentData.csv (Or as named in config)
            ArchivedCurrentData/
            DailyDownloads/
            StudentsByYearLevel/

    Actions:
    1. Loads configuration from 'Scripts/config.json'.
    2. Initializes logging in 'Scripts/Logs/'.
    3. Defines paths based on the new /Scripts and /Data structure.
    4. Imports utility functions from 'Scripts/StudentDataUtils.psm1'.
    5. If 'Data/MasterStudentData.csv' is not found, an initial run is performed, creating the file from the first download.
    6. Downloads, compares, processes new students, updates master list, archives, and splits data by year level into the 'Data/' subfolders.
    7. Sends email notifications using a refactored system.
.NOTES
    - Assumes this script resides in a 'Scripts' folder.
    - Data files and outputs will be stored in a sibling 'Data' folder.
    - 'config.json' and 'StudentDataUtils.psm1' are expected in the same 'Scripts' folder.
#>

#region Global Settings and Path Definitions
$ScriptVersion = "1.4"
$ScriptStartTime = Get-Date
$ErrorActionPreference = "Stop" 
$VerbosePreference = "Continue"

# --- Base Path Assumptions ---
$ScriptsDir = $PSScriptRoot 
$ProjectRoot = (Get-Item $ScriptsDir).Parent.FullName
$DataDir = Join-Path -Path $ProjectRoot -ChildPath "Data"

# --- Load Configuration (from Scripts folder) ---
$ConfigPath = Join-Path -Path $ScriptsDir -ChildPath "config.json" # config.json is with the script
if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
    Write-Error "Configuration file 'config.json' not found at $ConfigPath. Script cannot continue."
    Exit 1
}
try {
    $Global:Config = Get-Content -Path $ConfigPath | ConvertFrom-Json
    if ($Global:Config.Logging.LogLevel -notin "Verbose", "Debug") {
        $script:OriginalVerbosePreference = $VerbosePreference
        $VerbosePreference = "SilentlyContinue"
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DEBUG: Verbose output from imported modules will be suppressed due to LogLevel setting ('$($Global:Config.Logging.LogLevel)')."
    }
}
catch {
    Write-Error "Error reading or parsing 'config.json': $($_.Exception.Message). Script cannot continue."
    Exit 1
}

# --- Utility Module Path (in Scripts folder) ---
$UtilsModulePath = Join-Path -Path $ScriptsDir -ChildPath "StudentDataUtils.psm1"

# --- Logging Setup (Logs folder inside Scripts folder) ---
$LogDir = Join-Path -Path $ScriptsDir -ChildPath "Logs" 
$LogFileDateSuffix = Get-Date -Format "yyyyMMdd"
$LogFilePath = Join-Path -Path $LogDir -ChildPath "DailyStudentProcessLog_$LogFileDateSuffix.log"

if (-not (Test-Path -Path $LogDir -PathType Container)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# --- Global Processing Summary ---
$Global:ProcessingSummary = [System.Text.StringBuilder]::new()

Function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("Information", "Verbose", "Warning", "Error", "Debug")]
        [string]$Level = "Information",
        [Parameter(Mandatory=$false)]
        [switch]$NoTimestamp
    )
    $timestamp = if ($NoTimestamp) { "" } else { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - " }
    $logEntry = "$timestamp$($Level.ToUpper()): $Message"
    $effectiveLogLevel = $Global:Config.Logging.LogLevel
    if ($Level -eq "Debug" -and $effectiveLogLevel -ne "Debug") { return }
    switch ($effectiveLogLevel) {
        "Verbose" { Write-Host $logEntry }
        "Information" { if ($Level -in "Information","Warning","Error") { Write-Host $logEntry } }
        "Warning" { if ($Level -in "Warning","Error") { Write-Host $logEntry } }
        "Error" { if ($Level -eq "Error") { Write-Error $logEntry } }
        "Debug" { Write-Host $logEntry }
    }
    try { Add-Content -Path $LogFilePath -Value $logEntry }
    catch { Write-Warning "Failed to write to log file $($LogFilePath): $($_.Exception.Message)" }
}

Write-Log -Message "Script execution started. Version $ScriptVersion" -Level Information
$Global:ProcessingSummary.AppendLine("Student Data Processing Report for $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
$Global:ProcessingSummary.AppendLine("School: $($Global:Config.SchoolSettings.SchoolName) (Number: $($Global:Config.SchoolSettings.SchoolNumber))") | Out-Null
$Global:ProcessingSummary.AppendLine("----------------------------------------------------") | Out-Null
Write-Log -Message "Project Root: $ProjectRoot" -Level Verbose
Write-Log -Message "Scripts Directory: $ScriptsDir" -Level Verbose
Write-Log -Message "Data Directory: $DataDir" -Level Verbose
Write-Log -Message "Configuration loaded from: $ConfigPath" -Level Verbose
Write-Log -Message "Log file for this session: $LogFilePath" -Level Information

# --- Data File and Directory Paths (relative to DataDir) ---
$MasterStudentDataFile = Join-Path -Path $DataDir -ChildPath $Global:Config.FileNames.MasterStudentData

$DailyDownloadDir = Join-Path -Path $DataDir -ChildPath "DailyDownloads"
$ArchivedMasterDataDir = Join-Path -Path $DataDir -ChildPath "ArchivedCurrentData"
$StudentsByYearLevelDir = Join-Path -Path $DataDir -ChildPath "StudentsByYearLevel"

$TodayFileNameFormat = Get-Date -Format "ddMMyyyy" 
$ArchivedMasterStudentDataFile = Join-Path -Path $ArchivedMasterDataDir -ChildPath "ArchivedMasterStudentData_$(($Global:Config.FileNames.MasterStudentData) -replace '\.csv', '')_$TodayFileNameFormat.csv"

# Ensure Data directory and its subdirectories exist
Write-Log -Message "Ensuring data directories exist under $DataDir..." -Level Verbose
@( $DataDir, $DailyDownloadDir, $ArchivedMasterDataDir, $StudentsByYearLevelDir ) | ForEach-Object {
    if (-Not (Test-Path -Path $_ -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Log -Message "Created directory: $_" -Level Verbose
        }
        catch {
            Write-Log -Message "Failed to create directory: $_. Error: $($_.Exception.Message)" -Level Error
        }
    }
}

# Import utility functions
try {
    Write-Log -Message "Importing utility module from: $UtilsModulePath" -Level Verbose
    Import-Module -Name $UtilsModulePath -Force 
    Write-Log -Message "Successfully imported module: $UtilsModulePath" -Level Information
}
catch {
    Write-Log -Message "Failed to import module [$UtilsModulePath]. Ensure the file exists and is accessible. $($_.Exception.Message)" -Level Error
    Exit 1 
}
#endregion Global Settings and Path Definitions

#region Helper Functions (Content mostly unchanged from V1.2, ensure they use global paths correctly)

Function Get-StudentDataDownload {
    [CmdletBinding()]
    param()
    Write-Log -Message "Step 1: Fetching updated student list from eduSTAR MC (to $DailyDownloadDir)..." -Level Information
    $Global:ProcessingSummary.AppendLine("1. Fetching updated student list...") | Out-Null
    if (-not (Get-Command Get-StudentAccountFullList -ErrorAction SilentlyContinue)) {
        Write-Log -Message "Utility function 'Get-StudentAccountFullList' not found." -Level Error
        throw "Missing critical utility function: Get-StudentAccountFullList"
    }

    $ActualDownloadedFilePath = Get-StudentAccountFullList -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -OutputPath $DailyDownloadDir -FileNamePrefix "DownloadedStudentList"
    if (-not $ActualDownloadedFilePath -or -not (Test-Path $ActualDownloadedFilePath -PathType Leaf)) {
        Write-Log -Message "Failed to download or locate the updated student list in $DailyDownloadDir" -Level Error
        $Global:ProcessingSummary.AppendLine("   ERROR: Failed to download student list.") | Out-Null
        throw "Student list download failed."
    }
    Write-Log -Message "Updated student list obtained: $ActualDownloadedFilePath" -Level Information
    $Global:ProcessingSummary.AppendLine("   SUCCESS: Student list downloaded to $ActualDownloadedFilePath") | Out-Null
    return $ActualDownloadedFilePath
}

Function Get-StudentDataLists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DownloadedFilePath
    )
    Write-Log -Message "Step 2: Loading student data..." -Level Information
    $Global:ProcessingSummary.AppendLine("2. Loading student data...") | Out-Null
    
    $MasterStudents = @()
    if (-not (Test-Path -Path $MasterStudentDataFile -PathType Leaf)) {
        Write-Log -Message "Master student data file not found: $MasterStudentDataFile. Performing initial run setup. A new master file will be created from downloaded data." -Level Warning
        $Global:ProcessingSummary.AppendLine("   WARNING: Master student data file not found ($MasterStudentDataFile). Assuming initial run.") | Out-Null
        # $MasterStudents remains @(), so all downloaded students will be treated as new.
    } else {
        try {
            # Ensure $MasterStudents is always initialized as an array, even if Import-Csv return $null or a single object
            $MasterStudents = @(Import-Csv -Path $MasterStudentDataFile)
            Write-Log -Message "Loaded $($MasterStudents.Count) students from master data: $MasterStudentDataFile" -Level Verbose
            $Global:ProcessingSummary.AppendLine("   SUCCESS: Loaded $($MasterStudents.Count) students from Master Student Data") | Out-Null
        } catch {
            Write-Log -Message "Error importing master data [$MasterStudentDataFile]: $($_.Exception.Message)." -Level Error
            $Global:ProcessingSummary.AppendLine("   ERROR: Failed to load master data: $($_.Exception.Message)") | Out-Null
            throw "Master student data import failed."
        }
    }

    try {
        $DownloadedStudents = @(Import-Csv -Path $DownloadedFilePath)
        Write-Log -Message "Loaded $($DownloadedStudents.Count) students from downloaded list: $DownloadedFilePath" -Level Verbose
        $Global:ProcessingSummary.AppendLine("   SUCCESS: Loaded $($DownloadedStudents.Count) students - Lastest Data in EduMC") | Out-Null
    } catch {
        Write-Log -Message "Error importing downloaded list [$DownloadedFilePath]: $($_.Exception.Message)." -Level Error
        $Global:ProcessingSummary.AppendLine("   ERROR: Failed to load downloaded list: $($_.Exception.Message)") | Out-Null
        throw "Downloaded student list import failed."
    }

    return @{ MasterStudents = $MasterStudents; DownloadedStudents = $DownloadedStudents }
}

Function Compare-StudentChanges {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$DownloadedStudents,
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$MasterStudents
    )
    Write-Log -Message "Step 3 & 4: Comparing lists and processing new students..." -Level Information
    $Global:ProcessingSummary.AppendLine("3. Comparing student lists...") | Out-Null
    $NewStudentsInput = @()
    $DepartedStudents = @() # Ensure it's okay for this to be empty
    $ExistingStudents = @()

    if ($MasterStudents.Count -eq 0) {
        Write-Log -Message "Master student list is empty (or initial run). All downloaded students treated as new." -Level Information
        $NewStudentsInput = if ($null -ne $DownloadedStudents) { $DownloadedStudents } else { @() }
    } else {
        if (-not (Get-Command Compare-StudentLists -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Utility function 'Compare-StudentLists' not found." -Level Error
            throw "Missing critical utility function: Compare-StudentLists"
        }
        $Comparison = Compare-StudentLists -DownloadedStudents $DownloadedStudents -MasterStudents $MasterStudents
        $NewStudentsInput = $Comparison.NewStudents
        $DepartedStudents = $Comparison.DepartedStudents
        $ExistingStudents = if ($null -eq $Comparison.ExistingStudents) { @() } else { $Comparison.ExistingStudents }
    }

    Write-Log -Message "Found $($NewStudentsInput.Count) new students." -Level Information
    Write-Log -Message "Found $($DepartedStudents.Count) departed students." -Level Information
    Write-Log -Message "$($ExistingStudents.Count) existing students retained." -Level Information
    $Global:ProcessingSummary.AppendLine("   New Students: $($NewStudentsInput.Count)") | Out-Null
    $Global:ProcessingSummary.AppendLine("   Departed Students: $($DepartedStudents.Count)") | Out-Null
    $Global:ProcessingSummary.AppendLine("   Retained Existing Students: $($ExistingStudents.Count)") | Out-Null
    
    # Process existing students with empty passwords
    $Global:ProcessingSummary.AppendLine("4.1 Processing students...") | Out-Null
    $StudentsWithNewlyGeneratedPasswords = [System.Text.StringBuilder]::new()
    $EmptyPasswordCount = 0

    Write-Log -Message "Checking existing students for empty passwords..." -Level Verbose

    foreach ($student in $ExistingStudents) {
        if ([string]::IsNullOrWhiteSpace($student.Password)) {
            
            # Generate a new password
            $newPassword = Get-RandomPasswordSimple
            # Add/update Password property to the student object
            $student.Password = $newPassword
            $EmptyPasswordCount++
            
            $StudentsWithNewlyGeneratedPasswords.AppendLine("   - $($student.FirstName) $($student.LastName) ($($student.Username)), Year: $($student.YearLevel), Class: $($student.Class) - Password Generated.") | Out-Null
            
            # If not in MockMode, actually set the password in eduPass
            if ($Global:Config.ScriptBehavior.MockMode -ne $true) {
                if (Get-Command Set-eduPassStudentAccountPassword -ErrorAction SilentlyContinue) {
                    try {
                        Set-eduPassStudentAccountPassword -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -Password $newPassword | Out-Null
                        Write-Log -Message "  SUCCESS: eduPass password set for $($student.Username)." -Level Information
                    } catch {
                        Write-Log -Message "  ERROR setting eduPass password for $($($student.Username)): $($_.Exception.Message)" -Level Error
                    }
                } else {
                    Write-Log -Message "  WARNING: Function Set-eduPassStudentAccountPassword not found. Password not set in eduPass." -Level Warning
                }
            } else {
                Write-Log -Message "  MOCK MODE: Simulating Set-eduPassStudentAccountPassword for $($student.Username)" -Level Information
            }
        }
    }

    if ($EmptyPasswordCount -gt 0) {
        Write-Log -Message "Generated passwords for $EmptyPasswordCount existing students with empty passwords." -Level Information
        $ProcessingSummary.AppendLine("   SUCCESS: Generated passwords for $EmptyPasswordCount existing students with empty passwords.") | Out-Null
        if ($StudentsWithNewlyGeneratedPasswords.Length -gt 0) {
            $ProcessingSummary.AppendLine("   Students with newly generated passwords:") | Out-Null
            $ProcessingSummary.Append($StudentsWithNewlyGeneratedPasswords.ToString()) | Out-Null
        }
    } else {
        Write-Log -Message "No existing students with empty passwords found." -Level Verbose
        $ProcessingSummary.AppendLine("   No existing students with empty passwords found.") | Out-Null
    }

    # Process new students
    $Global:ProcessingSummary.AppendLine("4.2 Processing new students...") | Out-Null
    $ProcessedNewStudents = @()
    $NewStudentDetailsForEmail = [System.Text.StringBuilder]::new()

    if ($NewStudentsInput.Count -gt 0) {
        if (-not (Get-Command Get-RandomPasswordSimple -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Utility function 'Get-RandomPasswordSimple' not found." -Level Error
            throw "Missing critical utility function: Get-RandomPasswordSimple"
        }
        foreach ($student in $NewStudentsInput) {         
            Write-Log -Message "Processing new student: $($student.Username) - Year: $($student.YearLevel) - Class: $($student.Class)" -Level Debug
            $newPassword = Get-RandomPasswordSimple
            $studentWithPassword = $student | Select-Object *, @{Name='Password';Expression={$newPassword}}
            # $NewStudentDetailsForEmail.AppendLine("   - $($student.FirstName) $($student.LastName) ($($student.Username)), Year: $($student.YearLevel), Class: $($student.Class) - Account created.") | Out-Null

            if ($Global:Config.ScriptBehavior.MockMode) {
                Write-Log -Message "  MOCK MODE: Simulating Set-eduPassStudentAccountPassword for $($student.Username)" -Level Information
                Write-Log -Message "  MOCK MODE: Simulating Set-eduPassCloudServiceStatus (Google) for $($student.Username)" -Level Information
                # Write-Log -Message "  MOCK MODE: Simulating Set-eduPassCloudServiceStatus (Intune) for $($student.Username)" -Level Information
            } else {
                if ((Get-Command Set-eduPassStudentAccountPassword -ErrorAction SilentlyContinue) -and (Get-Command Set-eduPassCloudServiceStatus -ErrorAction SilentlyContinue)) {
                    try { Set-eduPassStudentAccountPassword -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -Password $newPassword; Write-Log -Message "  SUCCESS: eduPass password set for $($student.Username)." -Level Information } catch { Write-Log -Message "  ERROR setting eduPass password for $($($student.Username)): $($_.Exception.Message)" -Level Error }
                    try { Set-eduPassCloudServiceStatus -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -AccountType student -Service google -Status Enabled; Write-Log -Message "  SUCCESS: Google Cloud Service enabled for $($student.Username)." -Level Information } catch { Write-Log -Message "  ERROR enabling Google Cloud Service for $($($student.Username)): $($_.Exception.Message)" -Level Error }
                    try { Set-eduPassCloudServiceStatus -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -AccountType student -Service intune -Status Enabled; Write-Log -Message "  SUCCESS: Intune Cloud Service enabled for $($student.Username)." -Level Information } catch { Write-Log -Message "  ERROR enabling Intune Cloud Service for $($($student.Username)): $($_.Exception.Message)" -Level Error }
                } else {
                    Write-Log -Message "  WARNING: eduPass/Cloud service functions not found. Skipping live account modifications." -Level Warning
                    $Global:ProcessingSummary.AppendLine("     WARNING: Live account modification functions not found.") | Out-Null
                }
            }
            $ProcessedNewStudents += $studentWithPassword
            Write-Log -Message "Added new student $($student.Username) with generated password to processing list." -Level Verbose
        }
        $Global:ProcessingSummary.AppendLine("   SUCCESS: Processed $($ProcessedNewStudents.Count) new students.") | Out-Null
        if ($NewStudentDetailsForEmail.Length -gt 0) {
             $Global:ProcessingSummary.AppendLine("   New Student Details:") | Out-Null
             $Global:ProcessingSummary.Append($NewStudentDetailsForEmail.ToString()) | Out-Null
        }

    } else {
        Write-Log -Message "No new students to process." -Level Information
        $Global:ProcessingSummary.AppendLine("   No new students to process.") | Out-Null
    }

    return @{ 
        ExistingStudents = if ($null -eq $ExistingStudents) { @() } else { $ExistingStudents } 
        ProcessedNewStudents = if ($null -eq $ProcessedNewStudents) { @() } else { $ProcessedNewStudents }
        DepartedStudentsCount = if ($null -eq $DepartedStudents) { 0 } else { $DepartedStudents.Count }
    }
}

Function Update-MasterStudentData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$ExistingStudents,
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [array]$ProcessedNewStudents 
    )

    #Safe Guard Nullable Values:
    $ExistingStudents = if ($null -eq $ExistingStudents) { @() } else { $ExistingStudents }
    $ProcessedNewStudents = if ($null -eq $ProcessedNewStudents) { @() } else { $ProcessedNewStudents }

    Write-Log -Message "Step 5 & 6: Updating, saving, and archiving master student list..." -Level Information
    $Global:ProcessingSummary.AppendLine("5. Updating master student list...") | Out-Null
    
    # Write-Host "DEBUG (Inside Update-MasterStudentData): Count of `$ProcessedNewStudents param: $($ProcessedNewStudents.Count)"

    $UpdatedMasterStudentList = $ExistingStudents + $ProcessedNewStudents
    $SortedUpdatedMasterStudentList = $UpdatedMasterStudentList | Sort-Object -Property Username
    
    Write-Log -Message "Master list updated. Total students: $($SortedUpdatedMasterStudentList.Count)" -Level Information
    $Global:ProcessingSummary.AppendLine("   SUCCESS: Master list updated. Total students: $($SortedUpdatedMasterStudentList.Count)") | Out-Null
    $Global:ProcessingSummary.AppendLine("6. Saving and archiving master list /ArchivedCurrentData...") | Out-Null
    
    $RequiredHeaders = @("Username","FirstName","LastName","YearLevel","Class","Email","Password") 
    $StandardizedMasterList = foreach ($student in $SortedUpdatedMasterStudentList) {
        $props = [ordered]@{} 
        foreach($header in $RequiredHeaders){
            if ($student.PSObject.Properties.Name -contains $header) { $props[$header] = $student.$header } 
            else { $props[$header] = "" }
        }
        [PSCustomObject]$props
    }
    $CsvDataToExport = $StandardizedMasterList | Select-Object $RequiredHeaders
    $csvOutputLines = $CsvDataToExport | ConvertTo-Csv -NoTypeInformation
    if ($Global:Config.ScriptBehavior.RemoveQuotesFromCsv) {
        $csvOutputLines = $csvOutputLines | ForEach-Object { $_ -replace '"','' }
    }

    # $ArchivedMasterStudentDataFile path is now correctly pointing to Data/ArchivedCurrentData/...
    try {
        $csvOutputLines | Set-Content -Path $ArchivedMasterStudentDataFile -Encoding UTF8 -Force
        Write-Log -Message "Archived master data saved to: $ArchivedMasterStudentDataFile" -Level Information
        $Global:ProcessingSummary.AppendLine("   SUCCESS: Archived master data. Date $($TodayFileNameFormat)") | Out-Null
    } catch {
        Write-Log -Message "Error saving archived master data to [$ArchivedMasterStudentDataFile]: $($_.Exception.Message)" -Level Error
        $Global:ProcessingSummary.AppendLine("   ERROR: Failed to archive master data: $($_.Exception.Message)") | Out-Null
    }

    # $MasterStudentDataFile path is now correctly pointing to Data/MasterStudentData.csv (or as configured)
    try {
        $csvOutputLines | Set-Content -Path $MasterStudentDataFile -Encoding UTF8 -Force 
        Write-Log -Message "Master student data file [$MasterStudentDataFile] has been updated for the next run." -Level Information
        $Global:ProcessingSummary.AppendLine("   SUCCESS: Updated main master data file $MasterStudentDataFile") | Out-Null
    } catch {
        Write-Log -Message "Error updating master data file [$MasterStudentDataFile]: $($_.Exception.Message)" -Level Error
        $Global:ProcessingSummary.AppendLine("   ERROR: Failed to update main master data file: $($_.Exception.Message)") | Out-Null
        throw "Failed to update critical master student data file: $MasterStudentDataFile."
    }
    return $SortedUpdatedMasterStudentList
}

Function Split-DataByYearLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$MasterListToSplit
    )
    Write-Log -Message "Step 7: Splitting updated master list by year level (to $StudentsByYearLevelDir)..." -Level Information
    $Global:ProcessingSummary.AppendLine("7. Splitting master list by year level...") | Out-Null
    if ($MasterListToSplit.Count -eq 0) {
        Write-Log -Message "No students in updated master list to split." -Level Warning
        $Global:ProcessingSummary.AppendLine("   No students to split by year level.") | Out-Null
        return
    }
    $RequiredHeaders = @("Username","FirstName","LastName","YearLevel","Class","Email","Password") 
    $GroupedByYear = $MasterListToSplit | Group-Object -Property YearLevel
    
    foreach ($group in $GroupedByYear) {
        $year = $group.Name
        if (-not [string]::IsNullOrWhiteSpace($year)) {
            $StudentsInYear = $group.Group
            $YearLevelFileName = "Year_$($year -replace '[^a-zA-Z0-9_-]', '_').xlsx"
            # $StudentsByYearLevelDir path is now correctly pointing to Data/StudentsByYearLevel/
            $YearLevelFilePath = Join-Path -Path $StudentsByYearLevelDir -ChildPath $YearLevelFileName
            $yearCsvDataToExport = $StudentsInYear | Select-Object $RequiredHeaders
            $yearCsvOutputLines = $yearCsvDataToExport | ConvertTo-Csv -NoTypeInformation
            if ($Global:Config.ScriptBehavior.RemoveQuotesFromCsv) {
                $yearCsvOutputLines = $yearCsvOutputLines | ForEach-Object { $_ -replace '"','' }
            }
            try {
                $yearCsvOutputLines | Set-Content -Path $YearLevelFilePath -Encoding UTF8 -Force
                Write-Log -Message "  Saved $($StudentsInYear.Count) students for Year [$year] to: $YearLevelFilePath" -Level Information
                $Global:ProcessingSummary.AppendLine("   - Year $($year): $($StudentsInYear.Count) students saved to /StudentsByYearLevel") | Out-Null
            } catch {
                Write-Log -Message "  ERROR saving year file for [$year] to [$YearLevelFilePath]: $($_.Exception.Message)" -Level Error
                $Global:ProcessingSummary.AppendLine("   - Year $($year): ERROR saving file - $($_.Exception.Message)") | Out-Null
            }
        } else {
            $studentsWithNoYear = $group.Group.Count
            Write-Log -Message "Skipping $studentsWithNoYear students with blank/null YearLevel." -Level Warning
            $Global:ProcessingSummary.AppendLine("   WARNING: Skipped $studentsWithNoYear students with blank/null YearLevel.") | Out-Null
        }
    }
}

#endregion Helper Functions

#region Main Processing Logic
$ScriptSuccess = $true 
try {
    $ActualDownloadedFilePath = Get-StudentDataDownload
    $StudentData = Get-StudentDataLists -DownloadedFilePath $ActualDownloadedFilePath
    $ProcessingResult = Compare-StudentChanges -DownloadedStudents $StudentData.DownloadedStudents -MasterStudents $StudentData.MasterStudents
    $FinalMasterList = Update-MasterStudentData -ExistingStudents ($ProcessingResult.ExistingStudents ?? @()) -ProcessedNewStudents ($ProcessingResult.ProcessedNewStudents ?? @())
    Split-DataByYearLevel -MasterListToSplit $FinalMasterList
    
    Write-Log -Message "Daily student processing completed successfully." -Level Information
    $Global:ProcessingSummary.AppendLine("----------------------------------------------------") | Out-Null
    $Global:ProcessingSummary.AppendLine("Overall Status: SUCCESS") | Out-Null
}
catch {
    $ScriptSuccess = $false
    $ErrorMessage = "AN ERROR OCCURRED: $($_.Exception.Message)"
    $ErrorDetails = "Stack Trace: $($_.ScriptStackTrace) - Position: $($_.InvocationInfo.PositionMessage)" # Ensure this captures useful info
    Write-Log -Message $ErrorMessage -Level Error
    Write-Log -Message $ErrorDetails -Level Error # Log details to file
    
    $Global:ProcessingSummary.AppendLine("----------------------------------------------------") | Out-Null
    $Global:ProcessingSummary.AppendLine("Overall Status: FAILED") | Out-Null
    $Global:ProcessingSummary.AppendLine("ERROR: $ErrorMessage") | Out-Null
    # $Global:ProcessingSummary.AppendLine("DETAILS: $ErrorDetails") | Out-Null # Optionally add full details to summary email

    # Send Admin Error Notification
    Send-NotificationEmail -NotificationType "AdminError" -IsScriptSuccessful $false -CustomMessage $ErrorMessage -CustomDetails $ErrorDetails
}
finally {
    if ($null -ne $script:OriginalVerbosePreference) {
        $VerbosePreference = $script:OriginalVerbosePreference
        Write-Log -Message "Restored original VerbosePreference value ('$($VerbosePreference)')." -Level Debug
    }

    #Perform File Cleanup
    Invoke-FileCleanUp

    # Send Process Summary Notification (success or failure, respecting SendOnSuccessOnly)
    Send-NotificationEmail -NotificationType "ProcessSummary" -IsScriptSuccessful $ScriptSuccess
    
    Write-Log -Message "Performing cleanup..." -Level Verbose
    if (Get-Command Disconnect-eduSTARMC -ErrorAction SilentlyContinue) {
        try { 
            if ($Global:Config.ScriptBehavior.MockMode) {
                Write-Log -Message "MOCK MODE: Simulating Disconnect-eduSTARMC." -Level Verbose
            } else {
                Disconnect-eduSTARMC 
                Write-Log -Message "Disconnected from eduSTAR MC." -Level Verbose 
            }
        }
        catch { Write-Log -Message "Error during Disconnect-eduSTARMC: $($_.Exception.Message)" -Level Warning }
    }
    $ScriptEndTime = Get-Date
    $ScriptDuration = New-TimeSpan -Start $ScriptStartTime -End $ScriptEndTime
    Write-Log -Message "Script execution finished. Total duration: $($ScriptDuration.TotalSeconds) seconds." -Level Information
    $Global:ProcessingSummary.AppendLine("Script Duration: $($ScriptDuration.TotalSeconds) seconds.") | Out-Null
    
    # Log the full summary if email wasn't sent or enabled
    $emailConfig = $Global:Config.EmailNotification
    if (-not $emailConfig.Enabled -or ($emailConfig.Enabled -and (-not $ScriptSuccess -and $emailConfig.SendOnSuccessOnly))) {
         Write-Log -Message "Final Processing Summary (also for log):`n$($Global:ProcessingSummary.ToString())" -Level Information -NoTimestamp
    }
}  
#endregion Main Processing Logic