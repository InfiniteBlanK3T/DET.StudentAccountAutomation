# Template File Editing Guide - DET Student Account Automation

## Overview

This guide explains how to properly edit the `config.json.template` file and other template files in the DET Student Account Automation system. It provides detailed examples and common scenarios to help you configure the system correctly for your school.

## Understanding the Template Structure

### What is config.json.template?

The `config.json.template` file is a template that contains all the configuration options for the automation system with example values and detailed comments. You copy this file to create your actual `config.json` configuration file.

**Key differences:**

- **Template file:** Contains examples and comments, not used by the system
- **Config file:** Your actual settings that the system reads and uses

### Template File Workflow

```
config.json.template → Copy → config.json → Edit for your school → Test → Production
```

## Step-by-Step Template Editing

### Step 1: Create Your Configuration File

```powershell
# Navigate to the Scripts directory
cd "C:\StudentAccountAutomation\Scripts"

# Copy the template to create your config file
Copy-Item "config.json.template" "config.json"
```

### Step 2: Open config.json for Editing

Use any text editor:

- **Notepad++** (recommended)
- **Visual Studio Code** (recommended for syntax highlighting)
- **Notepad** (basic but works)
- **PowerShell ISE** (good for testing)

### Step 3: Edit Each Section

## Section-by-Section Editing Guide

### 1. School Settings (CRITICAL - MUST CHANGE)

**Template:**

```json
"SchoolSettings": {
  "SchoolNumber": "0000", // Replace 0000 with your 4-digit school number (e.g., "8881")
  "SchoolName": "Your School Name" // Replace with your school's full name (e.g., "Sample Primary School")
},
```

**Your edits:**

```json
"SchoolSettings": {
  "SchoolNumber": "8881", // Your actual school number
  "SchoolName": "Tarneit Rise Primary School" // Your actual school name
},
```

**Important notes:**

- School number MUST be exactly 4 digits in quotes
- School name appears in email reports and logs
- These settings are used for eduSTAR API calls

### 2. File Names (USUALLY DON'T CHANGE)

**Template:**

```json
"FileNames": {
  "MasterStudentData": "MasterStudentData.csv", // Name of your primary student data file - without it it would START FRESH
},
```

**Typical usage:**

```json
"FileNames": {
  "MasterStudentData": "MasterStudentData.csv", // Keep default unless you have a reason to change
},
```

**When to change:**

- If you already have a student data file with a different name
- If you want to organize multiple schools in the same directory

### 3. Email Notification (CRITICAL - MUST CHANGE)

**Template:**

```json
"EmailNotification": {
  "Enabled": true, // true to enable email notifications, false to disable
  "To": "recipient1@example.com;recipient2@example.com", // Semicolon-separated list of email addresses for summary reports
  "From": "automation_noreply@example.com", // "From" address for emails sent by the script
  "SubjectPrefix": "Daily Student Update Report", // Prefix for email subject lines
  "SmtpServer": "smtp.yourschool.vic.edu.au", // Your SMTP server address (e.g., "smtp.education.vic.gov.au") - default setting does not need to be changed unless you have a different SMTP server
  "Port": 25, // SMTP port (usually 25, or 587/465 for SSL/TLS)
  "SendOnSuccessOnly": true, // true to send summary email only if script completes successfully; false to send on success or failure
  "AdminNotifyOnError": true, // true to send an immediate email to AdminEmailOnError if a critical script error occurs
  "AdminEmailOnError": "admin1@example.com;admin2@example.com", // Semicolon-separated list for critical error notifications
  "BodyAsHtml": false // true if the email body should be HTML, false for plain text
},
```

**Your edits:**

```json
"EmailNotification": {
  "Enabled": true,
  "To": "principal@tarneitrise.vic.edu.au;admin@tarneitrise.vic.edu.au;ict@tarneitrise.vic.edu.au",
  "From": "studentautomation@tarneitrise.vic.edu.au",
  "SubjectPrefix": "Daily Student Update Report - Tarneit Rise PS",
  "SmtpServer": "smtp.tarneitrise.vic.edu.au",
  "Port": 25,
  "SendOnSuccessOnly": true,
  "AdminNotifyOnError": true,
  "AdminEmailOnError": "principal@tarneitrise.vic.edu.au;admin@tarneitrise.vic.edu.au",
  "BodyAsHtml": true
},
```

**Email configuration tips:**

- Use semicolons (`;`) to separate multiple email addresses
- The "From" address must be authorized by your SMTP server
- HTML emails look better but plain text works if HTML causes issues
- Start with fewer recipients and add more once the system is working

### 4. Logging (USUALLY KEEP DEFAULT)

**Template:**

```json
"Logging": {
  "LogLevel": "Information" // Controls console output verbosity. Options: "Verbose", "Information", "Warning", "Error", "Debug". Log file always gets all levels.
},
```

**Recommended settings:**

- **Information** - Normal operation (recommended)
- **Verbose** - When troubleshooting issues
- **Warning** - When you only want to see problems
- **Error** - When you only want to see serious problems

**Example for troubleshooting:**

```json
"Logging": {
  "LogLevel": "Verbose" // Use during initial setup and troubleshooting
},
```

### 5. Script Behavior (CRITICAL FOR SAFETY)

**Template:**

```json
"ScriptBehavior": {
  "MockMode": true, // true to simulate eduPass operations (no live changes); false for production runs. START WITH TRUE!
  "TestEmail": "test_user@example.com", // Email address(es) to send ALL emails to when MockMode is true (semicolon-separated)
  "RemoveQuotesFromCsv": true // true to remove all double quotes from generated CSV files; false to keep them (standard CSV format)
},
```

**Your edits for TESTING:**

```json
"ScriptBehavior": {
  "MockMode": true, // ALWAYS start with true
  "TestEmail": "testuser@tarneitrise.vic.edu.au", // Your test email
  "RemoveQuotesFromCsv": true
},
```

**Your edits for PRODUCTION (only after testing):**

```json
"ScriptBehavior": {
  "MockMode": false, // Change to false only after successful testing
  "TestEmail": "testuser@tarneitrise.vic.edu.au", // Keep for future testing
  "RemoveQuotesFromCsv": true
},
```

**SAFETY WARNING:** Always test with MockMode = true first!

### 6. Cleanup Settings (OPTIONAL)

**Template:**

```json
"CleanupSettings": {
  "Enabled": true, // true to enable automated cleanup of old log and archive files, false to disable
  "RunOnDayOfWeek": "Monday", // Day of the week to run cleanup. Options: "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
  "RetentionDaysLogs": 7, // Number of days to keep log files before deleting
  "RetentionDaysArchives": 7 // Number of days to keep archived data files before deleting
}
```

**Recommended settings:**

```json
"CleanupSettings": {
  "Enabled": true,
  "RunOnDayOfWeek": "Monday", // Choose a day that works for your schedule
  "RetentionDaysLogs": 30, // Keep logs for 1 month
  "RetentionDaysArchives": 90 // Keep archived student data for 3 months
}
```

**Considerations:**

- More retention days = more disk space used
- Less retention days = less historical data for troubleshooting
- Cleanup runs only on the specified day of the week
- You can disable cleanup by setting "Enabled": false

## Common Editing Scenarios

### Scenario 1: Basic School Setup

For a typical primary school with basic requirements:

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
    "To": "principal@sample.vic.edu.au;admin@sample.vic.edu.au",
    "From": "automation@sample.vic.edu.au",
    "SubjectPrefix": "Daily Student Update Report",
    "SmtpServer": "smtp.sample.vic.edu.au",
    "Port": 25,
    "SendOnSuccessOnly": true,
    "AdminNotifyOnError": true,
    "AdminEmailOnError": "admin@sample.vic.edu.au",
    "BodyAsHtml": true
  },
  "Logging": {
    "LogLevel": "Information"
  },
  "ScriptBehavior": {
    "MockMode": true,
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

### Scenario 2: Multi-Campus Setup

For schools with multiple campuses sharing the same system:

```json
{
  "SchoolSettings": {
    "SchoolNumber": "8881",
    "SchoolName": "Sample College - All Campuses"
  },
  "FileNames": {
    "MasterStudentData": "MasterStudentData_AllCampuses.csv"
  },
  "EmailNotification": {
    "Enabled": true,
    "To": "principal@sample.vic.edu.au;campus1.admin@sample.vic.edu.au;campus2.admin@sample.vic.edu.au;ict@sample.vic.edu.au",
    "From": "automation@sample.vic.edu.au",
    "SubjectPrefix": "Daily Student Update Report - All Campuses",
    "SmtpServer": "smtp.sample.vic.edu.au",
    "Port": 25,
    "SendOnSuccessOnly": false,
    "AdminNotifyOnError": true,
    "AdminEmailOnError": "principal@sample.vic.edu.au;ict@sample.vic.edu.au",
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
    "RunOnDayOfWeek": "Sunday",
    "RetentionDaysLogs": 60,
    "RetentionDaysArchives": 180
  }
}
```

### Scenario 3: High-Security Environment

For schools with strict security requirements:

```json
{
  "SchoolSettings": {
    "SchoolNumber": "8881",
    "SchoolName": "Sample Secondary College"
  },
  "FileNames": {
    "MasterStudentData": "MasterStudentData.csv"
  },
  "EmailNotification": {
    "Enabled": true,
    "To": "ict.admin@sample.vic.edu.au",
    "From": "noreply.automation@sample.vic.edu.au",
    "SubjectPrefix": "[AUTOMATED] Student System Report",
    "SmtpServer": "mail.sample.vic.edu.au",
    "Port": 587,
    "SendOnSuccessOnly": false,
    "AdminNotifyOnError": true,
    "AdminEmailOnError": "security.admin@sample.vic.edu.au;ict.manager@sample.vic.edu.au",
    "BodyAsHtml": true
  },
  "Logging": {
    "LogLevel": "Verbose"
  },
  "ScriptBehavior": {
    "MockMode": false,
    "TestEmail": "automation.test@sample.vic.edu.au",
    "RemoveQuotesFromCsv": true
  },
  "CleanupSettings": {
    "Enabled": true,
    "RunOnDayOfWeek": "Saturday",
    "RetentionDaysLogs": 90,
    "RetentionDaysArchives": 365
  }
}
```

## JSON Syntax Rules

### Critical Syntax Requirements

1. **Quotes:** All keys and string values must be in double quotes

   ```json
   "SchoolNumber": "8881"  ✅ Correct
   SchoolNumber: "8881"    ❌ Wrong - missing quotes around key
   "SchoolNumber": 8881    ❌ Wrong - number should be string for school number
   ```

2. **Commas:** Use commas between items, but NOT after the last item

   ```json
   {
     "SchoolNumber": "8881",
     "SchoolName": "Sample School"  ← No comma after last item
   }
   ```

3. **Comments:** JSON doesn't support comments, but the template uses them for explanation

   ```json
   // Template (with comments) - for reference only
   "SchoolNumber": "8881", // Your school number

   // Your config.json (no comments) - actual file
   "SchoolNumber": "8881"
   ```

4. **Email Lists:** Use semicolons, not commas
   ```json
   "To": "admin@school.vic.edu.au;ict@school.vic.edu.au"  ✅ Correct
   "To": "admin@school.vic.edu.au,ict@school.vic.edu.au"  ❌ Wrong
   ```

### Validation

Use this PowerShell command to check your JSON syntax:

```powershell
try {
    $Config = Get-Content "config.json" | ConvertFrom-Json
    Write-Host "✅ JSON syntax is valid" -ForegroundColor Green
} catch {
    Write-Host "❌ JSON syntax error: $($_.Exception.Message)" -ForegroundColor Red
}
```

## Testing Your Configuration

### Phase 1: Syntax Testing

1. **Check JSON syntax** using the validation command above
2. **Fix any syntax errors** before proceeding

### Phase 2: Mock Mode Testing

1. **Ensure MockMode is true** in your config.json
2. **Run the script manually:**
   ```powershell
   cd "C:\StudentAccountAutomation\Scripts"
   .\Process-DailyStudentUpdates.ps1
   ```
3. **Check for:**
   - No red error messages
   - Email sent to TestEmail address
   - Log file created successfully
   - "MOCK MODE" messages in the output

### Phase 3: Configuration Validation

Check these specific items:

```powershell
# Test email configuration
$Config = Get-Content "config.json" | ConvertFrom-Json
Write-Host "School: $($Config.SchoolSettings.SchoolName)"
Write-Host "School Number: $($Config.SchoolSettings.SchoolNumber)"
Write-Host "Email Recipients: $($Config.EmailNotification.To)"
Write-Host "SMTP Server: $($Config.EmailNotification.SmtpServer)"
Write-Host "Mock Mode: $($Config.ScriptBehavior.MockMode)"
```

### Phase 4: Production Readiness

Only proceed to production after:

- [ ] Successful mock mode testing for at least 3 runs
- [ ] Email notifications working correctly
- [ ] Log files showing expected information
- [ ] No error messages in testing
- [ ] All stakeholders trained on reading reports

## Common Editing Mistakes

### 1. School Number Format Issues

```json
❌ "SchoolNumber": 8881        // Should be string, not number
❌ "SchoolNumber": "881"       // Should be 4 digits
❌ "SchoolNumber": "08881"     // Should be exactly 4 digits
✅ "SchoolNumber": "8881"      // Correct format
```

### 2. Email Configuration Mistakes

```json
❌ "To": "admin@school.vic.edu.au, ict@school.vic.edu.au"    // Comma instead of semicolon
❌ "From": "automation"                                       // Must be full email address
❌ "SmtpServer": "smtp.school.vic.edu.au:25"                // Don't include port in server name
✅ "To": "admin@school.vic.edu.au;ict@school.vic.edu.au"    // Correct format
✅ "From": "automation@school.vic.edu.au"                   // Full email address
✅ "SmtpServer": "smtp.school.vic.edu.au"                   // Server name only
```

### 3. JSON Syntax Errors

```json
❌ {
     "SchoolNumber": "8881",
     "SchoolName": "School",   ← Remove this comma
   }

❌ {
     SchoolNumber: "8881"      ← Missing quotes around key
   }

✅ {
     "SchoolNumber": "8881",
     "SchoolName": "School"
   }
```

### 4. Boolean Value Mistakes

```json
❌ "MockMode": "true"     // Should be boolean, not string
❌ "Enabled": True        // Should be lowercase
✅ "MockMode": true       // Correct boolean value
✅ "Enabled": false       // Correct boolean value
```

## Advanced Configuration Options

### Custom File Naming

If you need to change the default file names:

```json
"FileNames": {
  "MasterStudentData": "StudentData_MainCampus.csv"  // Custom name for specific use case
}
```

### Email Formatting Options

For different email preferences:

```json
"EmailNotification": {
  "BodyAsHtml": false,           // Plain text emails
  "SendOnSuccessOnly": false,    // Send emails even when there are minor issues
  "AdminNotifyOnError": false    // Disable immediate error notifications
}
```

### Logging Customization

For different logging needs:

```json
"Logging": {
  "LogLevel": "Debug"    // Maximum detail for troubleshooting
}
```

### Cleanup Customization

For different retention policies:

```json
"CleanupSettings": {
  "Enabled": false,              // Disable automatic cleanup
  "RunOnDayOfWeek": "Sunday",    // Run cleanup on Sundays
  "RetentionDaysLogs": 60,       // Keep logs for 2 months
  "RetentionDaysArchives": 365   // Keep archives for 1 year
}
```

## Backup and Version Control

### Before Making Changes

Always backup your working configuration:

```powershell
$BackupName = "config.json.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item "config.json" $BackupName
Write-Host "Configuration backed up to: $BackupName"
```

### Keep a Change Log

Document what you changed and why:

```
Change Log for config.json

2025-07-30: Initial setup for Tarneit Rise PS
- Set school number to 8881
- Configured email recipients: principal, admin, ict
- Enabled MockMode for testing

2025-08-01: Enabled production mode
- Changed MockMode to false
- Updated retention periods to 30/90 days
- Added additional email recipients
```

### Testing Changes

When making changes to a working system:

1. **Backup the current config.json**
2. **Make your changes**
3. **Test with MockMode enabled**
4. **Verify all functionality works**
5. **Disable MockMode only after successful testing**

## Getting Help

### Self-Service Validation

Use these commands to check your configuration:

```powershell
# Check JSON syntax
try { Get-Content "config.json" | ConvertFrom-Json; "✅ Valid JSON" } catch { "❌ Invalid JSON: $_" }

# Check required fields
$Config = Get-Content "config.json" | ConvertFrom-Json
if (-not $Config.SchoolSettings.SchoolNumber) { "❌ Missing SchoolNumber" }
if (-not $Config.SchoolSettings.SchoolName) { "❌ Missing SchoolName" }
if ($Config.EmailNotification.Enabled -and -not $Config.EmailNotification.From) { "❌ Missing From email" }
```

### When to Get Help

Contact technical support if:

- JSON validation consistently fails
- You're unsure about SMTP server settings
- You need help with network or security configurations
- The system doesn't work after following this guide

### Support Information

- **Primary Support:** Thomas VO (ST02392) - Thomas.Vo3@education.vic.gov.au
- **Include in support requests:**
  - Your school number and name
  - The specific configuration section you're having trouble with
  - Any error messages you're seeing
  - What you're trying to accomplish

This template editing guide should help you properly configure the DET Student Account Automation system for your school's specific needs. Remember to always test thoroughly before enabling production mode.
