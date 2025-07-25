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
    $sendThisEmail = $true # Assume email should be sent unless specific conditions prevent it

    # Determine recipients
    if ($Global:Config.ScriptBehavior.MockMode -and -not [string]::IsNullOrWhiteSpace($Global:Config.ScriptBehavior.TestEmail)) {
        $emailRecipients = $Global:Config.ScriptBehavior.TestEmail.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
        Write-Log -Message "MOCK MODE: Email will be sent to TestEmail: $($Global:Config.ScriptBehavior.TestEmail)" -Level Information
    } elseif ($NotificationType -eq "AdminError" -and $Global:Config.EmailNotification.AdminNotifyOnError -and -not [string]::IsNullOrWhiteSpace($Global:Config.EmailNotification.AdminEmailOnError)) {
        $emailRecipients = $Global:Config.EmailNotification.AdminEmailOnError.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
    } elseif ($NotificationType -eq "ProcessSummary" -and -not [string]::IsNullOrWhiteSpace($Global:Config.EmailNotification.To)) {
        $emailRecipients = $Global:Config.EmailNotification.To.Split(';') | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ""}
    }

    if ($emailRecipients.Count -eq 0) {
        Write-Log -Message "No valid email recipients configured or determined for $NotificationType. Skipping email." -Level Warning
        return
    }

    # Determine subject and body
    if ($NotificationType -eq "AdminError") {
        $emailSubject = "CRITICAL ERROR in Daily Student Update Script - $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
        $emailBody = "A critical error occurred in the Daily Student Update script for $($Global:Config.SchoolSettings.SchoolName).`n`n"
        $emailBody += "Error Message: $CustomMessage`n`n"
        if (-not [string]::IsNullOrWhiteSpace($CustomDetails)) {
            $emailBody += "Error Details: $CustomDetails`n`n"
        }
        $emailBody += "Please check the log file for more details: $LogFilePath"
    } elseif ($NotificationType -eq "ProcessSummary") {
        if ($IsScriptSuccessful) {
            $emailSubject = "SUCCESS - $($Global:Config.EmailNotification.SubjectPrefix) for $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
            Write-Log -Message "Script completed successfully. Preparing success email." -Level Information
        } else {
            $emailSubject = "FAILED - $($Global:Config.EmailNotification.SubjectPrefix) for $($Global:Config.SchoolSettings.SchoolName) - $(Get-Date -Format 'yyyy-MM-dd')"
            Write-Log -Message "Script failed. Preparing failure email." -Level Information
            # If script failed, and SendOnSuccessOnly is true, don't send summary email
            if ($Global:Config.EmailNotification.SendOnSuccessOnly) {
                Write-Log -Message "SendOnSuccessOnly is true and script failed. Skipping process summary email." -Level Information
                $sendThisEmail = $false
            }
        }
        $emailBody = $Global:ProcessingSummary.ToString()
        if (-not [string]::IsNullOrWhiteSpace($CustomMessage)) {
            $emailBody += "`n`nAdditional Information:`n$CustomMessage"
        }
    }

    if (-not $sendThisEmail) {
        return # Email sending was intentionally skipped by logic above
    }

    $emailParams = @{
        To         = $emailRecipients
        From       = $Global:Config.EmailNotification.From
        Subject    = $emailSubject
        Body       = $emailBody
        SmtpServer = $Global:Config.EmailNotification.SmtpServer
        Port       = $Global:Config.EmailNotification.Port
    }
    if ($Global:Config.EmailNotification.BodyAsHtml) { $emailParams.BodyAsHtml = $true }

    try {
        Write-Log -Message "Attempting to send $NotificationType email to: $($emailRecipients -join '; ')" -Level Information
        Send-MailMessage @emailParams
        Write-Log -Message "$NotificationType email sent successfully." -Level Information
        if ($NotificationType -eq "ProcessSummary") { # Append to summary only for process summary email
            $Global:ProcessingSummary.AppendLine("Email Notification Sent To: $($emailRecipients -join '; ')") | Out-Null
        }
    } catch {
        Write-Log -Message "Failed to send $NotificationType email: $($_.Exception.Message)" -Level Error
        if ($NotificationType -eq "ProcessSummary") {
            $Global:ProcessingSummary.AppendLine("EMAIL SEND FAILED ($($NotificationType)): $($_.Exception.Message)") | Out-Null
        }
        # For AdminError, the failure to send is critical but already logged.
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
Export-ModuleMember -Function Compare-StudentLists, Get-RandomPasswordSimple, Test-DuplicationEntry, Send-NotificationEmail, Invoke-FileCleanUp

Write-Log "[Utils] MiscHelper.psm1 loaded."
