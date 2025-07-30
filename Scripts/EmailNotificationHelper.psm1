# EmailNotificationHelper.psm1
# Purpose: Email notification functions for student account automation
# Author: Thomas VO (ST02392)
# Date: 30-07-2025

Function Send-NotificationEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ProcessSummary", "AdminError")]
        [string]$NotificationType,

        [Parameter(Mandatory=$true)]
        [bool]$IsScriptSuccessful,

        [Parameter(Mandatory=$false)] 
        [string]$CustomMessage = "", # For specific error messages or additional content for summary

        [Parameter(Mandatory=$false)]
        [string]$CustomDetails = ""  # For error stack traces or detailed information
    )

    if (-not $Global:Config.EmailNotification.Enabled) {
        Write-Log -Message "Email notification disabled in config. Skipping email." -Level Information
        return
    }

    # Determine if we should send this email based on configuration and content
    $shouldSendEmail = $false
    $emailRecipients = @()
    $emailSubject = ""
    $emailBody = ""
    $useHtml = $Global:Config.EmailNotification.UseHtmlFormat -eq $true

    # Email logic: Only send what's necessary
    if ($Global:Config.ScriptBehavior.MockMode -and -not [string]::IsNullOrWhiteSpace($Global:Config.ScriptBehavior.TestEmail)) {
        # In mock mode, always send to test email for verification
        $emailRecipients = $Global:Config.ScriptBehavior.TestEmail.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
        $shouldSendEmail = $true
        Write-Log -Message "MOCK MODE: Email will be sent to TestEmail: $($Global:Config.ScriptBehavior.TestEmail)" -Level Information
    } else {
        # Production mode email logic
        if ($NotificationType -eq "AdminError" -or -not $IsScriptSuccessful) {
            # Always send errors to admin
            if (-not [string]::IsNullOrWhiteSpace($Global:Config.EmailNotification.AdminOnly)) {
                $emailRecipients = $Global:Config.EmailNotification.AdminOnly.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
                $shouldSendEmail = $true
            }
        } elseif ($NotificationType -eq "ProcessSummary" -and $IsScriptSuccessful) {
            # For successful runs, check if there are any significant changes before sending
            $summaryText = $Global:ProcessingSummary.ToString()
            $hasSignificantChanges = $false
            
            # Check for significant changes that warrant an email
            if ($summaryText -match "New Students: ([1-9]\d*)" -or  # Any new students
                $summaryText -match "Departed Students: ([1-9]\d*)" -or  # Any departed students  
                $summaryText -match "newly generated passwords" -or  # Password updates
                $summaryText -match "Student Detail Changes" -or  # Class/year changes
                $summaryText -match "ERROR" -or  # Any errors
                $summaryText -match "WARNING.*Skipped") {  # Any warnings about skipped students
                $hasSignificantChanges = $true
            }
            
            # Send to team members only if there are significant changes OR if configured to always send on success
            if ($hasSignificantChanges -or -not $Global:Config.EmailNotification.SendOnSuccessOnly) {
                if (-not [string]::IsNullOrWhiteSpace($Global:Config.EmailNotification.TeamMembers)) {
                    $emailRecipients = $Global:Config.EmailNotification.TeamMembers.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
                    $shouldSendEmail = $true
                    
                    if ($hasSignificantChanges) {
                        Write-Log -Message "Significant changes detected, sending summary email to team members." -Level Information
                    } else {
                        Write-Log -Message "No significant changes but SendOnSuccessOnly is false, sending summary email to team members." -Level Information
                    }
                } 
            } else {
                Write-Log -Message "No significant changes detected and SendOnSuccessOnly is true. Skipping routine success email." -Level Information
                return
            }
        }
    }

    if (-not $shouldSendEmail -or $emailRecipients.Count -eq 0) {
        Write-Log -Message "No email will be sent for $NotificationType (no recipients or not warranted)." -Level Information
        return
    }

    # Create nicely formatted emails
    if ($NotificationType -eq "AdminError") {
        $emailSubject = "🚨 CRITICAL ERROR - Student Account Automation - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        $emailBody = Get-AdminErrorEmailBody -CustomMessage $CustomMessage -CustomDetails $CustomDetails -UseHtml $useHtml
    } elseif ($NotificationType -eq "ProcessSummary") {
        if ($IsScriptSuccessful) {
            $emailSubject = "✅ Daily Update Complete - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
            Write-Log -Message "Script completed successfully. Preparing success email for team members." -Level Information
        } else {
            $emailSubject = "❌ Daily Update Failed - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
            Write-Log -Message "Script failed. Preparing failure email for admin only." -Level Information
        }
        $emailBody = Get-ProcessSummaryEmailBody -IsSuccessful $IsScriptSuccessful -CustomMessage $CustomMessage -UseHtml $useHtml
    }

    $emailParams = @{
        To         = $emailRecipients
        From       = $Global:Config.EmailNotification.From
        Subject    = $emailSubject
        Body       = $emailBody
        SmtpServer = $Global:Config.EmailNotification.SmtpServer
        Port       = $Global:Config.EmailNotification.Port
        Encoding   = [System.Text.Encoding]::UTF8
    }
    
    if ($useHtml) { 
        $emailParams.BodyAsHtml = $true 
    }

    try {
        $recipientType = if ($NotificationType -eq "AdminError" -or -not $IsScriptSuccessful) { "Admin" } else { "Team Members" }
        Write-Log -Message "Attempting to send $NotificationType email to ${recipientType}: $($emailRecipients -join '; ')" -Level Information
        Send-MailMessage @emailParams
        Write-Log -Message "$NotificationType email sent successfully to ${recipientType}." -Level Information
        if ($NotificationType -eq "ProcessSummary") {
            $Global:ProcessingSummary.AppendLine("Email Notification Sent To (${recipientType}): $($emailRecipients -join '; ')") | Out-Null
        }
    } catch {
        Write-Log -Message "Failed to send $NotificationType email: $($_.Exception.Message)" -Level Error
        if ($NotificationType -eq "ProcessSummary") {
            $Global:ProcessingSummary.AppendLine("EMAIL SEND FAILED ($($NotificationType)): $($_.Exception.Message)") | Out-Null
        }
    }
}

Function Get-AdminErrorEmailBody {
    [CmdletBinding()]
    param(
        [string]$CustomMessage,
        [string]$CustomDetails,
        [bool]$UseHtml
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $school = $Global:Config.SchoolSettings.SchoolName
    $schoolNumber = $Global:Config.SchoolSettings.SchoolNumber
    
    if ($UseHtml) {
        return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #dc3545; color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .content { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .error-box { background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; padding: 10px; border-radius: 3px; margin: 10px 0; }
        .details-box { background-color: #fff3cd; border: 1px solid #ffeaa7; color: #856404; padding: 10px; border-radius: 3px; margin: 10px 0; }
        .footer { color: #6c757d; font-size: 12px; margin-top: 20px; }
        h2 { color: #dc3545; }
        h3 { color: #495057; }
        .urgent { color: #dc3545; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚨 CRITICAL ERROR - Student Account Automation</h1>
        <p><strong>School:</strong> $school (Number: $schoolNumber)</p>
        <p><strong>Timestamp:</strong> $timestamp</p>
    </div>
    
    <div class="content">
        <h2>Error Summary</h2>
        <p class="urgent">A critical error has occurred in the Daily Student Account Automation script that requires immediate attention.</p>
        
        <div class="error-box">
            <h3>🔴 Error Message:</h3>
            <p>$CustomMessage</p>
        </div>
        
        $(if (-not [string]::IsNullOrWhiteSpace($CustomDetails)) {
            "<div class='details-box'>
                <h3>📋 Technical Details:</h3>
                <pre>$CustomDetails</pre>
            </div>"
        })
        
        <h3>📝 Next Steps:</h3>
        <ul>
            <li>Check the log file for detailed information: <code>$LogFilePath</code></li>
            <li>Verify eduSTAR and network connectivity</li>
            <li>Check for any recent system changes</li>
            <li>Restart the script manually after resolving the issue</li>
        </ul>
    </div>
    
    <div class="footer">
        <p>This email was automatically generated by the Student Account Automation system.</p>
        <p>System: $($env:COMPUTERNAME) | Script Version: $($Global:ScriptVersion)</p>
    </div>
</body>
</html>
"@
    } else {
        return @"
🚨 CRITICAL ERROR - Student Account Automation
==========================================

School: $school (Number: $schoolNumber)
Timestamp: $timestamp

ERROR SUMMARY:
A critical error has occurred in the Daily Student Account Automation script that requires immediate attention.

🔴 Error Message:
$CustomMessage

$(if (-not [string]::IsNullOrWhiteSpace($CustomDetails)) {
"📋 Technical Details:
$CustomDetails
"})

📝 Next Steps:
• Check the log file for detailed information: $LogFilePath
• Verify eduSTAR and network connectivity
• Check for any recent system changes
• Restart the script manually after resolving the issue

This email was automatically generated by the Student Account Automation system.
System: $($env:COMPUTERNAME) | Script Version: $($Global:ScriptVersion)
"@
    }
}

Function Get-ProcessSummaryEmailBody {
    [CmdletBinding()]
    param(
        [bool]$IsSuccessful,
        [string]$CustomMessage,
        [bool]$UseHtml
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $school = $Global:Config.SchoolSettings.SchoolName
    $schoolNumber = $Global:Config.SchoolSettings.SchoolNumber
    $statusIcon = if ($IsSuccessful) { "✅" } else { "❌" }
    $statusText = if ($IsSuccessful) { "SUCCESS" } else { "FAILED" }
    $statusColor = if ($IsSuccessful) { "#28a745" } else { "#dc3545" }
    $backgroundClass = if ($IsSuccessful) { "success" } else { "failure"  }
    
    # Parse the processing summary to extract key statistics and create clean user-friendly summary
    $summaryText = $Global:ProcessingSummary.ToString()
    $newStudents = if ($summaryText -match "New Students: (\d+)") { $matches[1] } else { "0" }
    $departedStudents = if ($summaryText -match "Departed Students: (\d+)") { $matches[1] } else { "0" }
    $existingStudents = if ($summaryText -match "Retained Existing Students: (\d+)") { $matches[1] } else { "0" }
    $processedNew = if ($summaryText -match "Processed (\d+) new students") { $matches[1] } else { "0" }
    
    # Count PDF files generated
    $pdfCount = 0
    $yearLevelsProcessed = @()
    $summaryLines = $summaryText -split "`n"
    foreach ($line in $summaryLines) {
        if ($line -match "Year \d+.*students saved to PDF") {
            $pdfCount++
            if ($line -match "Year (\d+)") {
                $yearLevel = "Year $($matches[1])"
                if ($yearLevel -notin $yearLevelsProcessed) {
                    $yearLevelsProcessed += $yearLevel
                }
            }
        }
    }
    
    # Create user-friendly summary
    $userFriendlySummary = Get-UserFriendlySummary -NewStudents $newStudents -DepartedStudents $departedStudents -ExistingStudents $existingStudents -PdfCount $pdfCount -YearLevels $yearLevelsProcessed
    
    if ($UseHtml) {
        return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            line-height: 1.6; 
            background-color: #f5f7fa;
        }
        .email-container { 
            max-width: 800px; 
            margin: 0 auto; 
            background-color: white; 
            border-radius: 12px; 
            overflow: hidden; 
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        .header { 
            background: linear-gradient(135deg, $statusColor 0%, $(if ($IsSuccessful) { '#20c997' } else { '#e74c3c' }) 100%);
            color: white; 
            padding: 30px; 
            text-align: center; 
        }
        .header h1 { 
            margin: 0; 
            font-size: 28px; 
            font-weight: 600; 
        }
        .header p { 
            margin: 8px 0 0 0; 
            opacity: 0.9; 
            font-size: 16px; 
        }
        .summary-stats { 
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            padding: 20px;
            margin: 0;
            border-radius: 0;
        }
        .stat-row {
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 30px;
            max-width: 500px;
            margin: 0 auto;
            flex-wrap: wrap;
        }
        .stat-item { 
            display: flex;
            align-items: center;
            gap: 8px;
            background: white;
            padding: 8px 16px;
            border-radius: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
            border: 1px solid #e9ecef;
        }
        .stat-number { 
            font-size: 16px; 
            font-weight: bold; 
            color: $statusColor; 
            margin: 0;
        }
        .stat-label { 
            color: #495057; 
            font-size: 12px; 
            font-weight: 500;
            margin: 0;
        }
        .content { 
            padding: 30px; 
        }
        .success-message { 
            background: linear-gradient(135deg, #d4edda 0%, #c3e6cb 100%);
            border: none;
            color: #155724; 
            padding: 25px; 
            border-radius: 10px; 
            margin-bottom: 25px;
            border-left: 5px solid #28a745;
        }
        .failure-message { 
            background: linear-gradient(135deg, #f8d7da 0%, #f5c6cb 100%);
            border: none;
            color: #721c24; 
            padding: 25px; 
            border-radius: 10px; 
            margin-bottom: 25px;
            border-left: 5px solid #dc3545;
        }
        .change-section {
            background: white;
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 12px 15px;
            margin: 12px 0;
            box-shadow: 0 1px 3px rgba(0,0,0,0.05);
        }
        .change-section h4 {
            margin: 0 0 10px 0;
            color: #495057;
            font-size: 15px;
            font-weight: 600;
        }
        .student-list {
            margin: 0;
            padding-left: 20px;
        }
        .student-list.compact {
            margin: 0;
            padding-left: 15px;
            column-count: 2;
            column-gap: 20px;
        }
        .student-list li {
            margin: 8px 0;
            color: #495057;
            font-size: 14px;
        }
        .student-list.compact li {
            margin: 4px 0;
            color: #495057;
            font-size: 12px;
            break-inside: avoid;
        }
        .no-changes {
            text-align: center;
            padding: 15px;
            color: #6c757d;
            font-size: 14px;
        }
        .no-changes h4 {
            color: #28a745;
            margin-bottom: 8px;
            font-size: 16px;
        }
        .info-note {
            font-style: italic;
            color: #6c757d;
            font-size: 12px;
            margin: 6px 0;
        }
        .security-note {
            background-color: #fff3cd;
            border: 1px solid #ffeaa7;
            color: #856404;
            padding: 6px 10px;
            border-radius: 4px;
            font-size: 12px;
            margin-top: 8px;
            display: inline-block;
        }
        .year-levels {
            background: #e3f2fd;
            border: 1px solid #bbdefb;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
        .year-levels h3 {
            margin: 0 0 10px 0;
            color: #1976d2;
        }
        .technical-summary { 
            background: #f8f9fa; 
            border: 1px solid #dee2e6; 
            padding: 15px; 
            border-radius: 8px; 
            margin-top: 25px;
        }
        .technical-summary h4 { 
            margin: 0 0 10px 0;
            color: #495057; 
            font-size: 14px;
            font-weight: 600;
        }
        .summary-metrics { 
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 10px;
            margin-bottom: 15px;
        }
        .metric-item {
            background: white;
            padding: 8px 12px;
            border-radius: 6px;
            font-size: 12px;
            border-left: 3px solid $statusColor;
        }
        .metric-label {
            color: #6c757d;
            font-weight: 500;
        }
        .metric-value {
            color: #495057;
            font-weight: 600;
        }
        .process-time {
            text-align: center;
            color: #6c757d;
            font-size: 11px;
            margin-top: 10px;
            padding-top: 10px;
            border-top: 1px solid #e9ecef;
        }
        .footer { 
            background-color: #f8f9fa;
            color: #6c757d; 
            font-size: 12px; 
            padding: 25px 30px; 
            text-align: center; 
            border-top: 1px solid #dee2e6; 
        }
        .footer p { 
            margin: 5px 0; 
        }
        .highlight { 
            color: $statusColor; 
            font-weight: 600; 
        }
        h3 { 
            color: #495057; 
            margin: 0 0 15px 0; 
            font-size: 18px;
            font-weight: 600;
        }
        @media (max-width: 600px) {
            .stat-row { 
                gap: 15px; 
            }
            .stat-item {
                padding: 6px 12px;
            }
            .content { 
                padding: 20px; 
            }
            .header { 
                padding: 20px; 
            }
            .summary-metrics {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="email-container">
        <div class="header">
            <h1>$statusIcon Student Account Update</h1>
            <p><strong>$statusText</strong> • $school</p>
            <p>$(Get-Date -Format 'dddd, dd MMMM yyyy')</p>
        </div>
        
        $(if ($IsSuccessful) {
            "<div class='summary-stats'>
                <div class='stat-row'>
                    <div class='stat-item'>
                        <span class='stat-number'>$newStudents</span>
                        <span class='stat-label'>New</span>
                    </div>
                    <div class='stat-item'>
                        <span class='stat-number'>$departedStudents</span>
                        <span class='stat-label'>Departed</span>
                    </div>
                    <div class='stat-item'>
                        <span class='stat-number'>$existingStudents</span>
                        <span class='stat-label'>Current</span>
                    </div>
                    <div class='stat-item'>
                        <span class='stat-number'>$pdfCount</span>
                        <span class='stat-label'>Lists Updated</span>
                    </div>
                </div>
            </div>"
        })
        
        <div class="content">
            $(if ($IsSuccessful) {
                "<div class='success-message'>
                    <h3>🎉 Daily Update Completed Successfully</h3>
                    <p>All student account updates have been processed and class lists have been refreshed.</p>
                </div>
                $userFriendlySummary"
            } else {
                "<div class='failure-message'>
                    <h3>⚠️ Daily Update Failed</h3>
                    <p>The student account update process encountered errors and could not complete. The IT administrator has been notified and will investigate the issue.</p>
                    $(if (-not [string]::IsNullOrWhiteSpace($CustomMessage)) {
                        "<p><strong>Error Details:</strong> $CustomMessage</p>"
                    })
                </div>"
            })
            
            $(if ($IsSuccessful -and $yearLevelsProcessed.Count -gt 0) {
                "<div class='year-levels'>
                    <h3>📚 Updated Class Lists</h3>
                    <p>Fresh class lists with current student information are now available for: <span class='highlight'>$($yearLevelsProcessed -join ', ')</span></p>
                    <p>Teachers can access these updated Excel files in the StudentsByYearLevel folder.</p>
                </div>"
            })
        </div>
        
        $(if ($IsSuccessful) {
            "$(Get-TechnicalSummaryHtml -SummaryText $summaryText -StatusColor $statusColor)"
        })
        
        <div class="footer">
            <p><strong>Student Account Management System</strong></p>
            <p>$school (School #$schoolNumber) • Generated at $timestamp</p>
            $(if ($Global:Config.EmailNotification.AdminOnly) {
                "<p>Technical support: $($Global:Config.EmailNotification.AdminOnly)</p>"
            })
        </div>
    </div>
</body>
</html>
"@
    } else {
        # Plain text version - also user-friendly
        $plainTextSummary = $userFriendlySummary -replace '<[^>]+>', '' -replace '&nbsp;', ' ' # Strip HTML tags
        
        return @"
$statusIcon Student Account Update Report
==========================================

Status: $statusText
School: $school | $(Get-Date -Format 'dddd, dd MMMM yyyy')

$(if ($IsSuccessful) {
"📊 DAILY SUMMARY:
• New Students: $newStudents
• Departed Students: $departedStudents  
• Current Students: $existingStudents
• Class Lists Updated: $pdfCount

🎉 DAILY UPDATE COMPLETED SUCCESSFULLY

$plainTextSummary

$(if ($yearLevelsProcessed.Count -gt 0) {
"📚 UPDATED CLASS LISTS: $($yearLevelsProcessed -join ', ')
Fresh Excel class lists with current student information are now available 
in the StudentsByYearLevel folder for teachers and administrators.
"})
"} else {
"⚠️ DAILY UPDATE FAILED

The student account update process encountered errors and could not complete. 
The IT administrator has been notified and will investigate the issue.

$(if (-not [string]::IsNullOrWhiteSpace($CustomMessage)) {
"Error Details: $CustomMessage
"})
"})

$(if ($IsSuccessful) {
"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TECHNICAL DETAILS (for IT reference)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$summaryText
"})

This report was automatically generated by the Student Account Management System.
$school (School #$schoolNumber) | Generated at $timestamp
$(if ($Global:Config.EmailNotification.AdminOnly) {
"For technical support, contact: $($Global:Config.EmailNotification.AdminOnly)"
})
"@
    }
}

Function Get-UserFriendlySummary {
    [CmdletBinding()]
    param(
        [string]$NewStudents,
        [string]$DepartedStudents, 
        [string]$ExistingStudents,
        [string]$PdfCount,
        [array]$YearLevels
    )
    
    $summaryParts = @()
    
    # Parse the detailed summary to extract student names and details
    $summaryText = $Global:ProcessingSummary.ToString()
    
    # Extract new student details
    $newStudentDetails = @()
    if ($summaryText -match "New Student Details:(.*?)(?=\n\d\.|$)" -and $NewStudents -ne "0") {
        $newStudentSection = $matches[1]
        $newStudentLines = $newStudentSection -split "`n" | Where-Object { $_ -match "^\s*-\s*(.+)" }
        foreach ($line in $newStudentLines) {
            if ($line -match "^\s*-\s*(.+)") {
                $newStudentDetails += $matches[1].Trim()
            }
        }
    }
    
    # Extract departed student details (if any tracking exists)
    $departedStudentDetails = @()
    # Note: Current system doesn't track departed student names, but framework is here for future enhancement
    
    # Extract password generation details
    $passwordUpdates = @()
    if ($summaryText -match "newly generated passwords:(.*?)(?=\n\d\.|$)") {
        $passwordSection = $matches[1]
        $passwordLines = $passwordSection -split "`n" | Where-Object { $_ -match "^\s*-\s*(.+)" }
        foreach ($line in $passwordLines) {
            if ($line -match "^\s*-\s*(.+)") {
                $passwordUpdates += $matches[1].Trim()
            }
        }
    }
    
    # Extract class/year level changes
    $detailChanges = @()
    if ($summaryText -match "Student Detail Changes \(YearLevel/Class/Email\):(.*?)(?=\n\d\.|$)") {
        $changesSection = $matches[1]
        $changeLines = $changesSection -split "`n" | Where-Object { $_ -match "^\s*-\s*(.+)" }
        foreach ($line in $changeLines) {
            if ($line -match "^\s*-\s*(.+)") {
                $detailChanges += $matches[1].Trim()
            }
        }
    }
    
    # Build user-friendly summary
    if ($NewStudents -ne "0" -and $newStudentDetails.Count -gt 0) {
        $summaryParts += "<div class='change-section'>"
        $summaryParts += "<h4>🎉 New Students ($NewStudents)</h4>"
        $summaryParts += "<ul class='student-list compact'>"
        foreach ($student in $newStudentDetails) {
            $summaryParts += "<li>$student</li>"
        }
        $summaryParts += "</ul>"
        $summaryParts += "</div>"
    }
    
    if ($DepartedStudents -ne "0") {
        $summaryParts += "<div class='change-section'>"
        $summaryParts += "<h4>👋 Departed Students ($DepartedStudents)</h4>"
        if ($departedStudentDetails.Count -gt 0) {
            $summaryParts += "<ul class='student-list compact'>"
            foreach ($student in $departedStudentDetails) {
                $summaryParts += "<li>$student</li>"
            }
            $summaryParts += "</ul>"
        } else {
            $summaryParts += "<p class='info-note'>Accounts deactivated - details not available</p>"
        }
        $summaryParts += "</div>"
    }
    
    if ($detailChanges.Count -gt 0) {
        $summaryParts += "<div class='change-section'>"
        $summaryParts += "<h4>📝 Student Updates</h4>"
        $summaryParts += "<ul class='student-list compact'>"
        foreach ($change in $detailChanges) {
            $summaryParts += "<li>$change</li>"
        }
        $summaryParts += "</ul>"
        $summaryParts += "</div>"
    }
    
    if ($passwordUpdates.Count -gt 0) {
        $summaryParts += "<div class='change-section'>"
        $summaryParts += "<h4>🔐 Password Updates</h4>"
        $summaryParts += "<ul class='student-list compact'>"
        foreach ($update in $passwordUpdates) {
            $summaryParts += "<li>$update</li>"
        }
        $summaryParts += "</ul>"
        $summaryParts += "<p class='security-note'>⚠️ New passwords available in class lists</p>"
        $summaryParts += "</div>"
    }
    
    if ($summaryParts.Count -eq 0) {
        $summaryParts += "<div class='no-changes'>"
        $summaryParts += "<h4>📊 No Changes Today</h4>"
        $summaryParts += "<p>All student accounts are up to date.<br>No enrollments, departures, or information changes.</p>"
        $summaryParts += "</div>"
    }
    
    return $summaryParts -join ""
}

Function Get-TechnicalSummaryHtml {
    [CmdletBinding()]
    param(
        [string]$SummaryText,
        [string]$StatusColor
    )
    
    # Extract key metrics from the summary
    $downloadTime = if ($SummaryText -match "Downloaded student data in ([\d.]+) seconds") { $matches[1] } else { "N/A" }
    $processTime = if ($SummaryText -match "Total processing time: ([\d.]+) seconds") { $matches[1] } else { "N/A" }
    $recordsProcessed = if ($SummaryText -match "Total records processed: (\d+)") { $matches[1] } else { "N/A" }
    $passwordsGenerated = if ($SummaryText -match "(\d+) newly generated passwords") { $matches[1] } else { "0" }
    $errorsCount = ([regex]::Matches($SummaryText, "ERROR")).Count
    $warningsCount = ([regex]::Matches($SummaryText, "WARNING")).Count
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    # Only show if there are metrics to display
    if ($recordsProcessed -eq "N/A" -and $downloadTime -eq "N/A" -and $processTime -eq "N/A") {
        return ""
    }
    
    return @"
<div class='technical-summary'>
    <h4>📊 Process Summary</h4>
    <div class='summary-metrics'>
        $(if ($recordsProcessed -ne "N/A") { "<div class='metric-item'><span class='metric-label'>Records:</span> <span class='metric-value'>$recordsProcessed</span></div>" })
        $(if ($passwordsGenerated -ne "0") { "<div class='metric-item'><span class='metric-label'>Passwords:</span> <span class='metric-value'>$passwordsGenerated</span></div>" })
        $(if ($downloadTime -ne "N/A") { "<div class='metric-item'><span class='metric-label'>Download:</span> <span class='metric-value'>${downloadTime}s</span></div>" })
        $(if ($processTime -ne "N/A") { "<div class='metric-item'><span class='metric-label'>Process:</span> <span class='metric-value'>${processTime}s</span></div>" })
        $(if ($errorsCount -gt 0) { "<div class='metric-item'><span class='metric-label'>Errors:</span> <span class='metric-value' style='color: #dc3545;'>$errorsCount</span></div>" })
        $(if ($warningsCount -gt 0) { "<div class='metric-item'><span class='metric-label'>Warnings:</span> <span class='metric-value' style='color: #ffc107;'>$warningsCount</span></div>" })
    </div>
    <div class='process-time'>Completed at $timestamp</div>
</div>
"@
}

# Export functions
Export-ModuleMember -Function Send-NotificationEmail, Get-AdminErrorEmailBody, Get-ProcessSummaryEmailBody, Get-UserFriendlySummary, Get-TechnicalSummaryHtml

Write-Verbose "[Utils] EmailNotificationHelper.psm1 loaded."
