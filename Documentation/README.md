# DET Student Account Automation - Documentation Index

## Overview

This directory contains comprehensive documentation for the DET Student Account Automation system. The documentation is organized by user type and use case to help you find the information you need quickly.

## Documentation Structure

### 📚 For End Users and Administrators

#### [END-USER-GUIDE.md](./END-USER-GUIDE.md)

**Who should read this:** School administrators, ICT coordinators, and end users who need to operate the system day-to-day.

**What's included:**

- Quick start guide for new users
- Configuration template setup instructions
- Understanding email reports and what they mean
- Common daily tasks and maintenance
- Basic troubleshooting for non-technical users
- When to contact technical support

**Key sections:**

- ✅ What the system does automatically
- ✅ How to read and respond to email reports
- ✅ Simple configuration changes
- ✅ Warning signs to watch for

---

### 🔧 For Technical Users and Developers

#### [TECHNICAL-DOCUMENTATION.md](./TECHNICAL-DOCUMENTATION.md)

**Who should read this:** System administrators, developers, and technical staff who need to understand the system architecture and implementation details.

**What's included:**

- Complete system architecture overview
- Detailed module documentation
- API integration specifications
- Security implementation details
- Data flow and processing logic
- Development guidelines and coding standards
- Advanced configuration options

**Key sections:**

- 🔧 PowerShell module documentation
- 🔧 eduSTAR API integration details
- 🔧 Error handling and logging framework
- 🔧 Performance optimization guidelines

---

### 🆘 For Problem Resolution

#### [TROUBLESHOOTING-GUIDE.md](./TROUBLESHOOTING-GUIDE.md)

**Who should read this:** Anyone experiencing issues with the system, from basic users to technical administrators.

**What's included:**

- Quick diagnostic checklist (2-minute health check)
- Common issues and step-by-step solutions
- Error code reference and meanings
- Log file analysis techniques
- Network and connectivity troubleshooting
- Recovery procedures for various scenarios
- Escalation guidelines and contact information

**Key sections:**

- 🆘 Quick diagnostic checklist
- 🆘 Common error solutions
- 🆘 Emergency recovery procedures
- 🆘 When and how to escalate issues

---

### ⚙️ For Initial Setup and Configuration

#### [CONFIGURATION-GUIDE.md](./CONFIGURATION-GUIDE.md)

**Who should read this:** Anyone setting up the system for the first time or making configuration changes.

**What's included:**

- Step-by-step installation instructions
- Complete configuration reference with examples
- Configuration validation tools
- Security considerations
- Common configuration mistakes and how to avoid them
- Post-installation checklist

**Key sections:**

- ⚙️ Prerequisites and system requirements
- ⚙️ Complete configuration walkthrough
- ⚙️ Testing and validation procedures
- ⚙️ Security best practices

---

## Quick Start - Which Document Do I Need?

### I'm setting up the system for the first time

→ Start with [CONFIGURATION-GUIDE.md](./CONFIGURATION-GUIDE.md)

### I'm a school administrator who needs to understand daily operations

→ Read [END-USER-GUIDE.md](./END-USER-GUIDE.md)

### Something is broken and I need to fix it

→ Go to [TROUBLESHOOTING-GUIDE.md](./TROUBLESHOOTING-GUIDE.md)

### I'm a developer or need to understand how it works internally

→ Study [TECHNICAL-DOCUMENTATION.md](./TECHNICAL-DOCUMENTATION.md)

### I need to modify the configuration

→ Use [CONFIGURATION-GUIDE.md](./CONFIGURATION-GUIDE.md) for reference

## Document Relationships

```
CONFIGURATION-GUIDE.md ─┐
                        ├─→ END-USER-GUIDE.md ─→ Daily Operations
                        │
TECHNICAL-DOCUMENTATION.md ─┤
                            │
                        └─→ TROUBLESHOOTING-GUIDE.md ─→ Problem Resolution
```

## System Overview

The DET Student Account Automation system is a PowerShell-based solution that:

1. **Connects** to eduSTAR Management Console daily
2. **Downloads** the latest student enrollment data
3. **Compares** with existing student records
4. **Processes** new students (creates accounts, sets passwords, enables services)
5. **Updates** existing student information as needed
6. **Generates** reports organized by year level and class
7. **Sends** email summaries to designated staff
8. **Archives** data and performs maintenance tasks

### Key Features

- ✅ **Fully Automated** - Runs daily without manual intervention
- ✅ **Safe Testing** - MockMode allows testing without making changes
- ✅ **Comprehensive Logging** - Detailed logs for monitoring and troubleshooting
- ✅ **Email Notifications** - Automatic summary reports and error alerts
- ✅ **Data Archival** - Automatic backup and cleanup of historical data
- ✅ **Flexible Configuration** - JSON-based configuration for easy customization

### File Structure Reference

```
DET.StudentAccountAutomation/
├── Scripts/                           # Application files
│   ├── Process-DailyStudentUpdates.ps1   # Main script
│   ├── *.psm1                            # PowerShell modules
│   ├── config.json                       # Configuration file
│   └── Logs/                             # Daily log files
├── Archived-Logs/                    # Data storage
│   ├── MasterStudentData.csv             # Primary student database
│   ├── DailyDownloads/                   # API download files
│   └── ArchivedCurrentData/              # Historical backups
├── StudentsByYearLevel/               # Generated reports
│   └── Year_XX/                          # Class lists by year
└── Documentation/                     # This documentation
    ├── END-USER-GUIDE.md
    ├── TECHNICAL-DOCUMENTATION.md
    ├── TROUBLESHOOTING-GUIDE.md
    └── CONFIGURATION-GUIDE.md
```

## Version Information

- **Current Version:** 1.6
- **Author:** Thomas VO (ST02392)
- **Contact:** Thomas.Vo3@education.vic.gov.au
- **Last Updated:** July 30, 2025

## Support and Contact Information

### Primary Support

- **Developer:** Thomas VO (ST02392)
- **Email:** Thomas.Vo3@education.vic.gov.au
- **Role:** System developer and primary technical support

### Documentation Feedback

If you find errors in this documentation or have suggestions for improvement, please contact the primary support team with:

- The specific document and section
- The nature of the issue or suggestion
- Your role and how you use the system

### Emergency Support

For critical issues affecting daily student account operations:

1. Check the [TROUBLESHOOTING-GUIDE.md](./TROUBLESHOOTING-GUIDE.md) first
2. If issue persists, contact primary support immediately
3. Include relevant log files and error messages
4. Specify the urgency level and impact on operations

## Documentation Standards

This documentation follows these principles:

- **User-Centric:** Organized by who needs the information, not by technical structure
- **Task-Oriented:** Focuses on what users need to accomplish
- **Progressive Disclosure:** Basic information first, advanced details as needed
- **Searchable:** Clear headings and keywords for easy navigation
- **Actionable:** Includes specific steps and examples, not just theory

## Regular Maintenance

### Documentation Updates

This documentation should be reviewed and updated:

- **Immediately:** When system functionality changes
- **Quarterly:** To verify accuracy and completeness
- **Annually:** For comprehensive review and improvement

### User Feedback

Users are encouraged to provide feedback on documentation usefulness:

- What information was hard to find?
- What procedures need more detail?
- What examples would be helpful?
- What sections are unclear or confusing?

---

## Quick Reference Cards

### Daily Health Check

```powershell
# Quick system health check commands
$LogFile = "Scripts\Logs\DailyStudentProcessLog_$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $LogFile) { "✅ Script ran today" } else { "❌ No log file found" }
Get-Content $LogFile | Where-Object { $_ -like "*[Error]*" } | Measure-Object | ForEach-Object { "Errors: $($_.Count)" }
```

### Emergency Contacts

- **Technical Issues:** Thomas VO - Thomas.Vo3@education.vic.gov.au
- **eduSTAR Platform:** DET ICT Service Desk
- **Network/Infrastructure:** Local IT support team

### Common File Locations

- **Configuration:** `Scripts\config.json`
- **Today's Log:** `Scripts\Logs\DailyStudentProcessLog_YYYYMMDD.log`
- **Student Data:** `Archived-Logs\MasterStudentData.csv`
- **Class Reports:** `StudentsByYearLevel\Year_XX\`

This documentation index should serve as your starting point for any information needs related to the DET Student Account Automation system. Each document is designed to stand alone while also working together as a comprehensive reference suite.
