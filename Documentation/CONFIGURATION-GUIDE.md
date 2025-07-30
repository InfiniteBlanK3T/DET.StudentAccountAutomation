# DET Student Account Automation - Quick Configuration Guide

## Step-by-Step Setup for New Installations

### Prerequisites Check

Before starting, ensure you have:

- [ ] Windows Server 2012 R2+ or Windows 10+
- [ ] PowerShell 5.1 or later
- [ ] Administrator access to the target computer
- [ ] Network access to apps.edustar.vic.edu.au
- [ ] Valid eduSTAR Management Console credentials
- [ ] SMTP server details for email notifications

### Step 1: File Setup

1. **Copy the automation files** to your chosen location (e.g., `C:\StudentAccountAutomation\`)

2. **Verify the directory structure** looks like this:

   ```
   StudentAccountAutomation/
   ├── Scripts/
   │   ├── Process-DailyStudentUpdates.ps1
   │   ├── *.psm1 (PowerShell modules)
   │   ├── config.json.template
   │   └── Logs/ (will be created)
   ├── Archived-Logs/
   │   ├── DailyDownloads/ (will be created)
   │   └── ArchivedCurrentData/ (will be created)
   └── StudentsByYearLevel/ (will be created)
   ```

### Step 2: Install Required PowerShell Modules

Open PowerShell as Administrator and run:

```powershell
# Install ImportExcel module (required for PDF generation)
Install-Module ImportExcel -Scope AllUsers -Force

# Verify installation
Get-Module ImportExcel -ListAvailable
```

### Step 3: Create Configuration File

1. **Copy the template:**

   ```powershell
   cd "C:\StudentAccountAutomation\Scripts"
   Copy-Item "config.json.template" "config.json"
   ```

2. **Edit config.json** with your school's specific settings (see details below)

### Step 4: Configure Your Settings

Open `config.json` in a text editor and update these sections:

#### School Settings (REQUIRED)

```json
"SchoolSettings": {
  "SchoolNumber": "XXXX",           ← Your 4-digit school number
  "SchoolName": "Your School Name"  ← Your school's full name
}
```

#### Email Notifications (REQUIRED)

```json
"EmailNotification": {
  "Enabled": true,
  "To": "admin@yourschool.vic.edu.au;ict@yourschool.vic.edu.au",
  "From": "automation@yourschool.vic.edu.au",
  "SubjectPrefix": "Daily Student Update Report",
  "SmtpServer": "smtp.yourschool.vic.edu.au",
  "Port": 25,
  "AdminEmailOnError": "admin@yourschool.vic.edu.au"
}
```

#### Safety Settings (IMPORTANT)

```json
"ScriptBehavior": {
  "MockMode": true,                 ← ALWAYS start with true for testing
  "TestEmail": "test@yourschool.vic.edu.au",
  "RemoveQuotesFromCsv": true
}
```

### Step 5: Test the Configuration

1. **Open PowerShell as Administrator**

2. **Navigate to the Scripts directory:**

   ```powershell
   cd "C:\StudentAccountAutomation\Scripts"
   ```

3. **Run the script manually:**

   ```powershell
   .\Process-DailyStudentUpdates.ps1
   ```

4. **You will be prompted for eduSTAR credentials** - enter your eduSTAR MC username and password

5. **Check the results:**
   - Look for success messages in the console
   - Check for a new log file in `Scripts\Logs\`
   - Verify you receive a test email
   - Confirm no actual changes were made (MockMode should be enabled)

### Step 6: Review Test Results

#### ✅ Success Indicators

- Console shows "Script execution finished"
- Log file created with today's date
- Email received with summary
- No error messages in red

#### ❌ Failure Indicators

- Red error messages in console
- No log file created
- No email received
- "FAILED" in console output

### Step 7: Set Up Automated Scheduling

Once testing is successful:

1. **Open Task Scheduler**

2. **Create a new task** with these settings:

   - **Name:** Daily Student Account Updates
   - **Trigger:** Daily at 3:00 AM (or preferred time)
   - **Action:** Start a program
   - **Program:** `powershell.exe`
   - **Arguments:** `-ExecutionPolicy Bypass -File "C:\StudentAccountAutomation\Scripts\Process-DailyStudentUpdates.ps1"`
   - **Start in:** `C:\StudentAccountAutomation\Scripts\`

3. **Configure security:**
   - Run whether user is logged on or not
   - Run with highest privileges
   - Use a service account with appropriate permissions

### Step 8: Enable Production Mode

After successful testing for several days:

1. **Edit config.json**

2. **Change MockMode to false:**

   ```json
   "ScriptBehavior": {
     "MockMode": false,
     "TestEmail": "test@yourschool.vic.edu.au",
     "RemoveQuotesFromCsv": true
   }
   ```

3. **Update email recipients** to remove test addresses and add production recipients

4. **Run manually once more** to verify production settings work correctly

## Configuration Reference

### Complete Configuration Template with Examples

```json
{
  "SchoolSettings": {
    "SchoolNumber": "8881",
    "SchoolName": "Sample Primary School"
  },
  "FileNames": {
    "MasterStudentData": "MasterStudentData.csv"
  },
  "EmailNotification": {
    "Enabled": true,
    "To": "principal@sample.vic.edu.au;admin@sample.vic.edu.au;ict@sample.vic.edu.au",
    "From": "automation_noreply@sample.vic.edu.au",
    "SubjectPrefix": "Daily Student Update Report",
    "SmtpServer": "smtp.sample.vic.edu.au",
    "Port": 25,
    "SendOnSuccessOnly": true,
    "AdminNotifyOnError": true,
    "AdminEmailOnError": "admin@sample.vic.edu.au;principal@sample.vic.edu.au",
    "BodyAsHtml": true
  },
  "Logging": {
    "LogLevel": "Information"
  },
  "ScriptBehavior": {
    "MockMode": false,
    "TestEmail": "test@sample.vic.edu.au",
    "RemoveQuotesFromCsv": true
  },
  "CleanupSettings": {
    "Enabled": true,
    "RunOnDayOfWeek": "Monday",
    "RetentionDaysLogs": 30,
    "RetentionDaysArchives": 90
  }
}
```

### Configuration Options Explained

#### SchoolSettings

- **SchoolNumber:** Your 4-digit DET school number (must be a string)
- **SchoolName:** Full school name for email reports and logging

#### FileNames

- **MasterStudentData:** Name of the main student database file (default: "MasterStudentData.csv")

#### EmailNotification

- **Enabled:** Set to `false` to disable all email notifications
- **To:** Semicolon-separated list of recipients for daily reports
- **From:** Sender address (must be authorized by your SMTP server)
- **SubjectPrefix:** Text to appear at the start of email subjects
- **SmtpServer:** Your organization's SMTP server hostname
- **Port:** SMTP port (usually 25 for internal servers)
- **SendOnSuccessOnly:** If `true`, only sends emails when script completes successfully
- **AdminNotifyOnError:** If `true`, sends immediate emails for critical errors
- **AdminEmailOnError:** Recipients for critical error notifications
- **BodyAsHtml:** If `true`, sends formatted HTML emails (recommended)

#### Logging

- **LogLevel:** Controls console output verbosity
  - `"Verbose"` - Very detailed output (for troubleshooting)
  - `"Information"` - Standard detail level (recommended)
  - `"Warning"` - Only warnings and errors
  - `"Error"` - Only errors
  - `"Debug"` - Development-level detail

#### ScriptBehavior

- **MockMode:** When `true`, simulates all operations without making real changes
- **TestEmail:** In MockMode, all emails go to this address instead
- **RemoveQuotesFromCsv:** If `true`, removes quotes from generated CSV files

#### CleanupSettings

- **Enabled:** Set to `false` to disable automatic file cleanup
- **RunOnDayOfWeek:** Day of the week to perform cleanup ("Monday", "Tuesday", etc.)
- **RetentionDaysLogs:** Number of days to keep log files
- **RetentionDaysArchives:** Number of days to keep archived student data

## Common Configuration Mistakes

### ❌ Incorrect JSON Syntax

```json
// Wrong - trailing comma
{
  "SchoolNumber": "8881",
  "SchoolName": "Sample School",  ← Remove this comma
}

// Wrong - unquoted keys
{
  SchoolNumber: "8881"  ← Should be "SchoolNumber"
}
```

### ❌ Wrong Data Types

```json
// Wrong - numbers should be strings for school number
"SchoolNumber": 8881    ← Should be "8881"

// Wrong - port should be number not string
"Port": "25"            ← Should be 25
```

### ❌ Invalid Email Format

```json
// Wrong - comma separated instead of semicolon
"To": "admin@school.vic.edu.au, ict@school.vic.edu.au"

// Correct - semicolon separated
"To": "admin@school.vic.edu.au;ict@school.vic.edu.au"
```

## Validation Script

Use this PowerShell script to validate your configuration:

```powershell
# Configuration validation script
$ConfigPath = "config.json"

try {
    $Config = Get-Content $ConfigPath | ConvertFrom-Json
    Write-Host "✅ JSON syntax is valid" -ForegroundColor Green

    # Check required fields
    $Errors = @()

    if (-not $Config.SchoolSettings.SchoolNumber) {
        $Errors += "Missing SchoolNumber"
    } elseif ($Config.SchoolSettings.SchoolNumber -notmatch '^\d{4}$') {
        $Errors += "SchoolNumber must be 4 digits"
    }

    if (-not $Config.SchoolSettings.SchoolName) {
        $Errors += "Missing SchoolName"
    }

    if ($Config.EmailNotification.Enabled -and -not $Config.EmailNotification.From) {
        $Errors += "Missing From email address"
    }

    if ($Config.EmailNotification.Enabled -and -not $Config.EmailNotification.SmtpServer) {
        $Errors += "Missing SMTP server"
    }

    if ($Errors.Count -eq 0) {
        Write-Host "✅ Configuration validation passed" -ForegroundColor Green
    } else {
        Write-Host "❌ Configuration errors found:" -ForegroundColor Red
        $Errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    }

} catch {
    Write-Host "❌ JSON syntax error: $($_.Exception.Message)" -ForegroundColor Red
}
```

## Security Considerations

### File Permissions

Ensure the following permissions are set:

- **Scripts directory:** Read/Write for service account, Read for administrators
- **Archived-Logs directory:** Read/Write for service account
- **C:\Credentials directory:** Full control for service account only

### Network Security

- Ensure firewall allows HTTPS (port 443) to apps.edustar.vic.edu.au
- Ensure firewall allows SMTP (usually port 25) to your mail server
- Consider using a dedicated service account with minimal privileges

### Credential Security

- Credentials are encrypted using Windows DPAPI
- Only the user who stored them can decrypt them
- Store credentials using a service account, not a personal account
- Rotate eduSTAR credentials regularly (quarterly recommended)

## Post-Installation Checklist

### Daily (First Week)

- [ ] Check email reports arrive on time
- [ ] Review log files for any warnings or errors
- [ ] Verify new student data is being processed correctly
- [ ] Confirm PDF files are being generated

### Weekly (First Month)

- [ ] Monitor processing time and performance
- [ ] Check disk space usage trends
- [ ] Verify cleanup process is working (if enabled)
- [ ] Review any recurring warnings in logs

### Monthly (Ongoing)

- [ ] Update email recipient lists as needed
- [ ] Review and update retention settings
- [ ] Check for any system or network changes that might affect operation
- [ ] Test disaster recovery procedures

### Quarterly (Ongoing)

- [ ] Rotate eduSTAR credentials
- [ ] Review and update configuration as needed
- [ ] Test email delivery to ensure it's not being caught by spam filters
- [ ] Update documentation and procedures

## Getting Help

### Self-Service Resources

1. **Log Files:** Check `Scripts\Logs\` for detailed error information
2. **Configuration Validation:** Use the validation script above
3. **Test Mode:** Use MockMode to test changes safely

### Support Contacts

- **Primary:** Thomas VO (ST02392) - Thomas.Vo3@education.vic.gov.au
- **Documentation:** See the comprehensive guides in the Documentation folder
- **Emergency:** Use the emergency recovery procedures in the troubleshooting guide

### Before Contacting Support

Please gather this information:

1. Your school number and name
2. The exact error message you're seeing
3. The most recent log file
4. Your configuration file (with sensitive information removed)
5. What you were trying to accomplish when the error occurred

This configuration guide should help you get the DET Student Account Automation system set up and running successfully. Remember to always test thoroughly in MockMode before enabling production operations.
