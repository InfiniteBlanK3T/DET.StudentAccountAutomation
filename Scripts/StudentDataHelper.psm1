# StudentDataHelper.psm1
# Purpose: Functions for student data comparison and processing
# Author: Thomas VO (ST02392)
# Date: 30-07-2025

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

# Export functions
Export-ModuleMember -Function Compare-StudentLists, Test-DuplicationEntry

Write-Verbose "[Utils] StudentDataHelper.psm1 loaded."
