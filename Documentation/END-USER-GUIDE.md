# DET Student Account Automation - End User Guide

## 📋 Table of Contents

- [Overview](#overview)
- [What This System Does](#what-this-system-does)
- [Quick Start for New Users](#quick-start-for-new-users)
- [Configuration Template Setup](#configuration-template-setup)
- [Running the System](#running-the-system)
- [Understanding Email Reports](#understanding-email-reports)
- [Common Tasks](#common-tasks)
- [Troubleshooting for End Users](#troubleshooting-for-end-users)
- [When to Contact Technical Support](#when-to-contact-technical-support)

## Overview

The DET Student Account Automation system automatically manages student accounts for your school. It connects to the eduSTAR Management Console daily, downloads the latest student information, and ensures all student accounts are properly configured with passwords and cloud services.

### Version Information

- **Current Version:** 1.6
- **Author:** Thomas VO (ST02392)
- **Contact:** Thomas.Vo3@education.vic.gov.au

## What This System Does

### Daily Automation

- ✅ Downloads the latest student list from eduSTAR
- ✅ Identifies new students who need accounts
- ✅ Generates secure passwords for students who don't have them
- ✅ Activates Google and Microsoft Intune services for new students
- ✅ Creates reports organized by year level and class
- ✅ Sends email summaries to designated staff
- ✅ Archives old data and cleans up files automatically

### Key Benefits

- **Time Saving:** Eliminates manual student account creation
- **Consistency:** Ensures all students have properly configured accounts
- **Reporting:** Provides clear visibility of student account status
- **Safety:** Includes testing mode to verify changes before going live

## Quick Start for New Users

### Step 1: Understand the File Structure

Your system is organized like this:

```
DET.StudentAccountAutomation/
├── Scripts/                    ← All the program files live here
│   ├── config.json            ← Main configuration file (YOU EDIT THIS)
│   ├── config.json.template   ← Template to help you set up config.json
│   └── Logs/                  ← Daily log files appear here
├── Archived-Logs/             ← Student data files stored here
│   ├── MasterStudentData.csv  ← Main student database
│   ├── DailyDownloads/        ← Daily downloads from eduSTAR
│   └── ArchivedCurrentData/   ← Backup copies of student data
└── StudentsByYearLevel/       ← Class lists organized by year
    ├── Year_00/               ← Prep class lists
    ├── Year_01/               ← Year 1 class lists
    └── ...                    ← And so on
```

### Step 2: Initial Setup

1. **Copy the template:** Rename `config.json.template` to `config.json`
2. **Edit your settings:** Open `config.json` and update it for your school
3. **Test first:** Always start with Mock Mode enabled
4. **Go live:** Once testing is successful, disable Mock Mode

### Step 3: First Run

1. Open PowerShell as Administrator
2. Navigate to the Scripts folder
3. Run: `.\Process-DailyStudentUpdates.ps1`
4. Check the email report and log files

## Configuration Template Setup

### Essential Settings You Must Change

#### 1. School Information

```json
"SchoolSettings": {
  "SchoolNumber": "8881",           ← Your 4-digit school number
  "SchoolName": "Sample Primary School"  ← Your school's full name
}
```

#### 2. Email Notifications

```json
"EmailNotification": {
  "Enabled": true,
  "To": "admin@yourschool.vic.edu.au;ict@yourschool.vic.edu.au",
  "From": "automation_noreply@yourschool.vic.edu.au",
  "SubjectPrefix": "Daily Student Update Report",
  "SmtpServer": "smtp.yourschool.vic.edu.au",
  "AdminEmailOnError": "admin@yourschool.vic.edu.au"
}
```

#### 3. Safety Settings (Important!)

```json
"ScriptBehavior": {
  "MockMode": true,              ← ALWAYS start with true for testing
  "TestEmail": "test@yourschool.vic.edu.au",
  "RemoveQuotesFromCsv": true
}
```

### Optional Settings You Can Adjust

#### Email Behavior

- `SendOnSuccessOnly`: If `true`, only sends emails when everything works perfectly
- `AdminNotifyOnError`: If `true`, sends immediate emails when critical errors occur
- `BodyAsHtml`: If `true`, sends formatted HTML emails (recommended)

#### Logging Level

- `"Information"`: Standard detail level (recommended)
- `"Verbose"`: Very detailed logging (for troubleshooting)
- `"Warning"`: Only important issues
- `"Error"`: Only critical problems

#### File Cleanup

```json
"CleanupSettings": {
  "Enabled": true,
  "RunOnDayOfWeek": "Monday",      ← When to clean up old files
  "RetentionDaysLogs": 7,          ← Keep log files for 7 days
  "RetentionDaysArchives": 7       ← Keep archived data for 7 days
}
```

## Running the System

### Manual Testing (Recommended First)

1. **Open PowerShell as Administrator**
2. **Navigate to Scripts folder:**
   ```powershell
   cd "G:\Shared drives\...\DET.StudentAccountAutomation\Scripts"
   ```
3. **Run the script:**
   ```powershell
   .\Process-DailyStudentUpdates.ps1
   ```
4. **Watch the output** and check for any errors
5. **Review the email report** that gets sent
6. **Check the log file** in the Logs folder

### Setting Up Daily Automation

Once testing is successful, set up Windows Task Scheduler:

1. **Open Task Scheduler**
2. **Create Basic Task**

   - **Name:** "Daily Student Account Updates"
   - **Trigger:** Daily at 3:00 AM (or preferred time)
   - **Action:** Start a program
   - **Program:** `powershell.exe`
   - **Arguments:** `-ExecutionPolicy Bypass -File "G:\...\Scripts\Process-DailyStudentUpdates.ps1"`
   - **Start in:** `G:\...\Scripts\`

3. **Configure Security**
   - Run whether user is logged on or not
   - Run with highest privileges
   - Use a service account with appropriate permissions

## Understanding Email Reports

### Success Email Example

```
✅ SUCCESS - Daily Student Update Report - Your School - 2025-07-30

📊 SUMMARY STATISTICS:
• New Students: 3
• Departed Students: 1
• Existing Students: 245
• Accounts Created: 3

📋 PROCESSING DETAILS:
[Detailed log of what happened]

🎉 All tasks completed successfully!
```

### What the Numbers Mean

- **New Students:** Students found in eduSTAR but not in your local database
- **Departed Students:** Students in your local database but no longer in eduSTAR
- **Existing Students:** Students who remain enrolled
- **Accounts Created:** New accounts that were set up with passwords and services

### Warning Signs in Reports

- ❌ **FAILED** in the subject line means something went wrong
- High numbers of departed students might indicate a data issue
- Zero new students for extended periods might indicate connection problems
- Error messages in the processing details need attention

## Common Tasks

### Checking if the System is Working

1. **Look for today's log file** in `Scripts/Logs/`
2. **Check your email** for the daily report
3. **Verify new PDF files** are being created in `StudentsByYearLevel/`
4. **Confirm timestamps** on files are recent

### Adding New Email Recipients

1. **Open `config.json`**
2. **Find the `"To"` line under EmailNotification**
3. **Add emails separated by semicolons:**
   ```json
   "To": "admin@school.vic.edu.au;ict@school.vic.edu.au;principal@school.vic.edu.au"
   ```
4. **Save the file**

### Changing When Cleanup Runs

1. **Open `config.json`**
2. **Find `"RunOnDayOfWeek"` under CleanupSettings**
3. **Change to desired day:**
   ```json
   "RunOnDayOfWeek": "Friday"
   ```
4. **Save the file**

### Temporarily Disabling the System

1. **Open `config.json`**
2. **Set MockMode to true:**
   ```json
   "MockMode": true
   ```
3. **This will simulate operations without making real changes**

## Troubleshooting for End Users

### No Email Reports Received

**Check These:**

- ✅ Is `"Enabled": true` in EmailNotification?
- ✅ Are email addresses spelled correctly?
- ✅ Is the SMTP server address correct?
- ✅ Check your spam/junk folder
- ✅ Look for error messages in the log file

### Script Not Running Automatically

**Check These:**

- ✅ Is the scheduled task enabled in Task Scheduler?
- ✅ Does the user account running the task have permission?
- ✅ Are the file paths in the scheduled task correct?
- ✅ Check Windows Event Viewer for task scheduler errors

### Missing Student Data Files

**Check These:**

- ✅ Does `MasterStudentData.csv` exist in the Archived-Logs folder?
- ✅ Can the script connect to eduSTAR (check log for authentication errors)?
- ✅ Are the file permissions correct for the service account?

### PDF Files Not Being Created

**Check These:**

- ✅ Is the ImportExcel PowerShell module installed?
- ✅ Are there any errors in the log about Excel/PDF generation?
- ✅ Is there sufficient disk space?

### Old Files Not Being Cleaned Up

**Check These:**

- ✅ Is `"Enabled": true` in CleanupSettings?
- ✅ Is today the configured cleanup day?
- ✅ Are the retention day settings reasonable?

## When to Contact Technical Support

### Contact Technical Support If:

- ❌ You receive multiple failure emails in a row
- ❌ The log file shows authentication errors with eduSTAR
- ❌ Students report that their accounts or passwords aren't working
- ❌ You need to change the school number or major configuration settings
- ❌ The system hasn't run for several days without explanation
- ❌ You're getting errors about missing PowerShell modules

### Before Contacting Support:

1. ✅ Check the most recent log file in `Scripts/Logs/`
2. ✅ Note any error messages from the email reports
3. ✅ Verify the script hasn't been moved or renamed
4. ✅ Check if Windows Updates or antivirus might have interfered
5. ✅ Try running the script manually once to see if it works

### What to Include in Your Support Request:

- 📋 The exact error message you're seeing
- 📋 The most recent log file (from Scripts/Logs/)
- 📋 Your school number and contact information
- 📋 Whether this is a new problem or has been ongoing
- 📋 Any recent changes to your computer or network

### Emergency Contacts:

- **Primary:** Thomas VO (ST02392) - Thomas.Vo3@education.vic.gov.au
- **Backup:** Your local IT support team

---

## Important Reminders

### Safety First

- ⚠️ **Always test with MockMode first** before enabling live operations
- ⚠️ **Keep backups** of your config.json file
- ⚠️ **Don't modify files in the Scripts folder** unless instructed by technical support

### Regular Maintenance

- 📅 **Weekly:** Check that email reports are arriving
- 📅 **Monthly:** Review log files for any recurring warnings
- 📅 **Quarterly:** Verify student numbers match your expectations
- 📅 **Annually:** Review and update email recipient lists

### Data Security

- 🔒 **Protect credentials** used for eduSTAR access
- 🔒 **Limit access** to the automation files to authorized personnel only
- 🔒 **Monitor email reports** for unusual activity patterns

**Remember:** This system is designed to be reliable and low-maintenance. Most issues can be resolved by checking the configuration and log files. When in doubt, enable MockMode and contact technical support.
