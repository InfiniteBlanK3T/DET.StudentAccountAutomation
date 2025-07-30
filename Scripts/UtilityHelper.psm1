# UtilityHelper.psm1
# Purpose: Utility functions for password generation and file cleanup
# Author: Thomas VO (ST02392)
# Date: 30-07-2025

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

function Invoke-FileCleanUp {
    [CmdletBinding()]
    param()
    
    $cleanupConfig = $Global:Config.FileCleanup
    if (-not $cleanupConfig) {
        Write-Log -Message "File cleanup configuration not found. Skipping cleanup." -Level Warning
        return
    }
    if (-not $cleanupConfig.Enabled) {
        Write-Log -Message "File cleanup is disabled in configuration. Skipping cleanup." -Level Information
        return
    }

    $today = Get-Date
    $runDay = $cleanupConfig.RunOnDayOfWeek
    if ($today.DayOfWeek -ne $runDay) {
        Write-Log -Message "Today is $($today.DayOfWeek), but cleanup is scheduled for $runDay. Skipping cleanup." -Level Information
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
        $filesToDeleteLogs = Get-ChildItem -Path $LogDir -File | Where-Object { $_.LastWriteTime -lt $cutoffDateLogs }
        if ($filesToDeleteLogs.Count -gt 0) {
            $filesToDeleteLogs | Remove-Item -Force
            Write-Log -Message "Deleted $($filesToDeleteLogs.Count) old log files." -Level Information
            $Global:ProcessingSummary.AppendLine("     SUCCESS: Deleted $($filesToDeleteLogs.Count) old log files.") | Out-Null
        } else {
            Write-Log -Message "No old log files found for cleanup." -Level Information
            $Global:ProcessingSummary.AppendLine("     INFO: No old log files found for cleanup.") | Out-Null
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
        $filesToDeleteArchives = Get-ChildItem -Path $ArchivedMasterDataDir -File | Where-Object { $_.LastWriteTime -lt $cutoffDateArchives }
        if ($filesToDeleteArchives.Count -gt 0) {
            $filesToDeleteArchives | Remove-Item -Force
            Write-Log -Message "Deleted $($filesToDeleteArchives.Count) old archived data files." -Level Information
            $Global:ProcessingSummary.AppendLine("     SUCCESS: Deleted $($filesToDeleteArchives.Count) old archived data files.") | Out-Null
        } else {
            Write-Log -Message "No old archived data files found for cleanup." -Level Information
            $Global:ProcessingSummary.AppendLine("     INFO: No old archived data files found for cleanup.") | Out-Null
        }
    } catch {
        Write-Log -Message "Error during archive file cleanup: $($_.Exception.Message)" -Level Error
        $Global:ProcessingSummary.AppendLine("     ERROR during archive cleanup: $($_.Exception.Message)") | Out-Null
    }
}

function Get-UserFriendlySummary {
    [CmdletBinding()]
    param(
        [string]$NewStudents,
        [string]$DepartedStudents, 
        [string]$ExistingStudents,
        [int]$PdfCount,
        [array]$YearLevels
    )
    
    $summary = @()
    
    # Handle student changes in friendly language
    if ([int]$NewStudents -gt 0) {
        $studentWord = if ([int]$NewStudents -eq 1) { "student" } else { "students" }
        $summary += "• $NewStudents new $studentWord joined the school and account$( if ([int]$NewStudents -gt 1) { 's have' } else { ' has' } ) been created"
    }
    
    if ([int]$DepartedStudents -gt 0) {
        $studentWord = if ([int]$DepartedStudents -eq 1) { "student" } else { "students" }
        $summary += "• $DepartedStudents $studentWord $( if ([int]$DepartedStudents -gt 1) { 'have' } else { 'has' } ) left the school and account$( if ([int]$DepartedStudents -gt 1) { 's have' } else { ' has' } ) been deactivated"
    }
    
    if ([int]$NewStudents -eq 0 -and [int]$DepartedStudents -eq 0) {
        $summary += "• No student enrollment changes today"
    }
    
    # Handle PDF generation
    if ($PdfCount -gt 0) {
        $classWord = if ($PdfCount -eq 1) { "class list" } else { "class lists" }
        $summary += "• $PdfCount updated $classWord generated and ready for teachers"
    }
    
    # Current student count
    $summary += "• Total active students: $ExistingStudents"
    
    return ($summary -join "`n")
}

# Export functions
Export-ModuleMember -Function Get-RandomPasswordSimple, Invoke-FileCleanUp, Get-UserFriendlySummary

Write-Verbose "[Utils] UtilityHelper.psm1 loaded."
