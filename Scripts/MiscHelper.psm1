function Compare-StudentLists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DownloadedStudents, # Array of PSCustomObjects
        [Parameter(Mandatory = $true)]
        [array]$MasterStudents      # Array of PSCustomObjects
    )
    Write-Log "[Utils] Comparing student lists. Downloaded: $($DownloadedStudents.Count), Current: $($MasterStudents.Count)"

    $downloadedUsernames = $DownloadedStudents | Select-Object -ExpandProperty Username -Unique
    $masterUsernames = $MasterStudents | Select-Object -ExpandProperty Username -Unique

    $newStudentUsernames = Compare-Object -ReferenceObject $masterUsernames -DifferenceObject $downloadedUsernames -PassThru | Where-Object { $_ -in $downloadedUsernames }
    $departedStudentUsernames = Compare-Object -ReferenceObject $downloadedUsernames -DifferenceObject $masterUsernames -PassThru | Where-Object { $_ -in $masterUsernames }

    $newStudentList = $DownloadedStudents | Where-Object { $_.Username -in $newStudentUsernames }
    $departedStudentList = $MasterStudents | Where-Object { $_.Username -in $departedStudentUsernames }
    # Existing students are those in master who are not in departed list
    $existingStudentList = $MasterStudents | Where-Object { $_.Username -notin $departedStudentUsernames }


    Write-Log "Found $($newStudentList.Count) new students."
    Write-Log "Found $($departedStudentList.Count) departed students."
    Write-Log "Found $($existingStudentList.Count) existing students to retain."

    return [PSCustomObject]@{
        NewStudents       = $newStudentList      # Students in downloaded, not in master
        DepartedStudents  = $departedStudentList # Students in master, not in downloaded
        ExistingStudents  = $existingStudentList # Students in master AND in downloaded (to be carried over)
    }
}

function Get-RandomPasswordSimple {
    <#
    .SYNOPSIS
        Generates a simple, memorable random password.
    .DESCRIPTION
        Combines a capitalized word (animal, color, or object) with 4 random digits, separated by a dot.
        Example: Panda.1234
    #>
    $passwordLists = @(
        # Animals
        "Crab", "Lion", "Zebra", "Panda", "Frog", "Koala", "Shark", "Tiger", "Bear", "Wolf", 
        "Fox", "Eagle", "Hawk", "Owl", "Deer", "Moose", "Bison", "Penguin", "Dolphin", "Whale",
        "Octopus", "Squid", "Turtle", "Snake", "Lizard", "Rabbit", "Puppy", "Kitten", "Mouse",
        "Horse", "Pony", "Goat", "Sheep", "Duck", "Goose", "Chicken", "Fish", "Monkey", "Cow",
        "Cat", "Dog", "Pig", "Bird", "Frog", "Seal", "Otter", "Parrot", "Hamster", "Gerbil",
        # Colors
        "Red", "Blue", "Green", "Yellow", "Orange", "Purple", "Pink", "Brown", "Black", "White",
        "Gold", "Silver", "Cyan", "Teal", "Coral", "Amber", "Ruby", "Peach", "Lime", "Mint",
        "Violet", "Maroon", "Navy", "Plum", "Olive", "Rose", "Beige", "Cream", "Gray", "Tan",
        # Simple objects
        "Apple", "Ball", "Chair", "Desk", "Eraser", "Flag", "Globe", "House", "Ice", "Jar",
        "Kite", "Lamp", "Moon", "Nest", "Pencil", "Queen", "Ruler", "Star", "Table", "Book",
        "Vase", "Wheel", "Box", "Yarn", "Zipper", "Sun", "Cloud", "Tree", "Flower", "Grass",
        "Hat", "Shoe", "Sock", "Ring", "Key", "Door", "Window", "Bed", "Cup", "Plate",
        "Fork", "Spoon", "Knife", "Bowl", "Bike", "Car", "Bus", "Train", "Boat", "Plane",
        "Cake", "Pizza", "Clock", "Watch", "Coin", "Button", "Paper", "Paint", "Brush", "Glue"
    )
    $word = Get-Random -InputObject $passwordLists
    $numbers = "{0:D4}" -f (Get-Random -Minimum 0 -Maximum 9999) # Ensures 4 digits with leading zeros
    $password = "$word.$numbers"
    # Write-Log "[Utils] Generated random password pattern: $word.$numbers"
    return $password
}

function Test-DuplicationEntry {
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$CurrentData, # Expects array of PSCustomObjects with a 'Username' property
        [string]$OutputPathForDuplicates = "." # Directory to save duplicates CSV
    )
    $FileName = "Duplicate_Usernames_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $FilePath = Join-Path -Path $OutputPathForDuplicates -ChildPath $FileName
    
    $DuplicateUsernamesGroup = $CurrentData | Where-Object {$_.Username} | Group-Object -Property Username | Where-Object { $_.Count -gt 1 }
    
    if ($DuplicateUsernamesGroup) {
        Write-Warning "[Utils] Duplicate usernames found in the provided data:"
        $DuplicateUsernamesGroup | ForEach-Object {
            Write-Warning "[Utils]   Username '$($_.Name)' appears $($_.Count) times."
        }
        
        $DuplicateRecords = $CurrentData | Where-Object { $_.Username -in $DuplicateUsernamesGroup.Name }
        try {
            $DuplicateRecords | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
            # The main script handles quote removal if configured globally.
            # If this function needs specific quote handling:
            # (Get-Content -Path $FilePath) | ForEach-Object { $_ -replace '"', '' } | Set-Content -Path $FilePath
            Write-Warning "[Utils] Details of duplicate records exported to: $FilePath"
        } catch {
            Write-Warning "[Utils] Failed to export duplicate records to $($FilePath): $($_.Exception.Message)"
        }
        return $true
    }
    Write-Log "[Utils] No duplicate usernames found in the provided data."
    return $false
}

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

    $emailRecipients = @()
    $emailSubject = ""
    $emailBody = ""
    $useHtml = $Global:Config.EmailNotification.UseHtmlFormat -eq $true

    # Determine recipients based on script success/failure and notification type
    if ($Global:Config.ScriptBehavior.MockMode -and -not [string]::IsNullOrWhiteSpace($Global:Config.ScriptBehavior.TestEmail)) {
        $emailRecipients = $Global:Config.ScriptBehavior.TestEmail.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
        Write-Log -Message "MOCK MODE: Email will be sent to TestEmail: $($Global:Config.ScriptBehavior.TestEmail)" -Level Information
    } elseif ($NotificationType -eq "AdminError" -or -not $IsScriptSuccessful) {
        # Send to admin only when there's an error or script failure
        if (-not [string]::IsNullOrWhiteSpace($Global:Config.EmailNotification.AdminOnly)) {
            $emailRecipients = $Global:Config.EmailNotification.AdminOnly.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
        }
    } elseif ($NotificationType -eq "ProcessSummary" -and $IsScriptSuccessful) {
        # Send to all team members when script is successful
        if (-not [string]::IsNullOrWhiteSpace($Global:Config.EmailNotification.TeamMembers)) {
            $emailRecipients = $Global:Config.EmailNotification.TeamMembers.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
        }
    }

    if ($emailRecipients.Count -eq 0) {
        Write-Log -Message "No valid email recipients configured or determined for $NotificationType. Skipping email." -Level Warning
        return
    }

    # Create nicely formatted emails
    if ($NotificationType -eq "AdminError") {
        $emailSubject = "🚨 CRITICAL ERROR - Student Account Automation - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        $emailBody = Get-AdminErrorEmailBody -CustomMessage $CustomMessage -CustomDetails $CustomDetails -UseHtml $useHtml
    } elseif ($NotificationType -eq "ProcessSummary") {
        if ($IsScriptSuccessful) {
            $emailSubject = "✅ SUCCESS - $($Global:Config.EmailNotification.SubjectPrefix) - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
            Write-Log -Message "Script completed successfully. Preparing success email for team members." -Level Information
        } else {
            $emailSubject = "❌ FAILED - $($Global:Config.EmailNotification.SubjectPrefix) - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
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
    
    # Parse the processing summary to extract key statistics
    $summaryText = $Global:ProcessingSummary.ToString()
    $newStudents = if ($summaryText -match "New Students: (\d+)") { $matches[1] } else { "N/A" }
    $departedStudents = if ($summaryText -match "Departed Students: (\d+)") { $matches[1] } else { "N/A" }
    $existingStudents = if ($summaryText -match "Retained Existing Students: (\d+)") { $matches[1] } else { "N/A" }
    $processedNew = if ($summaryText -match "Processed (\d+) new students") { $matches[1] } else { "N/A" }
    
    if ($UseHtml) {
        return @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: $statusColor; color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .summary-stats { display: flex; flex-wrap: wrap; gap: 15px; margin-bottom: 20px; }
        .stat-card { background-color: #f8f9fa; border: 1px solid #dee2e6; padding: 15px; border-radius: 5px; min-width: 150px; text-align: center; }
        .stat-number { font-size: 24px; font-weight: bold; color: $statusColor; }
        .stat-label { color: #6c757d; font-size: 12px; }
        .content { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .details { background-color: white; padding: 15px; border-radius: 5px; border: 1px solid #dee2e6; }
        .footer { color: #6c757d; font-size: 12px; margin-top: 20px; }
        .success { border-left: 5px solid #28a745; }
        .failure { border-left: 5px solid #dc3545; }
        pre { background-color: #f1f1f1; padding: 10px; border-radius: 3px; overflow-x: auto; font-size: 11px; }
        h2 { color: $statusColor; }
    </style>
</head>
<body>
    <div class="header">
        <h1>$statusIcon Daily Student Account Update Report</h1>
        <p><strong>Status:</strong> $statusText</p>
        <p><strong>School:</strong> $school (Number: $schoolNumber)</p>
        <p><strong>Run Time:</strong> $timestamp</p>
    </div>
    
    $(if ($IsSuccessful) {
        "<div class='summary-stats'>
            <div class='stat-card'>
                <div class='stat-number'>$newStudents</div>
                <div class='stat-label'>NEW STUDENTS</div>
            </div>
            <div class='stat-card'>
                <div class='stat-number'>$departedStudents</div>
                <div class='stat-label'>DEPARTED STUDENTS</div>
            </div>
            <div class='stat-card'>
                <div class='stat-number'>$existingStudents</div>
                <div class='stat-label'>EXISTING STUDENTS</div>
            </div>
            <div class='stat-card'>
                <div class='stat-number'>$processedNew</div>
                <div class='stat-label'>ACCOUNTS CREATED</div>
            </div>
        </div>"
    })
    
    <div class="content $backgroundClass">
        <h2>📊 Processing Details</h2>
        <div class="details">
            <pre>$summaryText</pre>
        </div>
        
        $(if (-not [string]::IsNullOrWhiteSpace($CustomMessage)) {
            "<h3>ℹ️ Additional Information</h3>
            <p>$CustomMessage</p>"
        })
    </div>
    
    $(if ($IsSuccessful) {
        "<div style='background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 15px; border-radius: 5px; margin-bottom: 20px;'>
            <h3>🎉 All Tasks Completed Successfully!</h3>
            <p>The daily student account update process has been completed without any issues. All new student accounts have been created and existing accounts have been updated as needed.</p>
        </div>"
    } else {
        "<div style='background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; padding: 15px; border-radius: 5px; margin-bottom: 20px;'>
            <h3>⚠️ Process Failed</h3>
            <p>The daily student account update process encountered errors and could not complete successfully. Please check the log files and contact the system administrator.</p>
        </div>"
    })
    
    <div class="footer">
        <p>This email was automatically generated by the Student Account Automation system.</p>
        <p>System: $($env:COMPUTERNAME) | Script Version: $(if ($Global:ScriptVersion) { $Global:ScriptVersion } else { 'Unknown' })</p>
        <p>For support, contact: $($Global:Config.EmailNotification.AdminOnly)</p>
    </div>
</body>
</html>
"@
    } else {
        return @"
$statusIcon Daily Student Account Update Report
==========================================

Status: $statusText
School: $school (Number: $schoolNumber)
Run Time: $timestamp

$(if ($IsSuccessful) {
"📊 SUMMARY STATISTICS:
• New Students: $newStudents
• Departed Students: $departedStudents  
• Existing Students: $existingStudents
• Accounts Created: $processedNew
"})

📋 PROCESSING DETAILS:
$summaryText

$(if (-not [string]::IsNullOrWhiteSpace($CustomMessage)) {
"ℹ️ ADDITIONAL INFORMATION:
$CustomMessage
"})

$(if ($IsSuccessful) {
"🎉 All tasks completed successfully!
The daily student account update process has been completed without any issues."
} else {
"⚠️ Process failed!
The daily student account update process encountered errors. Please check the log files."})

This email was automatically generated by the Student Account Automation system.
System: $($env:COMPUTERNAME) | Script Version: $(if ($Global:ScriptVersion) { $Global:ScriptVersion } else { 'Unknown' })
For support, contact: $($Global:Config.EmailNotification.AdminOnly)
"@
    }
}


function Invoke-FileCleanUp {
    [CmdletBinding()]
    param()
    Write-Log -Message "Step 8: Performing automated file cleanup..." -Level Information
    $Global:ProcessingSummary.AppendLine("8. Performing automated file cleanup...")

    $cleanupConfig = $Global:Config.CleanupSettings
    if (-not $cleanupConfig) {
        Write-Warning "[Utils] Cleanup settings not found in configuration. Skipping cleanup."
        $Global:ProcessingSummary.AppendLine("8. Cleanup settings not found in configuration. Skipping cleanup.") | Out-Null
        return
    }
    if (-not $cleanupConfig.Enabled) {
        Write-Log "[Utils] Cleanup is disabled in configuration. Skipping cleanup." -Level Information
        $Global:ProcessingSummary.AppendLine("8. Cleanup is disabled in configuration. Skipping cleanup.") | Out-Null
        return
    }

    $today = Get-Date
    $runDay = $cleanupConfig.RunOnDayOfWeek
    if ($today.DayOfWeek -ne $runDay) {
        Write-Log "[Utils] Today is not the scheduled cleanup day ($runDay). Skipping scheduled file cleanup." -Level Information
        $Global:ProcessingSummary.AppendLine("  INFO: Today is not $runDay. Cleanup skipped.") | Out-Null
        return
    }

    Write-Log -Message "Today is $runDay. Proceeding with file cleanup." -Level Information
    $Global:ProcessingSummary.AppendLine("   INFO: Today is $runDay. Proceeding with cleanup.") | Out-Null

    # Cleanup Logs
    $retentionLogs = $cleanupConfig.RetentionDaysLogs
    $cutoffDateLogs = $today.AddDays(-$retentionLogs)
    Write-Log -Message "Cleaning up log files older than $retentionLogs days (before $($cutoffDateLogs.ToString('yyyy-MM-dd')) from $LogDir" -Level Information
    $Global:ProcessingSummary.AppendLine("   Cleaning up log files older than $retentionLogs days from $LogDir...") | Out-Null
    try {
        $oldLogs = Get-ChildItem -Path $LogDir -File | Where-Object { $_.LastWriteTime -lt $cutoffDateLogs -and $_.Name -ne (Split-Path $LogFilePath -Leaf) } # Exclude current log
        if ($oldLogs.Count -gt 0) {
            foreach ($logFile in $oldLogs) {
                Write-Log -Message "Deleting old log file: $($logFile.FullName) (LastWriteTime: $($logFile.LastWriteTime.ToString('yyyy-MM-dd')))" -Level Information
                if ($Global:Config.ScriptBehavior.MockMode) {
                    Write-Log -Message "  MOCK MODE: Simulated deletion of $($logFile.FullName)" -Level Information
                    $Global:ProcessingSummary.AppendLine("     MOCK: Deleted log - $($logFile.Name)") | Out-Null
                } else {
                    Remove-Item -Path $logFile.FullName -Force
                    $Global:ProcessingSummary.AppendLine("     Deleted log - $($logFile.Name)") | Out-Null
                }
            }
            Write-Log -Message "Deleted $($oldLogs.Count) old log files." -Level Information
        } else {
            Write-Log -Message "No old log files found to delete." -Level Information
            $Global:ProcessingSummary.AppendLine("     No old log files to delete.") | Out-Null
        }
    } catch {
        Write-Log -Message "Error during log file cleanup: $($_.Exception.Message)" -Level Error
        $Global:ProcessingSummary.AppendLine("     ERROR during log cleanup: $($_.Exception.Message)") | Out-Null
    }

    # Cleanup Archived Data
    $retentionArchives = $cleanupConfig.RetentionDaysArchives
    $cutoffDateArchives = $today.AddDays(-$retentionArchives)
    Write-Log -Message "Cleaning up archived data files older than $retentionArchives days (before $($cutoffDateArchives.ToString('yyyy-MM-dd'))) from $ArchivedMasterDataDir" -Level Information
    $Global:ProcessingSummary.AppendLine("   Cleaning up archived data files older than $retentionArchives days from $ArchivedMasterDataDir...") | Out-Null
    try {
        $oldArchives = Get-ChildItem -Path $ArchivedMasterDataDir -File | Where-Object { $_.LastWriteTime -lt $cutoffDateArchives }
        if ($oldArchives.Count -gt 0) {
            foreach ($archiveFile in $oldArchives) {
                Write-Log -Message "Deleting old archive file: $($archiveFile.FullName) (LastWriteTime: $($archiveFile.LastWriteTime.ToString('yyyy-MM-dd')))" -Level Information
                 if ($Global:Config.ScriptBehavior.MockMode) {
                    Write-Log -Message "  MOCK MODE: Simulated deletion of $($archiveFile.FullName)" -Level Information
                    $Global:ProcessingSummary.AppendLine("     MOCK: Deleted archive - $($archiveFile.Name)") | Out-Null
                } else {
                    Remove-Item -Path $archiveFile.FullName -Force
                    $Global:ProcessingSummary.AppendLine("     Deleted archive - $($archiveFile.Name)") | Out-Null
                }
            }
            Write-Log -Message "Deleted $($oldArchives.Count) old archive files." -Level Information
        } else {
            Write-Log -Message "No old archive files found to delete." -Level Information
            $Global:ProcessingSummary.AppendLine("     No old archive files to delete.") | Out-Null
        }
    } catch {
        Write-Log -Message "Error during archive file cleanup: $($_.Exception.Message)" -Level Error
        $Global:ProcessingSummary.AppendLine("     ERROR during archive cleanup: $($_.Exception.Message)") | Out-Null
    }
}

# Export the functions for use in other scripts
Export-ModuleMember -Function Compare-StudentLists, Get-RandomPasswordSimple, Test-DuplicationEntry, Send-NotificationEmail, Get-AdminErrorEmailBody, Get-ProcessSummaryEmailBody, Invoke-FileCleanUp

Write-Log "[Utils] MiscHelper.psm1 loaded."
