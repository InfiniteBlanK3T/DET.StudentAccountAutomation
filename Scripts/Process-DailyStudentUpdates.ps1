# Version 1.6
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
        Archived-Logs/     (All student data files and subdirectories)
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
$ScriptVersion = "1.6"
$ScriptStartTime = Get-Date
$ErrorActionPreference = "Stop" 
$VerbosePreference = "Continue"

# --- Base Path Assumptions ---
$ScriptsDir = $PSScriptRoot 
$ProjectRoot = (Get-Item $ScriptsDir).Parent.FullName
$DataDir = Join-Path -Path $ProjectRoot -ChildPath "Archived-Logs"

# --- Load Configuration (from Scripts folder) ---
$ConfigPath = Join-Path -Path $ScriptsDir -ChildPath "config.json" # config.json is with the script
if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
    Write-Error "Configuration file 'config.json' not found at $ConfigPath. Script cannot continue."
    Exit 1
}

$MiscHelperPath = Join-Path -Path $ScriptsDir -ChildPath "MiscHelper.psm1"
if (-not (Test-Path -Path $MiscHelperPath -PathType Leaf)) {
    Write-Error "Utility module 'MiscHelper.psm1' not found at $MiscHelperPath. Script cannot continue."
    Exit 1
}
$EduSTARHelperPath = Join-Path -Path $ScriptsDir -ChildPath "EduSTARHelper.psm1"
if (-not (Test-Path -Path $EduSTARHelperPath -PathType Leaf)) {
    Write-Error "Utility module 'EduSTARHelper.psm1' not found at $EduSTARHelperPath. Script cannot continue."
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

# --- Logging Setup (Logs folder inside Scripts folder) ---
$LogDir = Join-Path -Path $ScriptsDir -ChildPath "Logs" 
$LogFileDateSuffix = Get-Date -Format "yyyyMMdd"
$LogFilePath = Join-Path -Path $LogDir -ChildPath "DailyStudentProcessLog_$LogFileDateSuffix.log"

if (-not (Test-Path -Path $LogDir -PathType Container)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# --- Global Processing Summary ---
$Global:ProcessingSummary = [System.Text.StringBuilder]::new()

Function Global:Write-Log {
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

# Import utility functions
try {
    Write-Host "Importing utility module from: $MiscHelperPath"
    Import-Module -Name $MiscHelperPath -Force 

    Write-Host "Importing eduSTAR helper module from: $EduSTARHelperPath"
    Import-Module -Name $EduSTARHelperPath -Force
}
catch {
    Write-Error "Failed to import module. Ensure the file exists and is accessible. $($_.Exception.Message)"
    Exit 1 
}

try {
    Write-Log -Message "Importing ImportExcel module..." -Level Verbose
    Import-Module ImportExcel -ErrorAction Stop
    Write-Log -Message "Successfully imported ImportExcel module." -Level Information
} catch {
    Write-Log -Message "Failed to import the 'ImportExcel' module. This module is required for creating .xlsx files. Please install it by running 'Install-Module ImportExcel -Scope CurrentUser' in PowerShell. Error: $($_.Exception.Message)" -Level Error
    $Global:ProcessingSummary.AppendLine("   CRITICAL ERROR: ImportExcel module not found. Year level Excel files cannot be generated.") | Out-Null
}

# --- Data File and Directory Paths (relative to DataDir) ---
$MasterStudentDataFile = Join-Path -Path $DataDir -ChildPath $Global:Config.FileNames.MasterStudentData

$DailyDownloadDir = Join-Path -Path $DataDir -ChildPath "DailyDownloads"
$ArchivedMasterDataDir = Join-Path -Path $DataDir -ChildPath "ArchivedCurrentData"
$StudentsByYearLevelDir = Join-Path -Path $ProjectRoot -ChildPath "StudentsByYearLevel"

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

    $DownloadedStudentHas = @{}
    foreach ($ds in $DownloadedStudents) {
        if (-not [string]::IsNullOrWhiteSpace($ds.Username)) {
            $DownloadedStudentHas[$ds.Username] = $ds
        }
    }

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
    $Global:ProcessingSummary.AppendLine("4.1 Processing students changes (YearLevel, Class, Password)..") | Out-Null
    $UpdatedExistingStudents = @()
    $StudentsWithNewlyGeneratedPasswords = [System.Text.StringBuilder]::new()
    $StudentsWithDetailChanges = [System.Text.StringBuilder]::new()
    $EmptyPasswordCount = 0

    Write-Log -Message "Checking existing students for empty passwords..." -Level Verbose

    if($ExistingStudents.Count -gt 0) {
        Write-Log -Message "Processing $($ExistingStudents.Count) existing students..." -Level Information

        if (-not (Get-Command Get-RandomPasswordSimple -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Utility function 'Get-RandomPasswordSimple' not found." -Level Error
            throw "Missing critical utility function: Get-RandomPasswordSimple"
        }

        foreach ($masterStudent in $ExistingStudents) {
            $usernameForLog = if ($masterStudent.Username) { $masterStudent.Username } else { "Unknown" }
            $downloadedStudentData =  $DownloadedStudentHas[$masterStudent.Username]

            if ($null -eq $downloadedStudentData) {
                Write-Log -Message "WARNING: Existing student '$usernameForLog' not found in downloaded data. Skipping." -Level Warning
                $UpdatedExistingStudents += $masterStudent # Add to list as is, anomoly
                continue
            }

            # Check and update YearLevel
            if ($masterStudent.YearLevel -ne $downloadedStudentData.YearLevel) {
                # Debug
                $oldYearLevel = $masterStudent.YearLevel
                Write-Log -Message "Updating YearLevel for existing student '$usernameForLog' from '$oldYearLevel' to '$($downloadedStudentData.YearLevel)'" -Level Information
                $masterStudent.YearLevel = $downloadedStudentData.YearLevel
                $StudentsWithDetailChanges.AppendLine("   - $($masterStudent.FirstName) $($masterStudent.LastName) ($($masterStudent.Username)) - YearLevel: $oldYearLevel -> $($downloadedStudentData.YearLevel)") | Out-Null
            }

            # Check and update Class
            if ($masterStudent.Class -ne $downloadedStudentData.Class) {
                #Debug
                $oldClass = $masterStudent.Class
                Write-Log -Message "Updating Class for existing student '$usernameForLog' from '$oldClass' to '$($downloadedStudentData.Class)'" -Level Information
                $masterStudent.Class = $downloadedStudentData.Class
                $StudentsWithDetailChanges.AppendLine("   - $($masterStudent.FirstName) $($masterStudent.LastName) ($($masterStudent.Username)) - Class: $oldClass -> $($downloadedStudentData.Class)") | Out-Null
            }
            
            #Check and update Email
            $expectedEmail = "$($downloadedStudentData.Username)@schools.vic.edu.au"
            if ($masterStudent.Email -ne $expectedEmail) {
                #Debug
                $oldEmail = $masterStudent.Email
                Write-Log -Message "Updating Email for existing student '$usernameForLog' from '$oldEmail' to '$expectedEmail'" -Level Information
                $masterStudent.Email = $expectedEmail
                $StudentsWithDetailChanges.AppendLine("   - $($masterStudent.FirstName) $($masterStudent.LastName) ($($masterStudent.Username)) - Email: $oldEmail -> $expectedEmail") | Out-Null
            }

            # Check and update Password if blank in master data
            if ([string]::IsNullOrWhiteSpace($masterStudent.Password)) {
            
                # Generate a new password
                $newPassword = Get-RandomPasswordSimple
                # Add/update Password property to the student object
                $masterStudent.Password = $newPassword
                $EmptyPasswordCount++
                
                $StudentsWithNewlyGeneratedPasswords.AppendLine("   - $($masterStudent.FirstName) $($masterStudent.LastName) ($($masterStudent.Username)), Year: $($masterStudent.YearLevel), Class: $($masterStudent.Class) - Password Generated.") | Out-Null
  
                # If not in MockMode, actually set the password in eduPass
                if ($Global:Config.ScriptBehavior.MockMode -ne $true) {
                    if (Get-Command Set-eduPassStudentAccountPassword -ErrorAction SilentlyContinue) {
                        try {
                            Set-eduPassStudentAccountPassword -Identity $masterStudent.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -Password $newPassword | Out-Null
                            Write-Log -Message "  SUCCESS: eduPass password set for $($masterStudent.Username)." -Level Information
                        } catch {
                            Write-Log -Message "  ERROR setting eduPass password for $($($masterStudent.Username)): $($_.Exception.Message)" -Level Error
                        }
                    } else {
                        Write-Log -Message "  WARNING: Function Set-eduPassStudentAccountPassword not found. Password not set in eduPass." -Level Warning
                    }
                } else {
                    Write-Log -Message "  MOCK MODE: Simulating Set-eduPassStudentAccountPassword for $($masterStudent.Username)" -Level Information
                }
            }
            
            # Add the processed student to the updated list
            $UpdatedExistingStudents += $masterStudent
        }
    } else {
        Write-Log -Message "No existing students to process." -Level Information
    }

    if ($StudentsWithDetailChanges.Length -gt 0) {
        $Global:ProcessingSummary.AppendLine("   Student Detail Changes (YearLevel/Class/Email):") | Out-Null
        $Global:ProcessingSummary.Append($StudentsWithDetailChanges.ToString()) | Out-Null
    }
    if ($EmptyPasswordCount -gt 0) {
        $Global:ProcessingSummary.AppendLine("   Existing Students with newly generated passwords:") | Out-Null
        $Global:ProcessingSummary.Append($StudentsWithNewlyGeneratedPasswords.ToString()) | Out-Null
        Write-Log -Message "Generated passwords for $EmptyPasswordCount existing students." -Level Information
    } else {
        Write-Log -Message "No existing students required new password generation." -Level Verbose
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
                # Write-Log -Message "  MOCK MODE: Simulating Set-eduPassStudentAccountPassword for $($student.Username)" -Level Information
                # Write-Log -Message "  MOCK MODE: Simulating Set-eduPassCloudServiceStatus (Google) for $($student.Username)" -Level Information
                # Write-Log -Message "  MOCK MODE: Simulating Set-eduPassCloudServiceStatus (Intune) for $($student.Username)" -Level Information
            } else {
                if ((Get-Command Set-eduPassStudentAccountPassword -ErrorAction SilentlyContinue) -and (Get-Command Set-eduPassCloudServiceStatus -ErrorAction SilentlyContinue)) {
                    try { Set-eduPassStudentAccountPassword -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -Password $newPassword; Write-Log -Message "  SUCCESS: eduPass password set for $($student.Username)." -Level Information } catch { Write-Log -Message "  ERROR setting eduPass password for $($student.Username): $($_.Exception.Message)" -Level Error }
                    try { Set-eduPassCloudServiceStatus -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -AccountType student -Service google -Status Enabled; Write-Log -Message "  SUCCESS: Google Cloud Service enabled for $($student.Username)." -Level Information } catch { Write-Log -Message "  ERROR enabling Google Cloud Service for $($student.Username): $($_.Exception.Message)" -Level Error }
                    try { Set-eduPassCloudServiceStatus -Identity $student.Username -SchoolNumber $Global:Config.SchoolSettings.SchoolNumber -AccountType student -Service intune -Status Enabled; Write-Log -Message "  SUCCESS: Intune Cloud Service enabled for $($student.Username)." -Level Information } catch { Write-Log -Message "  ERROR enabling Intune Cloud Service for $($student.Username): $($_.Exception.Message)" -Level Error }
                } else {
                    Write-Log -Message "  WARNING: eduPass/Cloud service functions not found. Skipping live account modifications." -Level Warning
                    $Global:ProcessingSummary.AppendLine("     WARNING: Live account modification functions not found.") | Out-Null
                }
            }
            $ProcessedNewStudents += $studentWithPassword
            # Write-Log -Message "Added new student $($student.Username) with generated password to processing list." -Level Verbose
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

    Write-Log -Message "DEBUG: About to return from Compare-StudentChanges" -Level Information
    Write-Log -Message "DEBUG: UpdatedExistingStudents count: $($UpdatedExistingStudents.Count), ProcessedNewStudents count: $($ProcessedNewStudents.Count)" -Level Information
    
    $result = @{ 
        ExistingStudents = if ($null -eq $UpdatedExistingStudents -or $UpdatedExistingStudents.Count -eq 0) { @() } else { $UpdatedExistingStudents } 
        ProcessedNewStudents = if ($null -eq $ProcessedNewStudents -or $ProcessedNewStudents.Count -eq 0) { @() } else { $ProcessedNewStudents }
        DepartedStudentsCount = if ($null -eq $DepartedStudents) { 0 } else { $DepartedStudents.Count }
    }
    
    Write-Log -Message "DEBUG: Result ExistingStudents count: $($result.ExistingStudents.Count), ProcessedNewStudents count: $($result.ProcessedNewStudents.Count)" -Level Information
    return $result
    
}

Function Update-MasterStudentData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [array]$ExistingStudents = @(),
        [Parameter(Mandatory=$false)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [array]$ProcessedNewStudents = @()
    )

    #Safe Guard Nullable Values:
    $ExistingStudents = if ($null -eq $ExistingStudents) { @() } else { $ExistingStudents }
    $ProcessedNewStudents = if ($null -eq $ProcessedNewStudents) { @() } else { $ProcessedNewStudents }

    Write-Log -Message "Step 5 & 6: Updating, saving, and archiving master student list..." -Level Information
    Write-Log -Message "DEBUG: Inside Update-MasterStudentData - ExistingStudents count: $($ExistingStudents.Count), ProcessedNewStudents count: $($ProcessedNewStudents.Count)" -Level Information
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

    if (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue)) {
        Write-Log -Message "CRITICAL: 'Export-Excel' command not found. The ImportExcel module is required or not loaded. Skipping Excel file generation for year levels." -Level Error
        $Global:ProcessingSummary.AppendLine("   ERROR: ImportExcel module not found/loaded. Year level Excel files not generated.") | Out-Null
        return
    }

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
            $YearLevelFilePath = Join-Path -Path $StudentsByYearLevelDir -ChildPath $YearLevelFileName

            $yearDataToExport = $StudentsInYear | Select-Object $RequiredHeaders

            try {
                Write-Log -Message "Attempting to export $($yearDataToExport.Count) students for Year [$year] to '$YearLevelFilePath'..." -Level Debug

                # Export to Excel with desired features
                Export-Excel -Path $YearLevelFilePath -InputObject $yearDataToExport `
                    -WorksheetName "Year $year Students" `
                    -FreezeTopRow `
                    -AutoFilter `
                    -AutoSize `
                    -BoldTopRow `

                Write-Log -Message "  Saved $($StudentsInYear.Count) students for Year [$year] to Excel: $YearLevelFilePath" -Level Information
                $Global:ProcessingSummary.AppendLine("   - Year $($year): $($StudentsInYear.Count) students saved to Excel file $YearLevelFilePath") | Out-Null
            } catch {
                Write-Log -Message "  ERROR saving year Excel file for [$year] to [$YearLevelFilePath]: $($_.Exception.Message)" -Level Error
                $Global:ProcessingSummary.AppendLine("   - Year $($year): ERROR saving Excel file - $($_.Exception.Message)") | Out-Null
            }
        } else {
            $studentsWithNoYear = $group.Group.Count
            Write-Log -Message "Skipping $studentsWithNoYear students with blank/null YearLevel." -Level Warning
            $Global:ProcessingSummary.AppendLine("   WARNING: Skipped $studentsWithNoYear students with blank/null YearLevel.") | Out-Null
        }
    }
}

$ScriptSuccess = $true 
try {
    $ActualDownloadedFilePath = Get-StudentDataDownload
    $StudentData = Get-StudentDataLists -DownloadedFilePath $ActualDownloadedFilePath
    $ProcessingResult = Compare-StudentChanges -DownloadedStudents $StudentData.DownloadedStudents -MasterStudents $StudentData.MasterStudents
    
    # Safely extract results with explicit null checks and force array types
    $ExistingStudentsToProcess = @()
    $ProcessedNewStudentsToUse = @()
    
    if ($null -ne $ProcessingResult.ExistingStudents) {
        $ExistingStudentsToProcess = @($ProcessingResult.ExistingStudents)
    }
    
    if ($null -ne $ProcessingResult.ProcessedNewStudents) {
        $ProcessedNewStudentsToUse = @($ProcessingResult.ProcessedNewStudents)
    }
    
    Write-Log -Message "Compare-StudentChanges completed: ExistingStudents: $($ExistingStudentsToProcess.Count), NewStudents: $($ProcessedNewStudentsToUse.Count), DepartedStudents: $($ProcessingResult.DepartedStudentsCount)" -Level Information
    Write-Log -Message "Processing results - ExistingStudents: $($ExistingStudentsToProcess.Count), NewStudents: $($ProcessedNewStudentsToUse.Count)" -Level Information
    
    # Debug: Check variable types and values before function call
    Write-Log -Message "DEBUG: About to call Update-MasterStudentData" -Level Information
    Write-Log -Message "DEBUG: ExistingStudentsToProcess is null: $($null -eq $ExistingStudentsToProcess)" -Level Information
    Write-Log -Message "DEBUG: ExistingStudentsToProcess type: $($ExistingStudentsToProcess.GetType().Name)" -Level Information
    Write-Log -Message "DEBUG: ProcessedNewStudentsToUse is null: $($null -eq $ProcessedNewStudentsToUse)" -Level Information
    Write-Log -Message "DEBUG: ProcessedNewStudentsToUse type: $($ProcessedNewStudentsToUse.GetType().Name)" -Level Information
    
    # Ensure arrays are properly initialized
    if ($null -eq $ExistingStudentsToProcess) { $ExistingStudentsToProcess = @() }
    if ($null -eq $ProcessedNewStudentsToUse) { $ProcessedNewStudentsToUse = @() }
    
    # Use splatting for safer parameter passing
    $updateParams = @{
        ExistingStudents = $ExistingStudentsToProcess
        ProcessedNewStudents = $ProcessedNewStudentsToUse
    }
    
    Write-Log -Message "DEBUG: Calling Update-MasterStudentData with splatting" -Level Information
    $FinalMasterList = Update-MasterStudentData @updateParams
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