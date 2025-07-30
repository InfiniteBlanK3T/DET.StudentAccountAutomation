# DET Student Account Automation - Troubleshooting Guide

## Table of Contents

- [Quick Diagnostic Checklist](#quick-diagnostic-checklist)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Error Code Reference](#error-code-reference)
- [Log File Analysis](#log-file-analysis)
- [Network and Connectivity Issues](#network-and-connectivity-issues)
- [Configuration Problems](#configuration-problems)
- [Email Notification Issues](#email-notification-issues)
- [File and Permission Problems](#file-and-permission-problems)
- [eduSTAR Integration Issues](#edustar-integration-issues)
- [Performance and Resource Issues](#performance-and-resource-issues)
- [Recovery Procedures](#recovery-procedures)
- [Escalation Guidelines](#escalation-guidelines)

## Quick Diagnostic Checklist

### Is the System Running? (First 2 Minutes)

#### ✅ Check These First

1. **Recent Log File Exists**

   ```
   Location: Scripts\Logs\DailyStudentProcessLog_YYYYMMDD.log
   Should have today's date and recent timestamp
   ```

2. **Email Reports Received**

   ```
   Check inbox for: "Daily Student Update Report"
   Subject should show SUCCESS or FAILED
   ```

3. **Files Being Updated**

   ```
   Check: Archived-Logs\MasterStudentData.csv
   Should have recent modification time
   ```

4. **Scheduled Task Status**
   ```
   Open Task Scheduler
   Look for: "Daily Student Data Processing" or similar
   Check: Last Run Result should be 0x0 (success)
   ```

#### ❌ If Any of These Fail

- **No recent log file** → [Script Not Running](#script-not-running)
- **No email reports** → [Email Issues](#email-notification-issues)
- **Old file timestamps** → [File Access Issues](#file-and-permission-problems)
- **Task scheduler errors** → [Scheduling Problems](#scheduled-task-issues)

## Common Issues and Solutions

### Script Not Running

#### Symptoms

- No log files created today
- No email notifications
- Task Scheduler shows errors
- Files not being updated

#### Possible Causes and Solutions

**1. PowerShell Execution Policy**

```powershell
# Check current policy
Get-ExecutionPolicy

# If Restricted or AllSigned, change it
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

**2. Missing PowerShell Modules**

```powershell
# Check if ImportExcel is installed
Get-Module ImportExcel -ListAvailable

# Install if missing
Install-Module ImportExcel -Scope AllUsers -Force
```

**3. Script Path Issues in Task Scheduler**

```
Verify in Task Scheduler:
- Program/script: powershell.exe
- Arguments: -ExecutionPolicy Bypass -File "FULL_PATH_TO_SCRIPT"
- Start in: Scripts directory path
```

**4. Permissions Issues**

```
Check that the scheduled task user account has:
- Read/Write access to Scripts directory
- Read/Write access to Archived-Logs directory
- Access to C:\Credentials directory
```

### Authentication Failures

#### Symptoms

- Log shows "Failed to connect to eduSTAR MC"
- Error messages about credentials
- No student data downloaded

#### Solutions

**1. Credential File Issues**

```powershell
# Delete corrupted credential file
Remove-Item "C:\Credentials\eduSTARMCAdministration\Creds.xml" -Force

# Run script manually to re-enter credentials
.\Process-DailyStudentUpdates.ps1
```

**2. Account Lockout**

```
Contact eduSTAR support if account is locked
Verify username/password work in web browser
Check for password expiration
```

**3. Network Connectivity**

```powershell
# Test connection to eduSTAR
Test-NetConnection -ComputerName apps.edustar.vic.edu.au -Port 443

# Test proxy settings
netsh winhttp show proxy
```

### Student Data Issues

#### Symptoms

- Zero new students consistently
- Students missing from reports
- Duplicate entries in data

#### Solutions

**1. Data Validation Issues**

```
Check log file for:
- "No student data available"
- "Duplicate usernames found"
- "Failed to parse student data"
```

**2. School Number Configuration**

```json
// Verify in config.json
"SchoolSettings": {
  "SchoolNumber": "8881"  // Must be exactly 4 digits
}
```

**3. Data Synchronization**

```
If seeing old data:
1. Enable Force refresh in next run
2. Delete cache files in %TEMP%\eduSTARMCAdministration\
3. Run script manually to verify fresh data
```

### PDF Generation Failures

#### Symptoms

- No PDF files in StudentsByYearLevel folders
- Errors about Export-Excel in logs
- Empty class list files

#### Solutions

**1. ImportExcel Module Issues**

```powershell
# Reinstall ImportExcel module
Uninstall-Module ImportExcel -Force
Install-Module ImportExcel -Scope AllUsers -Force

# Verify installation
Import-Module ImportExcel
Get-Command Export-Excel
```

**2. File Path Length Issues**

```
If paths are too long (>260 characters):
1. Move installation to shorter path like C:\StudentAutomation\
2. Or enable long path support in Windows
```

**3. Memory Issues**

```
If processing large numbers of students:
1. Check available RAM during processing
2. Consider processing smaller batches
3. Restart script service if memory usage high
```

## Error Code Reference

### PowerShell Error Codes

| Error Code | Description               | Solution                           |
| ---------- | ------------------------- | ---------------------------------- |
| 0x80131500 | JSON parsing error        | Fix syntax in config.json          |
| 0x80070005 | Access denied             | Check file permissions             |
| 0x80131509 | Module not found          | Install missing PowerShell modules |
| 0x80131501 | Network connection failed | Check network connectivity         |

### eduSTAR API Error Codes

| HTTP Code | Description         | Solution                             |
| --------- | ------------------- | ------------------------------------ |
| 401       | Unauthorized        | Re-enter credentials                 |
| 403       | Forbidden           | Check account permissions            |
| 429       | Rate limited        | Reduce request frequency             |
| 500       | Server error        | Retry later, contact eduSTAR support |
| 503       | Service unavailable | eduSTAR maintenance, retry later     |

### Custom Application Errors

| Error Message                                | Cause                        | Solution                        |
| -------------------------------------------- | ---------------------------- | ------------------------------- |
| "Configuration file 'config.json' not found" | Missing config file          | Copy from template              |
| "School number validation failed"            | Invalid school number format | Use 4-digit string              |
| "Failed to import module"                    | Missing PowerShell module    | Install required modules        |
| "Credential file corrupted"                  | Damaged credential storage   | Delete and re-enter credentials |

## Log File Analysis

### Log File Location

```
Scripts\Logs\DailyStudentProcessLog_YYYYMMDD.log
```

### Log Entry Format

```
[2025-07-30 03:00:15] [Information] Script execution started. Version 1.6
[2025-07-30 03:00:16] [Verbose] Project Root: G:\...\DET.StudentAccountAutomation
[2025-07-30 03:00:17] [Error] Failed to connect to eduSTAR MC: Unauthorized
```

### Key Indicators to Look For

#### ✅ Success Indicators

```
"Script execution started"
"eduSTAR MC Login successful"
"Updated student list obtained"
"Daily student processing completed successfully"
"Script execution finished"
```

#### ❌ Error Indicators

```
"CRITICAL ERROR:"
"Failed to connect"
"Authentication failed"
"Permission denied"
"Module not found"
```

#### ⚠️ Warning Indicators

```
"No new students found"
"Password not set in eduPass"
"Duplicate usernames found"
"Cleanup skipped"
```

### Log Analysis PowerShell Commands

```powershell
# Get today's log file
$LogFile = "Scripts\Logs\DailyStudentProcessLog_$(Get-Date -Format 'yyyyMMdd').log"

# Check for errors
Get-Content $LogFile | Where-Object { $_ -like "*[Error]*" }

# Check for critical issues
Get-Content $LogFile | Where-Object { $_ -like "*CRITICAL*" }

# Get summary statistics
Get-Content $LogFile | Where-Object { $_ -like "*New Students:*" -or $_ -like "*Departed Students:*" }

# Check processing duration
$StartTime = (Get-Content $LogFile | Where-Object { $_ -like "*Script execution started*" })[0]
$EndTime = (Get-Content $LogFile | Where-Object { $_ -like "*Script execution finished*" })[0]
```

## Network and Connectivity Issues

### eduSTAR Connectivity Tests

#### Basic Connectivity

```powershell
# Test HTTPS connection
Test-NetConnection -ComputerName apps.edustar.vic.edu.au -Port 443

# Test with web request
try {
    Invoke-WebRequest -Uri "https://apps.edustar.vic.edu.au" -UseBasicParsing
    Write-Host "✅ Basic connection successful"
} catch {
    Write-Host "❌ Connection failed: $($_.Exception.Message)"
}
```

#### Proxy Configuration Issues

```powershell
# Check proxy settings
$ProxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
Write-Host "Proxy Enabled: $($ProxySettings.ProxyEnable)"
Write-Host "Proxy Server: $($ProxySettings.ProxyServer)"

# Test proxy configuration
$Proxy = New-Object System.Net.WebProxy($ProxySettings.ProxyServer)
$WebClient = New-Object System.Net.WebClient
$WebClient.Proxy = $Proxy
try {
    $WebClient.DownloadString("https://apps.edustar.vic.edu.au")
    Write-Host "✅ Proxy connection successful"
} catch {
    Write-Host "❌ Proxy connection failed"
}
```

#### Certificate Issues

```powershell
# Check certificate chain
$Certificate = [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
    param($sender, $certificate, $chain, $errors)
    Write-Host "Certificate Subject: $($certificate.Subject)"
    Write-Host "Certificate Errors: $errors"
    return $true
}

# Force TLS 1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
```

### Firewall and Security Software

#### Windows Firewall

```powershell
# Check if PowerShell is allowed through firewall
Get-NetFirewallRule -DisplayName "*PowerShell*" | Select-Object DisplayName, Enabled, Direction

# Create firewall rule if needed
New-NetFirewallRule -DisplayName "Student Automation PowerShell" -Direction Outbound -Program "%SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe" -Action Allow
```

#### Antivirus Exclusions

Add these paths to antivirus exclusions:

```
G:\...\DET.StudentAccountAutomation\Scripts\
C:\Credentials\eduSTARMCAdministration\
%TEMP%\eduSTARMCAdministration\
```

## Configuration Problems

### JSON Syntax Errors

#### Common Syntax Issues

```json
// ❌ Trailing comma
{
  "SchoolNumber": "8881",
  "SchoolName": "Sample School",  // <- Remove this comma
}

// ❌ Missing quotes
{
  SchoolNumber: "8881"  // <- Should be "SchoolNumber"
}

// ❌ Wrong comment style
{
  "SchoolNumber": "8881" /* Should use // not /* */
}
```

#### Validation Script

```powershell
# Test config.json syntax
try {
    $Config = Get-Content "config.json" | ConvertFrom-Json
    Write-Host "✅ Configuration file is valid JSON"

    # Test required fields
    if (-not $Config.SchoolSettings.SchoolNumber) {
        Write-Host "❌ Missing SchoolNumber"
    }
    if (-not $Config.SchoolSettings.SchoolName) {
        Write-Host "❌ Missing SchoolName"
    }
} catch {
    Write-Host "❌ JSON syntax error: $($_.Exception.Message)"
}
```

### School Configuration Issues

#### School Number Format

```json
// ✅ Correct formats
"SchoolNumber": "8881"
"SchoolNumber": "0123"

// ❌ Incorrect formats
"SchoolNumber": 8881      // Should be string, not number
"SchoolNumber": "881"     // Should be 4 digits
"SchoolNumber": "88810"   // Should be exactly 4 digits
```

#### Email Configuration

```json
// ✅ Correct email format
"To": "admin@school.vic.edu.au;ict@school.vic.edu.au"
"From": "automation@school.vic.edu.au"

// ❌ Incorrect formats
"To": "admin@school.vic.edu.au, ict@school.vic.edu.au"  // Use semicolon, not comma
"From": "automation"  // Must be full email address
```

## Email Notification Issues

### SMTP Configuration Problems

#### Common SMTP Issues

```json
// ✅ Typical working configuration
{
  "SmtpServer": "smtp.school.vic.edu.au",
  "Port": 25,
  "From": "automation@school.vic.edu.au"
}

// ❌ Common mistakes
{
  "SmtpServer": "smtp.school.vic.edu.au:25",  // Don't include port in server name
  "Port": "25",  // Should be number, not string
  "From": "automation"  // Must be full email address
}
```

#### SMTP Testing

```powershell
# Test SMTP connection
$SmtpServer = "smtp.school.vic.edu.au"
$Port = 25

try {
    $SmtpClient = New-Object System.Net.Mail.SmtpClient($SmtpServer, $Port)
    $SmtpClient.Send("test@school.vic.edu.au", "admin@school.vic.edu.au", "Test", "Test message")
    Write-Host "✅ SMTP test successful"
} catch {
    Write-Host "❌ SMTP test failed: $($_.Exception.Message)"
}
```

### Email Delivery Issues

#### Check Spam/Junk Folders

- Automated emails often go to spam
- Add sender to safe sender list
- Check email rules that might redirect emails

#### Mock Mode Email Redirection

```json
// When MockMode is enabled, emails go to TestEmail instead
{
  "ScriptBehavior": {
    "MockMode": true,
    "TestEmail": "test@school.vic.edu.au"
  }
}
```

#### Email Content Issues

```powershell
# Check email body generation
$EmailBody = Get-ProcessSummaryEmailBody -IsSuccessful $true -UseHtml $true
Write-Host $EmailBody
```

## File and Permission Problems

### File Access Issues

#### Common Permission Problems

```
❌ Access denied writing to Scripts\Logs\
❌ Cannot create Archived-Logs\MasterStudentData.csv
❌ Permission denied accessing C:\Credentials\
```

#### Permission Verification

```powershell
# Check current user permissions
$User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host "Running as: $User"

# Check file permissions
$Acl = Get-Acl "Scripts"
$Acl.Access | Where-Object { $_.IdentityReference -like "*$($env:USERNAME)*" }

# Check if running with admin rights
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
Write-Host "Running as Administrator: $IsAdmin"
```

#### Fix Permission Issues

```powershell
# Grant full control to current user
$Path = "G:\...\DET.StudentAccountAutomation"
$User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Acl = Get-Acl $Path
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($AccessRule)
Set-Acl -Path $Path -AclObject $Acl
```

### File Locking Issues

#### Symptoms

- "File is being used by another process"
- Cannot update CSV files
- Log file access denied

#### Solutions

```powershell
# Find processes using files
$FilePath = "Archived-Logs\MasterStudentData.csv"
$Processes = Get-Process | Where-Object { $_.Modules.FileName -like "*$FilePath*" }
$Processes | Stop-Process -Force

# Alternative: Use PowerShell file operations instead of external programs
# Ensure Excel/CSV editors are closed before script runs
```

### Disk Space Issues

#### Check Available Space

```powershell
$Drive = (Get-Location).Drive
$FreeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($Drive.Name)'").FreeSpace / 1GB
Write-Host "Free space on $($Drive.Name): $([math]::Round($FreeSpace, 2)) GB"

if ($FreeSpace -lt 1) {
    Write-Host "❌ Low disk space warning"
}
```

#### Cleanup Procedures

```powershell
# Manual cleanup of old files
$LogDir = "Scripts\Logs"
$OldLogs = Get-ChildItem $LogDir | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
$OldLogs | Remove-Item -Force

$ArchiveDir = "Archived-Logs\ArchivedCurrentData"
$OldArchives = Get-ChildItem $ArchiveDir | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-90) }
$OldArchives | Remove-Item -Force
```

## eduSTAR Integration Issues

### API Authentication Problems

#### Credential Issues

```powershell
# Test credential file
$CredsPath = "C:\Credentials\eduSTARMCAdministration\Creds.xml"
if (Test-Path $CredsPath) {
    try {
        $Creds = Import-Clixml $CredsPath
        Write-Host "✅ Credential file loaded"
        Write-Host "Username: $($Creds.UserName)"
    } catch {
        Write-Host "❌ Credential file corrupted"
        Remove-Item $CredsPath -Force
    }
} else {
    Write-Host "❌ Credential file not found"
}
```

#### Session Management Issues

```powershell
# Test eduSTAR session
if ($script:eduSTARMCSession) {
    try {
        $TestResponse = Invoke-RestMethod -Uri "https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetUser" -WebSession $script:eduSTARMCSession
        Write-Host "✅ Session is valid"
    } catch {
        Write-Host "❌ Session expired or invalid"
        $script:eduSTARMCSession = $null
    }
}
```

### Data Retrieval Issues

#### No Student Data Returned

```powershell
# Debug student data retrieval
$SchoolNumber = $Global:Config.SchoolSettings.SchoolNumber
Write-Host "Testing with school number: $SchoolNumber"

$Students = Get-eduPassStudentAccount -SchoolNumber $SchoolNumber -Force
if ($Students) {
    Write-Host "✅ Retrieved $($Students.Count) students"
} else {
    Write-Host "❌ No student data received"
    # Check if school number is correct
    # Verify account has access to this school
}
```

#### Incomplete Data

```powershell
# Check data completeness
$Students | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.Username)) {
        Write-Host "❌ Missing username for student: $($_.FirstName) $($_.LastName)"
    }
    if ([string]::IsNullOrWhiteSpace($_.YearLevel)) {
        Write-Host "❌ Missing year level for student: $($_.Username)"
    }
}
```

### Rate Limiting and Performance

#### API Rate Limiting

```powershell
# Implement request throttling
function Invoke-ThrottledRequest {
    param($Uri, $Method, $Body, $WebSession)

    $MaxRetries = 3
    $RetryCount = 0

    do {
        try {
            $Response = Invoke-RestMethod -Uri $Uri -Method $Method -Body $Body -WebSession $WebSession
            return $Response
        } catch {
            if ($_.Exception.Response.StatusCode -eq 429) {
                $RetryAfter = $_.Exception.Response.Headers["Retry-After"]
                Write-Host "Rate limited. Waiting $RetryAfter seconds..."
                Start-Sleep -Seconds $RetryAfter
                $RetryCount++
            } else {
                throw
            }
        }
    } while ($RetryCount -lt $MaxRetries)
}
```

## Performance and Resource Issues

### Memory Usage Problems

#### Monitor Memory Usage

```powershell
# Check PowerShell memory usage
$Process = Get-Process | Where-Object { $_.ProcessName -eq "powershell" -and $_.CommandLine -like "*Process-DailyStudentUpdates*" }
$MemoryMB = $Process.WorkingSet64 / 1MB
Write-Host "Memory usage: $([math]::Round($MemoryMB, 2)) MB"

if ($MemoryMB -gt 512) {
    Write-Host "⚠️ High memory usage detected"
}
```

#### Memory Optimization

```powershell
# Force garbage collection
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

# Clear large variables
$LargeArray = $null
Remove-Variable LargeArray -ErrorAction SilentlyContinue
```

### Processing Time Issues

#### Performance Monitoring

```powershell
# Time critical operations
$StartTime = Get-Date
# Critical operation here
$Duration = (Get-Date) - $StartTime
Write-Host "Operation completed in $($Duration.TotalSeconds) seconds"

# Log slow operations
if ($Duration.TotalSeconds -gt 60) {
    Write-Log "Slow operation detected: $($Duration.TotalSeconds) seconds" -Level Warning
}
```

#### Optimization Strategies

```powershell
# Process in batches for large datasets
$BatchSize = 100
for ($i = 0; $i -lt $Students.Count; $i += $BatchSize) {
    $Batch = $Students[$i..($i + $BatchSize - 1)]
    # Process batch
    Write-Progress -Activity "Processing Students" -PercentComplete (($i / $Students.Count) * 100)
}
```

## Recovery Procedures

### Configuration Recovery

#### Backup Configuration

```powershell
# Create configuration backup
$BackupName = "config.json.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item "config.json" $BackupName
Write-Host "Configuration backed up to: $BackupName"
```

#### Restore from Template

```powershell
# Restore from template
if (Test-Path "config.json.template") {
    Copy-Item "config.json.template" "config.json"
    Write-Host "Configuration restored from template"
    Write-Host "⚠️ Remember to update school-specific settings"
} else {
    Write-Host "❌ Template file not found"
}
```

### Data Recovery

#### Restore Master Data

```powershell
# List available backups
$ArchiveDir = "Archived-Logs\ArchivedCurrentData"
$Backups = Get-ChildItem $ArchiveDir -Filter "ArchivedMasterStudentData_*.csv" | Sort-Object LastWriteTime -Descending

Write-Host "Available backups:"
$Backups | ForEach-Object { Write-Host "  $($_.Name) - $($_.LastWriteTime)" }

# Restore from most recent backup
if ($Backups.Count -gt 0) {
    $LatestBackup = $Backups[0]
    Copy-Item $LatestBackup.FullName "Archived-Logs\MasterStudentData.csv"
    Write-Host "✅ Master data restored from: $($LatestBackup.Name)"
}
```

### Complete System Recovery

#### Emergency Recovery Script

```powershell
# Emergency recovery procedure
Write-Host "Starting emergency recovery..."

# 1. Backup current state
$RecoveryDir = "Recovery_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory $RecoveryDir
Copy-Item "config.json" "$RecoveryDir\config.json.corrupted" -ErrorAction SilentlyContinue

# 2. Reset configuration
Copy-Item "config.json.template" "config.json"

# 3. Clear credential cache
Remove-Item "C:\Credentials\eduSTARMCAdministration\Creds.xml" -Force -ErrorAction SilentlyContinue

# 4. Restore data from backup
$LatestBackup = Get-ChildItem "Archived-Logs\ArchivedCurrentData" -Filter "*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($LatestBackup) {
    Copy-Item $LatestBackup.FullName "Archived-Logs\MasterStudentData.csv"
}

Write-Host "✅ Emergency recovery completed"
Write-Host "⚠️ Update config.json with your school settings"
Write-Host "⚠️ Run script manually to re-enter credentials"
```

## Escalation Guidelines

### When to Escalate

#### Level 1: Self-Resolution (0-30 minutes)

- Check obvious issues (logs, email, files)
- Verify configuration
- Restart services
- Check network connectivity

#### Level 2: Technical Support (30 minutes - 2 hours)

- Authentication issues persist
- Configuration problems beyond basic fixes
- Performance issues
- Data integrity problems

#### Level 3: Developer/Vendor Support (2+ hours)

- eduSTAR API changes
- PowerShell module compatibility issues
- System architecture problems
- Security vulnerabilities

### Information to Collect Before Escalating

#### System Information

```powershell
# Collect system info
$SystemInfo = @{
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    PowerShellVersion = $PSVersionTable.PSVersion
    OSVersion = (Get-WmiObject Win32_OperatingSystem).Caption
    LastBootTime = (Get-WmiObject Win32_OperatingSystem).LastBootUpTime
}

$SystemInfo | ConvertTo-Json
```

#### Configuration State

```powershell
# Sanitize config for sharing (remove sensitive info)
$Config = Get-Content "config.json" | ConvertFrom-Json
$Config.EmailNotification.From = "***REDACTED***"
$Config.EmailNotification.To = "***REDACTED***"
$Config | ConvertTo-Json -Depth 5
```

#### Recent Logs

```powershell
# Get last 50 lines of today's log
$LogFile = "Scripts\Logs\DailyStudentProcessLog_$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $LogFile) {
    Get-Content $LogFile | Select-Object -Last 50
}
```

#### Error Details

```powershell
# Get recent errors
$LogFile = "Scripts\Logs\DailyStudentProcessLog_$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $LogFile) {
    Get-Content $LogFile | Where-Object { $_ -like "*[Error]*" -or $_ -like "*CRITICAL*" }
}
```

### Contact Information

#### Primary Support

- **Name:** Thomas VO (ST02392)
- **Email:** Thomas.Vo3@education.vic.gov.au
- **Role:** Developer/Primary Support

#### Secondary Support

- **Local IT Team:** Your school's IT support
- **eduSTAR Support:** For eduSTAR platform issues
- **DET ICT Service Desk:** For system-wide issues

### Support Request Template

```
Subject: DET Student Account Automation - [URGENT/NORMAL] - [Brief Description]

School: [School Name]
School Number: [XXXX]
System: [Computer Name]
Date/Time: [When issue occurred]

Issue Description:
[Detailed description of the problem]

Error Messages:
[Copy exact error messages from logs]

Steps Already Taken:
[List troubleshooting steps already attempted]

System Information:
[Include system info collected above]

Recent Changes:
[Any recent changes to system, network, or configuration]

Impact:
[How this affects daily operations]

Urgency Level:
[Critical/High/Medium/Low and why]
```

---

## Quick Reference Cards

### Daily Health Check Commands

```powershell
# Check if script ran today
$LogFile = "Scripts\Logs\DailyStudentProcessLog_$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $LogFile) { "✅ Log exists" } else { "❌ No log today" }

# Check for errors in today's log
Get-Content $LogFile | Where-Object { $_ -like "*[Error]*" } | Measure-Object | Select-Object -ExpandProperty Count

# Check master data age
$MasterFile = "Archived-Logs\MasterStudentData.csv"
if (Test-Path $MasterFile) {
    $Age = (Get-Date) - (Get-Item $MasterFile).LastWriteTime
    "Master data age: $($Age.Days) days"
}

# Check scheduled task
Get-ScheduledTask | Where-Object { $_.TaskName -like "*Student*" } | Select-Object TaskName, State, LastRunTime
```

### Emergency Stop Procedures

```powershell
# Stop all related PowerShell processes
Get-Process powershell | Where-Object { $_.CommandLine -like "*Student*" } | Stop-Process -Force

# Disable scheduled task
Disable-ScheduledTask -TaskName "Daily Student Data Processing"

# Enable MockMode
$Config = Get-Content "config.json" | ConvertFrom-Json
$Config.ScriptBehavior.MockMode = $true
$Config | ConvertTo-Json -Depth 5 | Set-Content "config.json"
```

This troubleshooting guide provides comprehensive coverage of common issues and their solutions. Keep this document accessible for quick reference during problem resolution.
