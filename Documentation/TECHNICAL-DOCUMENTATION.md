# DET Student Account Automation - Technical Documentation

## Table of Contents

- [System Architecture](#system-architecture)
- [Module Documentation](#module-documentation)
- [Configuration Reference](#configuration-reference)
- [API Integration](#api-integration)
- [Security Implementation](#security-implementation)
- [Data Flow and Processing](#data-flow-and-processing)
- [Error Handling and Logging](#error-handling-and-logging)
- [Deployment and Maintenance](#deployment-and-maintenance)
- [Development Guidelines](#development-guidelines)
- [Advanced Troubleshooting](#advanced-troubleshooting)

## System Architecture

### Overview

The DET Student Account Automation system is built as a modular PowerShell application designed to integrate with the eduSTAR Management Console API. The system follows a service-oriented architecture with clear separation of concerns.

### Version Information

- **Current Version:** 1.6
- **Author:** Thomas VO (ST02392) - Thomas.Vo3@education.vic.gov.au
- **Platform:** Windows PowerShell 5.1+ / PowerShell Core 7+
- **Dependencies:** ImportExcel module, System.Net.Http

### Core Components

#### Primary Script

- **Process-DailyStudentUpdates.ps1** - Main orchestration script

#### PowerShell Modules (.psm1)

- **EduSTARHelper.psm1** - eduSTAR MC API integration
- **StudentDataHelper.psm1** - Student data comparison and processing
- **MiscHelper.psm1** - Utility functions and email notifications
- **PDFGenerationHelper.psm1** - PDF and HTML generation
- **EmailNotificationHelper.psm1** - Email service integration
- **UtilityHelper.psm1** - General utility functions

#### Configuration

- **config.json** - Runtime configuration
- **config.json.template** - Template for new deployments

### Directory Structure

```
DET.StudentAccountAutomation/
├── Scripts/                    # Application code
│   ├── Process-DailyStudentUpdates.ps1  # Main entry point
│   ├── *.psm1                 # PowerShell modules
│   ├── config.json            # Runtime configuration
│   └── Logs/                  # Application logs
├── Archived-Logs/             # Data storage
│   ├── MasterStudentData.csv  # Primary student database
│   ├── DailyDownloads/        # Daily API downloads
│   └── ArchivedCurrentData/   # Historical backups
└── StudentsByYearLevel/       # Generated reports
    └── Year_XX/               # Year-level class lists
```

## Module Documentation

### EduSTARHelper.psm1

#### Purpose

Provides integration with the eduSTAR Management Console REST API for student account management.

#### Key Functions

##### Set-eMCCredentials

```powershell
function Set-eMCCredentials {
    <#
    .SYNOPSIS
        Stores and manages credentials for eduSTAR MC access.
    .DESCRIPTION
        Creates secure credential storage at C:\Credentials\eduSTARMCAdministration\
        Uses Export-Clixml for secure credential persistence.
    #>
}
```

**Implementation Details:**

- Hardcoded credential path: `C:\Credentials\eduSTARMCAdministration\Creds.xml`
- Uses Windows DPAPI for encryption via Export-Clixml
- Automatic credential validation and re-prompting on failure

##### Connect-eduSTARMC

```powershell
function Connect-eduSTARMC {
    <#
    .SYNOPSIS
        Establishes authenticated session with eduSTAR MC.
    .DESCRIPTION
        Performs proxy detection, credential management, and session establishment.
        Maintains session state in script-scoped variable $script:eduSTARMCSession.
    #>
}
```

**Implementation Details:**

- Proxy auto-detection with fallback mechanisms
- Session persistence through WebRequestSession objects
- Automatic retry logic for connection failures
- Session validation through Keep-Alive headers

##### Get-eduPassStudentAccount

```powershell
function Get-eduPassStudentAccount {
    param(
        [string]$SchoolNumber,
        [string]$Identity,
        [switch]$Force
    )
}
```

**Implementation Details:**

- XML REST API communication
- Response caching in %TEMP%\eduSTARMCAdministration\
- Force parameter bypasses cache for fresh data
- Comprehensive error handling with detailed logging

#### API Endpoints Used

- **Authentication:** `https://apps.edustar.vic.edu.au/CookieAuth.dll?Logon`
- **Student Data:** `https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetAccountDetails`
- **Password Reset:** `https://apps.edustar.vic.edu.au/edustarmc/api/MC/ResetPassword`
- **Cloud Services:** `https://apps.edustar.vic.edu.au/edustarmc/api/MC/SetCloudServiceStatus`

### StudentDataHelper.psm1

#### Purpose

Handles comparison logic between downloaded student data and existing master records.

##### Compare-StudentLists

```powershell
function Compare-StudentLists {
    param(
        [array]$DownloadedStudents,
        [array]$MasterStudents
    )
    return [PSCustomObject]@{
        NewStudents      = $newStudentList
        DepartedStudents = $departedStudentList
        ExistingStudents = $existingStudentList
    }
}
```

**Algorithm:**

1. Extract unique usernames from both datasets
2. Use Compare-Object to identify differences
3. Cross-reference with original objects to preserve full student records
4. Return categorized student collections

##### Test-DuplicationEntry

```powershell
function Test-DuplicationEntry {
    param(
        [array]$CurrentData,
        [string]$OutputPathForDuplicates
    )
    return [bool]
}
```

**Implementation:**

- Groups students by Username property
- Identifies records where Count > 1
- Exports duplicate records to timestamped CSV
- Returns boolean indicating presence of duplicates

### MiscHelper.psm1

#### Purpose

Provides utility functions for email notifications, file cleanup, and password generation.

##### Get-RandomPasswordSimple

```powershell
function Get-RandomPasswordSimple {
    [OutputType([string])]
    param()
}
```

**Password Generation Algorithm:**

- Selects random word from predefined arrays (animals, colors, objects)
- Appends random 4-digit number
- Format: `Word.1234`
- Word arrays contain 40+ entries each for adequate entropy

##### Send-NotificationEmail

```powershell
function Send-NotificationEmail {
    param(
        [ValidateSet("AdminError", "ProcessSummary")]
        [string]$NotificationType,
        [bool]$IsScriptSuccessful,
        [string]$CustomMessage,
        [string]$CustomDetails
    )
}
```

**Email Types:**

- **AdminError:** Critical error notifications with immediate delivery
- **ProcessSummary:** Daily processing reports with statistics

**Features:**

- HTML and plain text formats
- MockMode email redirection
- SMTP authentication support
- Comprehensive error handling

##### Invoke-FileCleanUp

```powershell
function Invoke-FileCleanUp {
    param()
}
```

**Cleanup Logic:**

- Day-of-week scheduling
- Configurable retention periods
- Separate retention for logs vs. archives
- MockMode simulation support
- Detailed logging of cleanup actions

### PDFGenerationHelper.psm1

#### Purpose

Generates PDF reports for student lists organized by year level and class.

##### Generate-StudentListPDF

```powershell
function Generate-StudentListPDF {
    param(
        [array]$Students,
        [string]$OutputPath,
        [string]$YearLevel,
        [string]$ClassName
    )
}
```

**Implementation:**

- HTML-to-PDF conversion using WebView2
- A4 page formatting with optimized margins
- School branding and header information
- Automatic page numbering
- Error handling with fallback mechanisms

## Configuration Reference

### JSON Schema Overview

```json
{
  "SchoolSettings": {
    "SchoolNumber": "string(4)",
    "SchoolName": "string"
  },
  "FileNames": {
    "MasterStudentData": "string"
  },
  "EmailNotification": {
    "Enabled": "boolean",
    "To": "string(semicolon-separated)",
    "From": "string(email)",
    "SubjectPrefix": "string",
    "SmtpServer": "string(hostname)",
    "Port": "integer",
    "SendOnSuccessOnly": "boolean",
    "AdminNotifyOnError": "boolean",
    "AdminEmailOnError": "string(semicolon-separated)",
    "BodyAsHtml": "boolean"
  },
  "Logging": {
    "LogLevel": "string(enum)"
  },
  "ScriptBehavior": {
    "MockMode": "boolean",
    "TestEmail": "string(semicolon-separated)",
    "RemoveQuotesFromCsv": "boolean"
  },
  "CleanupSettings": {
    "Enabled": "boolean",
    "RunOnDayOfWeek": "string(enum)",
    "RetentionDaysLogs": "integer",
    "RetentionDaysArchives": "integer"
  }
}
```

### Configuration Validation

The system performs runtime validation of configuration parameters:

#### Required Fields

- `SchoolSettings.SchoolNumber` - Must be 4-digit string
- `SchoolSettings.SchoolName` - Non-empty string
- `EmailNotification.From` - Valid email format
- `EmailNotification.SmtpServer` - Valid hostname

#### Enumerated Values

```powershell
# LogLevel options
$ValidLogLevels = @("Verbose", "Information", "Warning", "Error", "Debug")

# Day of week options
$ValidDays = @("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
```

#### Default Values

```json
{
  "Port": 25,
  "SendOnSuccessOnly": true,
  "AdminNotifyOnError": true,
  "BodyAsHtml": false,
  "LogLevel": "Information",
  "MockMode": true,
  "RemoveQuotesFromCsv": true,
  "RetentionDaysLogs": 7,
  "RetentionDaysArchives": 7
}
```

## API Integration

### eduSTAR MC REST API

#### Authentication Flow

1. **Credential Retrieval:** Load stored credentials or prompt user
2. **Proxy Detection:** Test direct connection, configure proxy if needed
3. **Login Request:** POST to CookieAuth.dll with credentials
4. **Session Validation:** Verify Keep-Alive header and status code 200
5. **Session Persistence:** Store WebRequestSession for subsequent calls

#### Request/Response Format

```xml
<!-- Example Student Account Request -->
<ArrayOfString xmlns="http://schemas.microsoft.com/2003/10/Serialization/Arrays">
    <string>8881</string>
    <string>student</string>
    <string></string>
</ArrayOfString>

<!-- Example Response -->
<ArrayOfAccount xmlns="http://schemas.datacontract.org/2004/07/eduSTAR.MC.WebService">
    <Account>
        <_class>1A</_class>
        <_desc>Year 01</_desc>
        <_dn>CN=student.name,OU=Students,OU=8881,DC=edustar,DC=vic,DC=edu,DC=au</_dn>
        <_login>student.name</_login>
        <_firstName>Student</_firstName>
        <_lastName>Name</_lastName>
    </Account>
</ArrayOfAccount>
```

#### Error Handling

```powershell
try {
    $Response = Invoke-RestMethod -Uri $ApiEndpoint -Method $Method -WebSession $Session
} catch {
    if ($_.Exception.Response) {
        $StatusCode = $_.Exception.Response.StatusCode
        $ResponseStream = $_.Exception.Response.GetResponseStream()
        $StreamReader = New-Object System.IO.StreamReader($ResponseStream)
        $ErrorBody = $StreamReader.ReadToEnd()
        Write-Log "API Error: $StatusCode - $ErrorBody" -Level Error
    }
    throw
}
```

#### Rate Limiting and Caching

- **Cache Duration:** 1 hour for student data (configurable)
- **Cache Location:** `%TEMP%\eduSTARMCAdministration\{SchoolNumber}-Students.xml`
- **Force Refresh:** `-Force` parameter bypasses cache
- **Rate Limiting:** Built-in delays between bulk operations

## Security Implementation

### Credential Management

- **Storage Location:** `C:\Credentials\eduSTARMCAdministration\Creds.xml`
- **Encryption:** Windows DPAPI via Export-Clixml
- **Access Control:** Requires local administrator rights
- **Validation:** Automatic credential testing and re-prompting

### Network Security

- **HTTPS Enforcement:** All API calls use HTTPS
- **Certificate Validation:** Standard .NET certificate chain validation
- **Proxy Support:** Automatic proxy detection and configuration
- **Timeout Settings:** Configurable connection timeouts

### Data Protection

- **Local Storage:** Student data stored in secure directory structure
- **File Permissions:** Restricted access to service account
- **Audit Trail:** Comprehensive logging of all data access
- **Data Retention:** Configurable cleanup of old files

### Mock Mode Security

```powershell
if ($Global:Config.ScriptBehavior.MockMode) {
    Write-Log "MOCK MODE: Simulating $Operation for $Username" -Level Information
    # Simulation logic - no actual API calls
    return $SimulatedResult
}
```

## Data Flow and Processing

### Daily Processing Workflow

#### Phase 1: Initialization

1. **Configuration Loading:** Parse and validate config.json
2. **Module Import:** Load all PowerShell modules
3. **Directory Setup:** Ensure required directories exist
4. **Logging Setup:** Initialize daily log file

#### Phase 2: Data Acquisition

1. **eduSTAR Connection:** Establish authenticated session
2. **Student Download:** Fetch complete student list via API
3. **Data Validation:** Verify download completeness and format
4. **File Storage:** Save to DailyDownloads with timestamp

#### Phase 3: Data Processing

1. **Master Data Load:** Import existing MasterStudentData.csv
2. **Comparison Logic:** Identify new, departed, and existing students
3. **Password Generation:** Create passwords for students without them
4. **Data Enrichment:** Add metadata and processing timestamps

#### Phase 4: Account Updates (Live Mode Only)

1. **New Student Processing:**
   - Set eduPass password
   - Enable Google cloud services
   - Enable Intune cloud services
2. **Existing Student Processing:**
   - Update passwords for blank entries
   - Verify account status
   - Update metadata

#### Phase 5: Data Persistence

1. **Archive Creation:** Backup current master data with timestamp
2. **Master Update:** Write new master data file
3. **Year Level Split:** Generate class-specific files
4. **PDF Generation:** Create printable class lists

#### Phase 6: Cleanup and Notification

1. **File Cleanup:** Remove old logs and archives (if scheduled)
2. **Session Cleanup:** Disconnect from eduSTAR MC
3. **Email Notification:** Send processing summary
4. **Logging Finalization:** Complete log file

### Data Structures

#### Student Record Format

```powershell
[PSCustomObject]@{
    Username         = "student.name"
    FirstName        = "Student"
    LastName         = "Name"
    YearLevel        = "Year 01"
    Class            = "1A"
    Email            = "student.name@schools.vic.edu.au"
    Password         = "Apple.1234"
    DistinguishedName = "CN=student.name,OU=Students,OU=8881,DC=edustar,DC=vic,DC=edu,DC=au"
    ProcessingDate   = "2025-07-30"
    AccountStatus    = "Active"
}
```

#### Processing Summary Format

```powershell
$Global:ProcessingSummary = [System.Text.StringBuilder]::new()
$Global:ProcessingSummary.AppendLine("New Students: $NewCount") | Out-Null
$Global:ProcessingSummary.AppendLine("Departed Students: $DepartedCount") | Out-Null
$Global:ProcessingSummary.AppendLine("Existing Students: $ExistingCount") | Out-Null
```

## Error Handling and Logging

### Logging Framework

#### Log Levels

```powershell
[ValidateSet("Information", "Verbose", "Warning", "Error", "Debug")]
```

#### Log Format

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message content with context
```

#### Log File Management

- **Location:** `Scripts/Logs/DailyStudentProcessLog_YYYYMMDD.log`
- **Rotation:** Daily rotation based on date
- **Retention:** Configurable cleanup via CleanupSettings
- **Encoding:** UTF-8 for international character support

### Error Handling Patterns

#### API Communication Errors

```powershell
try {
    $Result = Invoke-RestMethod -Uri $ApiUrl -Method Post -WebSession $Session
} catch [System.Net.WebException] {
    Write-Log "Network error connecting to eduSTAR: $($_.Exception.Message)" -Level Error
    Send-NotificationEmail -NotificationType "AdminError" -CustomMessage "eduSTAR connection failed"
    throw
} catch {
    Write-Log "Unexpected error in API call: $($_.Exception.Message)" -Level Error
    throw
}
```

#### File System Errors

```powershell
try {
    $CsvContent | Set-Content -Path $FilePath -Encoding UTF8 -Force
} catch [System.UnauthorizedAccessException] {
    Write-Log "Permission denied writing to $FilePath" -Level Error
    throw "Insufficient permissions for file operations"
} catch [System.IO.IOException] {
    Write-Log "I/O error writing to $FilePath: $($_.Exception.Message)" -Level Error
    throw
}
```

#### Configuration Errors

```powershell
try {
    $Config = Get-Content -Path $ConfigPath | ConvertFrom-Json
    if (-not $Config.SchoolSettings.SchoolNumber) {
        throw "SchoolNumber is required in configuration"
    }
} catch [System.ArgumentException] {
    Write-Error "Invalid JSON format in config.json"
    Exit 1
}
```

### Critical Error Notifications

```powershell
function Send-CriticalError {
    param($ErrorMessage, $ErrorDetails)

    Send-NotificationEmail -NotificationType "AdminError" -CustomMessage $ErrorMessage -CustomDetails $ErrorDetails
    Write-Log "CRITICAL ERROR: $ErrorMessage" -Level Error
    $Global:ProcessingSummary.AppendLine("CRITICAL ERROR: $ErrorMessage") | Out-Null
}
```

## Deployment and Maintenance

### System Requirements

- **Operating System:** Windows Server 2012 R2+ or Windows 10+
- **PowerShell:** Version 5.1 or later
- **Network:** HTTPS access to apps.edustar.vic.edu.au
- **Permissions:** Local administrator for credential storage
- **Disk Space:** Minimum 100MB for logs and data
- **Memory:** 512MB RAM recommended

### Installation Process

#### 1. File Deployment

```powershell
# Copy files to target location
$TargetPath = "C:\StudentAccountAutomation"
Copy-Item -Path ".\Scripts\*" -Destination "$TargetPath\Scripts\" -Recurse
```

#### 2. Module Installation

```powershell
# Install required PowerShell modules
Install-Module ImportExcel -Scope AllUsers -Force
```

#### 3. Configuration Setup

```powershell
# Create configuration from template
Copy-Item -Path "config.json.template" -Destination "config.json"
# Manual editing required for school-specific settings
```

#### 4. Permissions Configuration

```powershell
# Set appropriate permissions
$Acl = Get-Acl $TargetPath
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($AccessRule)
Set-Acl -Path $TargetPath -AclObject $Acl
```

#### 5. Scheduled Task Creation

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4">
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>2025-01-01T03:00:00</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -File "C:\StudentAccountAutomation\Scripts\Process-DailyStudentUpdates.ps1"</Arguments>
      <WorkingDirectory>C:\StudentAccountAutomation\Scripts</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
```

### Monitoring and Maintenance

#### Daily Monitoring

- **Email Reports:** Verify daily processing emails arrive
- **Log Review:** Check latest log file for warnings/errors
- **File Timestamps:** Verify recent file creation in output directories

#### Weekly Maintenance

- **Performance Review:** Analyze processing times and resource usage
- **Error Pattern Analysis:** Look for recurring issues in logs
- **Backup Verification:** Ensure archive files are being created

#### Monthly Maintenance

- **Configuration Review:** Verify settings remain appropriate
- **Cleanup Verification:** Confirm old files are being removed
- **Capacity Planning:** Monitor disk space usage trends

#### Quarterly Maintenance

- **Security Review:** Update credentials and review permissions
- **Module Updates:** Check for PowerShell module updates
- **Documentation Updates:** Refresh procedures and contact information

### Backup and Recovery

#### Configuration Backup

```powershell
# Backup configuration
Copy-Item -Path "config.json" -Destination "config.json.backup.$(Get-Date -Format 'yyyyMMdd')"
```

#### Data Recovery Procedures

1. **Master Data Recovery:** Restore from ArchivedCurrentData folder
2. **Configuration Recovery:** Restore from backup config.json
3. **Credential Recovery:** Re-run Set-eMCCredentials function
4. **Full System Recovery:** Redeploy from source with backed-up configuration

## Development Guidelines

### Code Style Standards

#### PowerShell Best Practices

```powershell
# Use approved verbs
function Get-StudentData { }     # ✓ Good
function FetchStudentData { }    # ✗ Avoid

# Parameter validation
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$SchoolNumber
)

# Error handling
try {
    # Main logic
} catch [SpecificException] {
    # Specific handling
} catch {
    # General handling
    throw
}
```

#### Documentation Standards

```powershell
function Get-StudentData {
    <#
    .SYNOPSIS
        Brief description of function purpose.
    .DESCRIPTION
        Detailed description of what the function does.
    .PARAMETER SchoolNumber
        Description of the parameter.
    .EXAMPLE
        Get-StudentData -SchoolNumber "8881"
    .NOTES
        Additional notes about usage or limitations.
    #>
}
```

#### Module Structure

```powershell
# Function implementations
function Public-Function { }
function Private-Function { }

# Export only public functions
Export-ModuleMember -Function Public-Function

# Module loading confirmation
Write-Verbose "[Utils] ModuleName.psm1 loaded successfully."
```

### Testing Framework

#### Unit Testing Approach

```powershell
# Mock external dependencies
Mock Invoke-RestMethod { return $TestData }
Mock Set-Content { }

# Test function behavior
Describe "Compare-StudentLists" {
    It "Should identify new students correctly" {
        $Result = Compare-StudentLists -DownloadedStudents $TestDownload -MasterStudents $TestMaster
        $Result.NewStudents.Count | Should -Be 2
    }
}
```

#### Integration Testing

```powershell
# Test with MockMode enabled
$Global:Config.ScriptBehavior.MockMode = $true
$Result = .\Process-DailyStudentUpdates.ps1
# Verify no actual changes made
```

### Version Control and Deployment

#### Version Management

- **Semantic Versioning:** MAJOR.MINOR.PATCH
- **Change Documentation:** Maintain detailed changelog
- **Backward Compatibility:** Ensure configuration compatibility

#### Deployment Pipeline

1. **Development:** Local development and testing
2. **Staging:** Test environment with mock data
3. **User Acceptance:** End-user validation
4. **Production:** Live deployment with monitoring

## Advanced Troubleshooting

### Performance Issues

#### Memory Usage

```powershell
# Monitor memory consumption
$Process = Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*Process-DailyStudentUpdates*" }
Write-Log "Memory usage: $($Process.WorkingSet64 / 1MB) MB" -Level Debug
```

#### Processing Time Analysis

```powershell
$StepStart = Get-Date
# Processing step
$StepDuration = (Get-Date) - $StepStart
Write-Log "Step completed in $($StepDuration.TotalSeconds) seconds" -Level Debug
```

### Network Connectivity Issues

#### Proxy Troubleshooting

```powershell
function Test-ProxyConfiguration {
    $ProxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Write-Log "Proxy enabled: $($ProxySettings.ProxyEnable)" -Level Debug
    Write-Log "Proxy server: $($ProxySettings.ProxyServer)" -Level Debug
}
```

#### SSL/TLS Issues

```powershell
# Force TLS 1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Certificate validation override (development only)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
```

### API Integration Issues

#### Session Management

```powershell
function Test-SessionValidity {
    try {
        $TestCall = Invoke-RestMethod -Uri "https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetUser" -WebSession $script:eduSTARMCSession
        return $true
    } catch {
        return $false
    }
}
```

#### Rate Limiting Detection

```powershell
if ($Response.StatusCode -eq 429) {
    $RetryAfter = $Response.Headers["Retry-After"]
    Write-Log "Rate limited. Retry after $RetryAfter seconds" -Level Warning
    Start-Sleep -Seconds $RetryAfter
}
```

### Data Integrity Issues

#### Duplicate Detection

```powershell
function Find-DataInconsistencies {
    param([array]$StudentData)

    # Check for duplicate usernames
    $Duplicates = $StudentData | Group-Object Username | Where-Object { $_.Count -gt 1 }

    # Check for missing required fields
    $MissingData = $StudentData | Where-Object {
        [string]::IsNullOrWhiteSpace($_.Username) -or
        [string]::IsNullOrWhiteSpace($_.FirstName) -or
        [string]::IsNullOrWhiteSpace($_.LastName)
    }

    return @{
        Duplicates = $Duplicates
        MissingData = $MissingData
    }
}
```

### Recovery Procedures

#### Configuration Recovery

```powershell
function Restore-Configuration {
    param([string]$BackupDate)

    $BackupFile = "config.json.backup.$BackupDate"
    if (Test-Path $BackupFile) {
        Copy-Item $BackupFile "config.json"
        Write-Log "Configuration restored from $BackupFile" -Level Information
    } else {
        throw "Backup file not found: $BackupFile"
    }
}
```

#### Data Recovery

```powershell
function Restore-MasterData {
    param([string]$ArchiveDate)

    $ArchiveFile = "ArchivedMasterStudentData_MasterStudentData_$ArchiveDate.csv"
    $ArchivePath = Join-Path $ArchivedMasterDataDir $ArchiveFile

    if (Test-Path $ArchivePath) {
        Copy-Item $ArchivePath $MasterStudentDataFile
        Write-Log "Master data restored from $ArchivePath" -Level Information
    } else {
        throw "Archive file not found: $ArchivePath"
    }
}
```

---

## Security Considerations

### Credential Management Best Practices

- Regular credential rotation (quarterly recommended)
- Service account usage for scheduled tasks
- Principle of least privilege for file system access
- Audit trail for credential access and modifications

### Network Security

- HTTPS enforcement for all external communications
- Certificate pinning consideration for production environments
- Network segmentation for automation services
- Firewall rules for eduSTAR MC access only

### Data Protection

- Encryption at rest for sensitive student data
- Secure deletion of temporary files
- Access logging for compliance requirements
- Regular security assessments and updates

This technical documentation provides comprehensive coverage of the system architecture, implementation details, and operational procedures for the DET Student Account Automation system. For additional support or clarification on any technical aspects, contact the development team.
