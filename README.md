# Automated Student Data Processing Scripts

### Version: 1.4

Author: Thomas VO (ST02392) - Thomas.Vo3@education.vic.gov.au

## Overview

This set of PowerShell scripts automates the daily processing of student data for a school. It fetches the latest student list from eduSTAR Management Console (MC), compares it with a local master list, processes new and existing students (including password generation for those missing one), updates account details (passwords, cloud services - with a mock mode for testing), archives data, splits the student list by year level, and performs cleanup of old log/archive files. The process is highly configurable via a `config.json` file and includes comprehensive logging and email notifications.

## Features

- **Configuration Driven:** All major settings (school details, file paths/names, email settings, logging levels, cleanup rules) are managed in `config.json`.
- **Student Processing:**
  - Identifies new students from the daily download.
  - Generates a simple, memorable random password (e.g., `Word.1234`) for new students AND existing students in the master list who have a blank password.
  - (Optional - Live Mode) Sets the student's password in eduPass.
  - (Optional - Live Mode) Activates Google and Intune cloud services in eduPass for new students.
- **Departed Student Handling:** Identifies departed students (present in the master list but not in the daily download) and excludes them from the updated master list.
- **Data Management:**
  - Maintains a `MasterStudentData.csv` file (or as configured).
  - Archives a copy of the `MasterStudentData.csv` daily with a timestamp.
  - Splits the updated master list into separate CSV files per year level (e.g., `Year_07.csv`).
- **Logging:** Comprehensive logging of actions, warnings, and errors to a daily log file (e.g., `DailyStudentProcessLog_YYYYMMDD.log`).
- **Email Notifications:**
  - Sends a summary email upon completion of tasks (configurable to send on success only or always).
  - Can be configured to notify an administrator immediately if critical errors occur.
  - Supports sending emails to a test address when in Mock Mode.
- **Mock Mode:** Allows running the script without making actual changes to eduPass (password resets, cloud service activation) or performing file deletions during cleanup. Essential for testing.
- **Automated File Cleanup:**
  - Configurable cleanup of old log files and archived data files.
  - Specify retention days and the day of the week for cleanup to run.
- **Modular Utilities:** Uses `StudentDataUtils.ps1` for eduSTAR MC interactions and other helper functions.
- **User-Friendly:** Designed for technicians with varying levels of programming knowledge to configure and run.

## File Structure

The script expects and creates the following directory structure, relative to where the `Process-DailyStudentUpdates.ps1` script is located (Project Root):

> [!IMPORTANT]
> Put your MasterStudentData **INSIDE** your /Data to make it work later on it will get updated to the latest when the script runs properly

```
StudentAccountAutomation/ (Project Root)
├── Scripts/ # Contains all executable scripts and configurations
│ ├── Process-DailyStudentUpdates.ps1
│ ├── StudentDataUtils.ps1 # Utility functions for eduSTAR interaction
│ ├── config.json # Main configuration file
│ ├── config.json.template # Template for creating config.json
│ └── Logs/
│ └── DailyStudentProcessLog*YYYYMMDD.log # Daily log files
│
└── Data/ # Contains all student data files and subdirectories
├── MasterStudentData.csv # Main student data file (or as named in config.json)
│
├── DailyDownloads/
│ └── DownloadedStudentList_YYYYMMDD.csv # Raw data downloaded from eduSTAR MC
│
├── ArchivedCurrentData/
│ └── ArchivedMasterStudentData*[MasterFileName]\_DDMMYYYY.csv # Daily archive of the master data
│
├── StudentsByYearLevel/
│ ├── Year_Prep.csv
│ ├── Year_01.csv
│ └── ... # CSV files for each year level
```

## Prerequisites

- **PowerShell:** Version 5.1 or higher.
- **Credentials for eduSTAR MC:** The `StudentDataUtils.ps1` script uses `C:\Credentials\eduSTARMCAdministration\Creds.xml` to store encrypted credentials for eduSTAR MC.
  - On the first run (or if `Creds.xml` is missing), the script will prompt you to enter your eduSTAR MC username and password, which will then be saved securely in this file for future use.
  - Ensure the `C:\Credentials\eduSTARMCAdministration` path is accessible and writable by the user account running the script.
- **Network Access:** The machine running the script must have network access to:
  - `https://apps.edustar.vic.edu.au` (eduSTAR MC API)
  - `http://broadband.doe.wan/api/ip/whoami` (for optional school auto-detection, if configured in `StudentDataUtils.ps1` - though current main script relies on `config.json` for school number).
  - The SMTP server specified in `config.json` for email notifications.

## Setup and Configuration

1.  **Copy Files:**
    - Place `Process-DailyStudentUpdates.ps1`, `StudentDataUtils.ps1`, and `config.json.template` into your chosen `Scripts` directory (e.g., `X:\StudentAccountAutomation\Scripts\`).
2.  **Create `config.json`:**
    - Rename `config.json.template` to `config.json`.
    - Open `config.json` in a text editor (like VS Code or Notepad++) and carefully customize the settings. **This is the most crucial step.**
3.  **Edit `config.json` Settings:**

    Refer to the comments within `config.json.template` or the descriptions below for guidance on each setting:

    - **`SchoolSettings`**:
      - `SchoolNumber`: (String) Your 4-digit school number (e.g., `"8881"`). **This is essential.**
      - `SchoolName`: (String) Your school's full name for reporting (e.g., `"Sample Secondary College"`).
    - **`FileNames`**:
      - `MasterStudentData`: (String) The filename for your primary local student data CSV (e.g., `"MasterStudentData.csv"`). This file will be created in the `Data/` directory if it doesn't exist on the first run.
    - **`EmailNotification`**:
      - `Enabled`: (Boolean) `true` to enable email notifications, `false` to disable.
      - `To`: (String) Semicolon-separated list of email addresses to receive the daily summary report (e.g., `"tech@school.vic.edu.au;principal@school.vic.edu.au"`).
      - `From`: (String) The "From" address for emails sent by the script (e.g., `"studentautomation@school.vic.edu.au"`).
      - `SubjectPrefix`: (String) Prefix for the email subject line (e.g., `"Student Data Sync Report"`).
      - `SmtpServer`: (String) Your SMTP server address (e.g., `"smtp.education.vic.gov.au"`).
      - `Port`: (Number) SMTP port (usually `25`. For SSL/TLS, often `587` or `465` - script may need modification for SSL/TLS).
      - `SendOnSuccessOnly`: (Boolean) `true` to only send the main report if the script completes without errors. If `false`, it will send a report indicating success or failure.
      - `AdminNotifyOnError`: (Boolean) `true` to send an immediate notification to `AdminEmailOnError` if a critical script error occurs.
      - `AdminEmailOnError`: (String) Semicolon-separated list of email addresses for critical error notifications.
      - `BodyAsHtml`: (Boolean) `true` if the email body should be formatted as HTML, `false` for plain text.
    - **`Logging`**:
      - `LogLevel`: (String) Controls the verbosity of console output. Options: `"Verbose"`, `"Information"`, `"Warning"`, `"Error"`, `"Debug"`. `"Information"` is a good default. The log file in `Scripts/Logs/` always receives all levels of messages.
    - **`ScriptBehavior`**:
      - `MockMode`: (Boolean) `true` to simulate eduPass operations (password sets, cloud services) and file cleanup without making live changes. **Crucially important to set to `true` for initial testing.** Set to `false` for production runs.
      - `TestEmail`: (String) Semicolon-separated list of email addresses to which ALL emails will be sent when `MockMode` is `true`. This overrides `To` and `AdminEmailOnError` during mock runs.
      - `RemoveQuotesFromCsv`: (Boolean) `true` to remove all double quotes from generated CSV files. `false` to keep them (standard CSV format).
    - **`CleanupSettings`**:
      - `Enabled`: (Boolean) `true` to enable automated cleanup of old log and archive files, `false` to disable.
      - `RunOnDayOfWeek`: (String) The specific day of the week to perform cleanup. Valid values: `"Monday"`, `"Tuesday"`, `"Wednesday"`, `"Thursday"`, `"Friday"`, `"Saturday"`, `"Sunday"`.
      - `RetentionDaysLogs`: (Number) How many days to keep log files in `Scripts/Logs/` before they are deleted by the cleanup process.
      - `RetentionDaysArchives`: (Number) How many days to keep archived data files in `Data/ArchivedCurrentData/` before deletion.

4.  **MasterStudentData.csv (Initial Run):**
    - On the very first run, if the master student data file (e.g., `Data/MasterStudentData.csv`) does not exist, the script will assume it's an initial setup. The first downloaded student list will be used to create this master file.
    - If the file exists, the script expects it to be a CSV with at least the following headers: `Username,FirstName,LastName,YearLevel,Class,Email,Password`.
    - The `Password` column can be blank for students; the script will generate passwords for those with blank entries.

## Running the Script

1.  **Manual Execution:**

    - Open PowerShell.
    - Navigate to the `Scripts` directory where you placed the files: `cd C:\StudentAccountAutomation\Scripts`
    - Run the main script: `.\Process-DailyStudentUpdates.ps1`
    - Check the console output and the detailed log file in the `Scripts/Logs/` directory.

2.  **Scheduled Task (Recommended for Daily Automation):**
    - Open Task Scheduler on your server/computer.
    - Create a new Task (not Basic Task, for more options).
    - **General Tab:**
      - Name: `Daily Student Data Processing`
      - Description: `Runs the PowerShell script to process daily student data updates.`
      - Select "Run whether user is logged on or not".
      - Select "Run with highest privileges" (may be needed for `C:\Credentials` access or other operations).
      - Configure the user account that will run the task (ensure it has necessary permissions).
    - **Triggers Tab:**
      - New... -> Daily, at a specified time (e.g., 3:00 AM).
    - **Actions Tab:**
      - New... -> Action: `Start a program`.
      - Program/script: `powershell.exe`
      - Add arguments (optional): `-ExecutionPolicy Bypass -File "C:\StudentAccountAutomation\Scripts\Process-DailyStudentUpdates.ps1"` (Update path accordingly).
      - Start in (optional): `C:\StudentAccountAutomation\Scripts\` (This helps the script resolve relative paths correctly).
    - **Conditions/Settings Tabs:** Configure power options, stop if running too long, etc., as per your environment's needs.
    - **Permissions:** Ensure the account running the task has:
      - Read/write/modify permissions to the `Scripts` directory and its subdirectories (`Logs`).
      - Read/write/modify permissions to the `Data` directory and its subdirectories.
      - Permissions to access `C:\Credentials` for `Creds.xml`.
      - Network access to eduSTAR MC and the SMTP server.

## Troubleshooting

- **"Configuration file 'config.json' not found"**: Ensure `config.json` is in the `Scripts` directory alongside `Process-DailyStudentUpdates.ps1`.
- **"Failed to import module [StudentDataUtils.ps1]"**: Ensure `StudentDataUtils.ps1` is in the `Scripts` directory.
- **Credential Prompts/Failures:**
  - If repeatedly prompted for credentials, check permissions on `C:\Credentials\eduSTARMCAdministration` and `Creds.xml`. The user running the script needs read/write access.
  - Ensure the saved credentials are correct. Delete `Creds.xml` to force a re-prompt if unsure.
- **Email Failures:**
  - Verify SMTP server settings (`SmtpServer`, `Port`, `From` address) in `config.json`.
  - Ensure the server is reachable and allows relay from the machine running the script. Check firewalls.
  - Check `TestEmail` in `config.json` if `MockMode` is true.
- **API Errors (eduSTAR MC):**
  - Log files in `Scripts/Logs/` will contain error messages from API interactions.
  - These could be due to network issues, eduSTAR MC service unavailability, incorrect credentials, or API changes.
- **"Access Denied" to `Data` or `Logs` directories:** Ensure the user account running the script (especially for scheduled tasks) has full control permissions to the `Scripts` and `Data` directories and their subdirectories.
- **File Cleanup Not Working:**
  - Verify `CleanupSettings.Enabled` is `true` in `config.json`.
  - Check if the script is run on the day specified in `RunOnDayOfWeek`.
  - Ensure `RetentionDaysLogs` and `RetentionDaysArchives` are set appropriately.
  - Review logs for any specific error messages during the cleanup step.

## Log File Analysis

The script generates a daily log file in `Scripts/Logs/` (e.g., `DailyStudentProcessLog_20250528.log`). This file is crucial for monitoring and troubleshooting. It contains:

- Script version and start/end times.
- Timestamps for each major action and log entry.
- Log Levels: `INFO`, `VERBOSE`, `WARN`, `ERROR`, `DEBUG`.
- Details of students processed (new, existing with password changes).
- Summary of files downloaded, created, or archived.
- Actions taken during file cleanup (if enabled and run).
- Errors encountered with stack traces if available.
- A copy of the processing summary that is emailed.

Review this log file regularly, especially if issues are suspected or after making configuration changes.

## Mock Mode vs. Live Mode

- **Mock Mode (`"MockMode": true` in `config.json`):**
  - The script will perform all data comparisons, generate passwords, and update local CSV files.
  - File cleanup actions will be logged as "simulated" but no files will be deleted.
  - **It will NOT attempt to:**
    - Set passwords in eduPass.
    - Change cloud service status (Google, Intune) in eduPass.
  - All emails will be sent to the `TestEmail` address(es) specified in `config.json`.
  - **Use this mode extensively for testing** the script logic, data handling, file outputs, and email content without affecting live student accounts or data.
- **Live Mode (`"MockMode": false` in `config.json`):**
  - The script will perform all actions, including making changes to student accounts in eduPass (passwords, cloud services) and deleting files during cleanup.
  - Emails will be sent to the recipients defined in `To` and `AdminEmailOnError`.
  - **Use with extreme caution and only after thorough testing in Mock Mode.**

## `StudentDataUtils.ps1` Module

This file contains helper functions used by `Process-DailyStudentUpdates.ps1`, primarily for interacting with the eduSTAR Management Console. Key functions include:

- `Set-eMCCredentials`: Manages storing and retrieving eduSTAR MC credentials.
- `Connect-eduSTARMC` / `Disconnect-eduSTARMC`: Handles session management.
- `Get-StudentAccountFullList`: Fetches the complete student list from eduSTAR MC.
- `Set-eduPassStudentAccountPassword`: Sets a student's password in eduPass.
- `Set-eduPassCloudServiceStatus`: Enables/disables cloud services (Google, Intune) for students.
- `Compare-StudentLists`: Compares the downloaded list with the master list to find new, departed, and existing students.
- `Get-RandomPasswordSimple`: Generates simple, memorable passwords.

Modifications to this file should be done carefully as they directly impact interactions with eduSTAR MC.

## Disclaimer

This script interacts with live student data and systems. Always test thoroughly in Mock Mode and with non-production data if possible before running in Live Mode against production systems. The authors and contributors are not responsible for any data loss or issues caused by the use of this script. Ensure you have appropriate backups and understand the script's operations before use.
