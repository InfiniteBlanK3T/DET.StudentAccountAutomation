# StudentDataUtils.ps1
# Version 1.1 (Adjusted for use with Process-DailyStudentUpdates.ps1 v2.0)
# Purpose: Utility functions for student account management with eduSTAR MC.
# Original Author: Thomas VO (ST02392)
# Adjustments for configurability and logging integration.

#region Helper Functions for Logging (Can be enhanced or rely on main script's Write-Log)
# For simplicity, these utilities will use Write-Verbose, Write-Warning, Write-Host for now.
# The main script's preferences will control console output.
# For critical errors, functions should 'throw' to allow the caller to handle.

#endregion

#region Credential Management
# As per user request, internal logic of Set-eMCCredentials remains largely unchanged.
# Consider making $CustomPath configurable in future versions if needed.
function Set-eMCCredentials {
    <#
    .SYNOPSIS
        Stores and manages credentials for network access.
    .DESCRIPTION
        Creates and manages secure credential storage for network access.
        Uses a hardcoded path C:\Credentials by default.
    #>
    $global:CustomPath = "C:\Credentials" # This path is hardcoded as per original script.
    $global:CacheRootPath = Join-Path -Path $global:CustomPath -ChildPath "eduSTARMCAdministration"    
    $global:CredsFile = Join-Path -Path $global:CacheRootPath -ChildPath "Creds.xml"
    
    if (-not (Test-Path -Path $global:CacheRootPath)) {
        try {
            New-Item -Path $global:CacheRootPath -ItemType Directory -Force | Out-Null
            Write-Verbose "[Utils] Created credentials cache directory: $($global:CacheRootPath)"
        } catch {
            Write-Warning "[Utils] Failed to create credentials cache directory $($global:CacheRootPath): $($_.Exception.Message)"
            # This might not be a fatal error if credentials already exist or are not strictly needed for all operations
        }
    }

    if (Test-Path -Path $global:CredsFile) {
        Write-Verbose "[Utils] Credential file [$($global:CredsFile)] found. Importing."
        try {
            $global:MyCredential = Import-Clixml -Path $global:CredsFile
        } catch {
            Write-Warning "[Utils] Failed to import credentials from [$($global:CredsFile)]: $($_.Exception.Message). Will prompt for new credentials."
            Remove-Item -Path $global:CredsFile -Force -ErrorAction SilentlyContinue
            # Fall through to prompt for new credentials
        }
    }
    
    if (-not $global:MyCredential) { # If creds file didn't exist or failed to load
        Write-Host "[Utils] Credential file not found or failed to load. Please provide credentials."
        try {
            $credentialInput = Get-Credential
            if ($credentialInput) {
                $credentialInput | Export-Clixml -Path $global:CredsFile -Force
                Write-Verbose "[Utils] Credentials saved to [$($global:CredsFile)]. Importing."
                $global:MyCredential = Import-Clixml -Path $global:CredsFile
            } else {
                throw "User did not provide credentials. Cannot continue."
            }
        } catch {
            throw "Failed to get or save credentials: $($_.Exception.Message)"
        }
    }
    Return $global:MyCredential
}
#endregion Credential Management

#region Proxy and Connection
function Test-Proxy {
    <#
    .SYNOPSIS
        Tests network connectivity to eduSTAR and configures proxy if needed.
    #>
    Write-Verbose "[Utils] Testing proxy connection to https://apps.edustar.vic.edu.au..."
    try {
        $Response = Invoke-WebRequest -Uri "https://apps.edustar.vic.edu.au" -ConnectionTimeoutSeconds 5 -UseBasicParsing # Added UseBasicParsing
        $StatusCode = $Response.StatusCode
        Write-Verbose "[Utils] Initial connection attempt status: $StatusCode"
    } catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__ # Potential error if Response is null
        Write-Warning "[Utils] Initial connection failed. Status Code: $StatusCode. Exception: $($_.Exception.Message)"
    }

    if ($StatusCode -ne 200) {
        Write-Verbose "[Utils] Setting system proxy for PowerShell session."
        try {
            [System.Net.WebRequest]::DefaultWebProxy = [System.Net.WebRequest]::GetSystemWebProxy()
            [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $Response = Invoke-WebRequest -Uri "https://apps.edustar.vic.edu.au" -ConnectionTimeoutSeconds 5 -UseBasicParsing
            $StatusCode = $Response.StatusCode
            Write-Verbose "[Utils] Connection attempt with proxy status: $StatusCode. Found eduSTAR MC using proxy."
        } catch {
            $StatusCode = $_.Exception.Response.StatusCode.value__
            Write-Warning "[Utils] Connection with proxy failed. Status Code: $StatusCode. Exception: $($_.Exception.Message)"
            throw "eduSTAR MC not found even with system proxy. Please check network/proxy settings."
        }
    } else {
        Write-Verbose "[Utils] Unsetting explicit PS Proxy (direct connection was successful)."
        [System.Net.WebRequest]::DefaultWebProxy = $null # Explicitly nullify if direct connection worked
        # Test again to be sure, though this might be redundant if first test was 200
        try {
            $Response = Invoke-WebRequest -Uri "https://apps.edustar.vic.edu.au" -ConnectionTimeoutSeconds 5 -UseBasicParsing
            $StatusCode = $Response.StatusCode
            Write-Verbose "[Utils] Found eduSTAR MC without a proxy set (direct). Status: $StatusCode. Continuing..."
        } catch {
            $StatusCode = $_.Exception.Response.StatusCode.value__
            Write-Warning "[Utils] Retest of direct connection failed. Status: $StatusCode. Exception: $($_.Exception.Message)"
            throw "eduSTAR MC not found. Direct connection failed after initial success check. Exiting..."
        }
    }
    # If we haven't thrown an error by now, connection is assumed okay.
}


function Connect-eduSTARMC {
    <#
    .SYNOPSIS
        Establishes a session with eduSTAR MC.
    #>
    Write-Verbose "[Utils] Attempting to connect to eduSTAR MC..."
    try {
        Test-Proxy # Ensure proxy is set up if needed. Test-Proxy will throw if it can't connect.
        
        $currentCredential = Set-eMCCredentials # This will prompt if not cached
        if (-not $currentCredential) {
            throw "Failed to obtain credentials for eduSTAR MC."
        }

        $WebRequestBody = @{
            curl        = "Z2Fedustarmc" # This seems to be a specific form field name
            username    = $currentCredential.UserName
            password    = $currentCredential.GetNetworkCredential().Password
            SubmitCreds = "Log+in"
        }

        Write-Verbose "[Utils] Sending login request to eduSTAR MC..."
        $Request = Invoke-WebRequest -Uri "https://apps.edustar.vic.edu.au/CookieAuth.dll?Logon" -Body $WebRequestBody -Method Post -SessionVariable eduSTARMCSessionGlobal -UseBasicParsing
        $script:eduSTARMCSession = $eduSTARMCSessionGlobal # Assign to script-scoped variable for other functions in this util script.

        if ($Request.Headers.Connection -eq 'Keep-Alive' -and $Request.StatusCode -eq 200) {
            Write-Verbose "[Utils] eduSTAR MC Login successful. Session established."
            # Optionally, get user details if needed for verification
            # $GetUser = Invoke-RestMethod -Uri "https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetUser" -Method Get -WebSession $script:eduSTARMCSession -ContentType "application/xml"
            # Write-Verbose "[Utils] Logged in as: $($GetUser.User._displayName)"
            # Return $true or a session object if desired by caller
            return $script:eduSTARMCSession # Return the session object
        } else {
            Write-Warning "[Utils] eduSTAR MC Login failed. Status: $($Request.StatusCode). Connection Header: $($Request.Headers.Connection)"
            # Consider removing creds file if login fails with valid-looking creds
            # Remove-Item -Path $global:CredsFile -Force -ErrorAction SilentlyContinue
            throw "Unable to connect to the eduSTAR Management Console. Login request failed."
        }
    } catch {
        Write-Warning "[Utils] Error during Connect-eduSTARMC: $($_.Exception.Message)" # Changed to Warning
        throw "Connection to eduSTAR MC failed: $($_.Exception.Message)" # Re-throw to be caught by main script
    }
}

function Disconnect-eduSTARMC {
    <#
    .SYNOPSIS
        Placeholder for disconnecting the eduSTAR MC session if applicable.
    .DESCRIPTION
        Currently, eduSTAR MC sessions might rely on cookie expiration.
        If a specific logout endpoint exists, it should be called here.
    #>
    Write-Verbose "[Utils] Disconnecting from eduSTAR MC (clearing session variable)."
    $script:eduSTARMCSession = $null
    # If there's a logout URL:
    # Invoke-WebRequest -Uri "https://apps.edustar.vic.edu.au/logout_endpoint" -WebSession $script:eduSTARMCSession
    Write-Host "[Utils] eduSTAR MC session has been cleared locally. Browser session may persist until cookie expires."
}
#endregion Proxy and Connection

#region School Management
# These functions might be less critical if SchoolNumber is always passed from config.
# They are kept for potential interactive use or other scripts.
function Set-eduSTARMCSchool {
    param (
        [Parameter(Mandatory=$false)]
        [string]$SchoolNumber # Renamed from 'School' to avoid conflict with common variable names
    )
    Write-Verbose "[Utils] Set-eduSTARMCSchool called with SchoolNumber: $SchoolNumber"
    if ($SchoolNumber) {
        $global:SelectedSchool = $SchoolNumber # Store it in the global var used by other util functions
        Write-Verbose "[Utils] Global SelectedSchool set to: $SchoolNumber"
        return $global:SelectedSchool
    } else {
        # Auto-detection logic (kept from original script)
        Write-Verbose "[Utils] No SchoolNumber provided, attempting auto-detection..."
        try {
            $WhoAmIthen = Invoke-WebRequest -Uri "http://broadband.doe.wan/api/ip/whoami" -UseBasicParsing | ConvertFrom-Json -ErrorAction Stop
            $ednum = $WhoAmIthen | Select-Object -ExpandProperty ednum
            if ($ednum -and $ednum.Length -gt 4) {
                $global:SelectedSchool = $ednum.Substring(2,4)
                Write-Verbose "[Utils] Auto-detected SchoolNumber: $($global:SelectedSchool)"
                return $global:SelectedSchool
            } else {
                Write-Warning "[Utils] Auto-detection failed: 'ednum' property not found or invalid from whoami API."
                return $null
            }
        } catch {
            Write-Warning "[Utils] Auto-detection of school number failed: $($_.Exception.Message)"
            return $null
        }
    }
}

function Get-eduSTARMCSchool {
    <#
    .SYNOPSIS
        Returns all schools assigned to the user currently authenticated.
    #>
    if (-not $script:eduSTARMCSession) { throw "[Utils] Not connected to eduSTAR MC. Call Connect-eduSTARMC first." }
    Write-Verbose "[Utils] Getting list of schools for the authenticated user..."
    try {
        [xml]$Request = Invoke-RestMethod -Uri "https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetAllSchools" -Method Get -WebSession $script:eduSTARMCSession -ContentType "application/xml" -ErrorAction Stop
        $Result = @()
        ForEach ($obj in $Request.ArrayOfSchool.School) {
            $item = New-Object PSObject -Property @{
                SchoolId   = $obj.SchoolId
                SchoolName = $obj.SchoolName
            }
            $Result += $item
        }
        Write-Verbose "[Utils] Found $($Result.Count) schools."
        return $Result
    } catch {
        throw "[Utils] Failed to get schools: $($_.Exception.Message)"
    }
}

function Select-eduSTARMCSchool {
    <#
    .SYNOPSIS
        Allows interactive selection of a school if multiple are available.
    .NOTES
        This is for interactive use. Automated scripts should use Set-eduSTARMCSchool or pass SchoolNumber directly.
    #>
    if($null -eq $global:SelectedSchool) { # Only run if not already set
        Write-Verbose "[Utils] Select-eduSTARMCSchool: No school pre-selected."
        if($null -eq $script:eduSTARMCSession) { Connect-eduSTARMC } # Ensure connection
        
        $schools = Get-eduSTARMCSchool
        if ($schools.Count -eq 0) {
            throw "[Utils] No schools found for this user."
        } elseif ($schools.Count -eq 1) {
            $global:SelectedSchool = $schools[0].SchoolId
            Write-Verbose "[Utils] Automatically selected only available school: $($global:SelectedSchool)"
        } else {
            Write-Host "[Utils] Multiple schools available. Please select one:" -ForegroundColor Yellow
            $global:SelectedSchool = $schools | Out-GridView -Title 'Select a school for eduSTAR MC session' -PassThru -ErrorAction Stop
            if ($global:SelectedSchool) {
                $global:SelectedSchool = $global:SelectedSchool.SchoolId # Ensure we get the ID
                Write-Verbose "[Utils] User selected school: $($global:SelectedSchool)"
            } else {
                throw "[Utils] No school selected by the user."
            }
        }
    }
    # Returns the SchoolId string
    if ($global:SelectedSchool -is [pscustomobject]) { # If full object was returned by mistake
         return $global:SelectedSchool.SchoolId
    }
    return $global:SelectedSchool
}

function Test-eduSTARMCSchoolNumber {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchoolNumberToTest # Changed parameter name to avoid conflict with $global:SelectedSchool
    )
    if ($SchoolNumberToTest -notmatch "^\d{4}$") { # Regex for exactly 4 digits
        throw "[Utils] Invalid School Number format: '$SchoolNumberToTest'. Must be 4 digits."
    }
    return $true
}
#endregion School Management

#region Student Account Functions

function Get-eduPassStudentAccount {
    <#
    .SYNOPSIS
        Retrieves student account information. Caches data for 23 hours.
    .PARAMETER SchoolNumber
        The 4-digit school number. Mandatory.
    .PARAMETER Identity
        Optional. Username of a specific student to retrieve.
    .PARAMETER Force
        Switch. Clears the local cache before retrieving students.
    .PARAMETER Timeout
        Optional. Timeout for the web request in seconds (default 60).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchoolNumber,
        [string]$Identity,
        [switch]$Force,
        [int]$Timeout = 60 # Increased default timeout for potentially large downloads
    )

    if (-not $script:eduSTARMCSession) {
        Write-Warning "[Utils] Get-eduPassStudentAccount: Not connected to eduSTAR MC. Attempting to connect."
        Connect-eduSTARMC -ErrorAction Stop # Attempt to connect; stop if fails
    }
    # Test-eduSTARMCSchoolNumber -SchoolNumberToTest $SchoolNumber # Validate format

    # Cache path setup (consider making CacheRootPath configurable or part of $Global:Config)
    $DefaultCacheRootPath = Join-Path -Path $env:TEMP -ChildPath "eduSTARMCAdministration" # Default to TEMP
    $StudentCacheFile = Join-Path -Path $DefaultCacheRootPath -ChildPath "$($SchoolNumber)-Students.xml"
    
    if (-not (Test-Path -Path $DefaultCacheRootPath)) {
        New-Item -Path $DefaultCacheRootPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $eduPassAccountsXml = @()

    if (-not $Force.IsPresent -and (Test-Path -Path $StudentCacheFile)) {
        $lastWrite = (Get-Item $StudentCacheFile).LastWriteTime
        $timespan = New-TimeSpan -Hours 23 # Cache validity period
        if (((Get-Date) - $lastWrite) -gt $timespan) {
            Write-Verbose "[Utils] Cache file [$StudentCacheFile] is older than 23 hours. Getting fresh data."
            Remove-Item -Path $StudentCacheFile -ErrorAction SilentlyContinue
        } else {
            Write-Verbose "[Utils] Loading student data from cache: $StudentCacheFile"
            try {
                $CacheContent = Get-Content -Path $StudentCacheFile -Raw -ErrorAction Stop
                $eduPassAccountsXml = ([xml]$CacheContent).ArrayOfStudent # Access the correct root based on XML structure
            } catch {
                Write-Warning "[Utils] Error reading from cache [$StudentCacheFile]: $($_.Exception.Message). Will fetch fresh data."
                $eduPassAccountsXml = $null
            }
        }
    }

    if($null -eq $eduPassAccountsXml -or $Force.IsPresent) {
        Write-Verbose "[Utils] Fetching fresh student data from eduSTAR MC for school $SchoolNumber."
        Write-Host "[Utils] Please wait, retrieving student data from eduSTAR MC... This can take a few minutes." -ForegroundColor Yellow
        
        $Uri = ("https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetStudents/{0}/FULL" -f $SchoolNumber)
        try {
            $RequestXml = Invoke-RestMethod -Uri $Uri -Method Get -WebSession $script:eduSTARMCSession -ContentType "application/xml" -TimeoutSec $Timeout -ErrorAction Stop
            $eduPassAccountsXml = ([xml]$RequestXml).ArrayOfStudent # Access the correct root
            
            # Save the XML file to cache
            if ($eduPassAccountsXml) { # Check if data was actually retrieved
                 # Ensure directory exists before saving
                if (-not (Test-Path -Path (Split-Path $StudentCacheFile))) {
                    New-Item -ItemType Directory -Path (Split-Path $StudentCacheFile) -Force | Out-Null
                }
                ([xml]$RequestXml).Save($StudentCacheFile) # Save the original XML document
                Write-Verbose "[Utils] Student data cached to: $StudentCacheFile"
            } else {
                Write-Warning "[Utils] No student data returned from API for school $SchoolNumber."
            }
        } catch {
            throw "[Utils] Failed to retrieve student data for school $SchoolNumber from API: $($_.Exception.Message) - URI: $Uri"
        }
    }

    if (-not $eduPassAccountsXml) {
        Write-Warning "[Utils] No student accounts found or retrieved for school $SchoolNumber."
        return @() # Return empty array
    }

    # Process and map fields
    $Result = $eduPassAccountsXml.Student | ForEach-Object {
        [PSCustomObject]@{
            Username          = $_._login
            LastName          = $_._lastName
            FirstName         = $_._firstName
            YearLevel         = $_._desc
            Class             = $_._class
            Email             = "$($_._login)@schools.vic.edu.au" 
            DistinguishedName = $_._dn
            # Add any other fields you need from the XML structure
            # Example: Status = $_._status if it exists
        }
    } | Sort-Object -Property Username

    if ([string]::IsNullOrEmpty($Identity)) {
        Write-Verbose "[Utils] Returning $($Result.Count) students for school $SchoolNumber."
        return $Result
    } else {
        Write-Verbose "[Utils] Filtering for student '$Identity'..."
        $FilteredResult = $Result | Where-Object {$_.Username -eq $Identity}
        Write-Verbose "[Utils] Found $($FilteredResult.Count) matching students for '$Identity'."
        return $FilteredResult
    }
}

function Set-eduPassCloudServiceStatus {
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Identity, # Usernames
        [Parameter(Mandatory=$true)]
        [string]$SchoolNumber,
        [ValidateNotNullOrEmpty()]
        [ValidateSet('staff', 'student', 'serviceaccount')]
        [string]$AccountType,
        [ValidateNotNullOrEmpty()]
        [ValidateSet('o365', 'intune', 'google', 'yammer', 'lynda', 'stile' , 'webex')] # Keep this list updated
        [string]$Service,
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Enabled', 'Disabled')]
        [string]$Status,
        [int]$Timeout = 60
    )
    if (-not $script:eduSTARMCSession) { Connect-eduSTARMC -ErrorAction Stop }
    Test-eduSTARMCSchoolNumber -SchoolNumberToTest $SchoolNumber

    $DNarray = @()
    Write-Verbose "[Utils] Setting cloud service status for $($Identity.Count) users. Service: $Service, Status: $Status"

    ForEach ($userLogin in $Identity) {
        $Account = Get-eduPassStudentAccount -SchoolNumber $SchoolNumber -Identity $userLogin -ErrorAction SilentlyContinue # Get full account details
        if ($Account -and $Account.DistinguishedName) {
            $DNarray += $Account.DistinguishedName
            Write-Verbose "[Utils]   Found DN for $($userLogin): $($Account.DistinguishedName)"
        } else {
            Write-Warning "[Utils]   Could not find account or DN for user '$userLogin' in school $SchoolNumber. Skipping."
        }
    }
   
    if ($DNarray.Count -eq 0) {
        Write-Warning "[Utils] No valid accounts found to update cloud service status."
        return $null # Or an empty array indicating no action
    }

    $WebRequestBody = @{
        _accountType = $AccountType
        _dns         = $DNarray # API expects an array of DNs
        _schoolId    = $SchoolNumber
        _property    = $Service
    } | ConvertTo-Json

    $endpointAction = if ($Status -eq 'Enabled') { "SetO365" } else { "UnsetO365" } # API endpoint name might vary based on service
    $Uri = "https://apps.edustar.vic.edu.au/edustarmc/api/MC/$endpointAction"
    # Write-Verbose "[Utils] Calling API: $Uri with body: $WebRequestBody"
    
    $OverallResult = @()
    try {
        # The API might return a success/failure per DN or a general status. Adjust parsing as needed.
        Invoke-RestMethod -Uri $Uri -WebSession $script:eduSTARMCSession -Body $WebRequestBody -Method Post -TimeoutSec $Timeout -ContentType "application/json" -ErrorAction Stop
        

        # Assuming API call applies to all DNs submitted if no error. Construct success result.
        ForEach($userLogin in $Identity) { # Iterate over original identities to build result
            $AccountInfo = Get-eduPassStudentAccount -SchoolNumber $SchoolNumber -Identity $userLogin # Re-fetch to get names if needed
            $OverallResult += [PSCustomObject]@{
                Username = $userLogin
                Name     = if ($AccountInfo) {"$($AccountInfo.FirstName) $($AccountInfo.LastName)"} else {"N/A"}
                Service  = $Service
                Status   = $Status
                Result   = "Success" # Assuming success if no error from API for the batch
            }
        }
    } catch {
        Write-Warning "[Utils] Failed to update cloud service for some/all users. Service: $Service. Error: $($_.Exception.Message)"
        # Construct failure result for all attempted users in this batch
         ForEach($userLogin in $Identity) {
            $AccountInfo = Get-eduPassStudentAccount -SchoolNumber $SchoolNumber -Identity $userLogin
            $OverallResult += [PSCustomObject]@{
                Username = $userLogin
                Name     = if ($AccountInfo) {"$($AccountInfo.FirstName) $($AccountInfo.LastName)"} else {"N/A"}
                Service  = $Service
                Status   = $Status
                Result   = "Failed: $($_.Exception.Message)"
            }
        }
    }
    return $OverallResult
}

function Set-eduPassStudentAccountPassword {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Identity, # Username
        [Parameter(Mandatory=$true)]
        [string]$SchoolNumber,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password # The new password
    )
    if (-not $script:eduSTARMCSession) { Connect-eduSTARMC -ErrorAction Stop }
    Test-eduSTARMCSchoolNumber -SchoolNumberToTest $SchoolNumber
        
    $Account = Get-eduPassStudentAccount -Identity $Identity -SchoolNumber $SchoolNumber -ErrorAction Stop
    if (-not $Account) {
        throw "[Utils] Student account '$Identity' not found in school '$SchoolNumber'."
    }
    if ([string]::IsNullOrEmpty($Account.DistinguishedName)) {
        throw "[Utils] DistinguishedName not found for student '$Identity'. Cannot reset password."
    }
  
    Write-Verbose "[Utils] Setting password for student '$Identity' (DN: $($Account.DistinguishedName)) in school $SchoolNumber."

    # Password is now passed directly, no need for DinoPass here.
    # The main script calls Get-RandomPasswordSimple then passes it here.

    $Uri = "https://apps.edustar.vic.edu.au/edustarmc/api/MC/ResetStudentPwd"
    $Parameters = @{
        dn       = $Account.DistinguishedName
        newPass  = $Password # Use the provided password
        schoolId = $SchoolNumber
    } | ConvertTo-Json

    try {
        # API might not return detailed content on success, check status or for errors.
        Invoke-RestMethod -Uri $Uri -WebSession $script:eduSTARMCSession -Method Post -Body $Parameters -ContentType "application/json" -ErrorAction Stop
        
        $Result = [PSCustomObject]@{
                Name     = ("$($Account.FirstName) $($Account.LastName)")
                Username = $Account.Username
                Password = "********" # Do not return or log the actual password
                Status   = "Password set successfully (API call succeeded)"
            }
        
            #Write-Verbose "[Utils] Password reset API call successful for '$Identity'."
        return $Result
    }
    catch {
        $errorMessage = "[Utils] Unable to set password for '$($Account.Username)'. Detail: $($_.Exception.Message)"
        # Check for specific error messages from the API if possible
        if ($_.Exception.Response) {
            $responseStream = $_.Exception.Response.GetResponseStream()
            $streamReader = New-Object System.IO.StreamReader($responseStream)
            $errorBody = $streamReader.ReadToEnd()
            $errorMessage += " API Response: $errorBody"
            $streamReader.Close()
            $responseStream.Close()
        }
        throw $errorMessage
    }
}
#endregion Student Account Functions

#region List Comparison and Data Utilities
function Compare-StudentLists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$DownloadedStudents, # Array of PSCustomObjects
        [Parameter(Mandatory = $true)]
        [array]$MasterStudents      # Array of PSCustomObjects
    )
    Write-Verbose "[Utils] Comparing student lists. Downloaded: $($DownloadedStudents.Count), Current: $($MasterStudents.Count)"

    $downloadedUsernames = $DownloadedStudents | Select-Object -ExpandProperty Username -Unique
    $masterUsernames = $MasterStudents | Select-Object -ExpandProperty Username -Unique

    $newStudentUsernames = Compare-Object -ReferenceObject $masterUsernames -DifferenceObject $downloadedUsernames -PassThru | Where-Object { $_ -in $downloadedUsernames }
    $departedStudentUsernames = Compare-Object -ReferenceObject $downloadedUsernames -DifferenceObject $masterUsernames -PassThru | Where-Object { $_ -in $masterUsernames }

    $newStudentList = $DownloadedStudents | Where-Object { $_.Username -in $newStudentUsernames }
    $departedStudentList = $MasterStudents | Where-Object { $_.Username -in $departedStudentUsernames }
    # Existing students are those in master who are not in departed list
    $existingStudentList = $MasterStudents | Where-Object { $_.Username -notin $departedStudentUsernames }


    Write-Verbose "Found $($newStudentList.Count) new students."
    Write-Verbose "Found $($departedStudentList.Count) departed students."
    Write-Verbose "Found $($existingStudentList.Count) existing students to retain."

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
    Write-Verbose "[Utils] Generated random password pattern: $word.$numbers"
    return $password
}

# Test-DuplicationEntry was in the original utils but not directly used by the main script flow.
# It's a good utility to have, so keeping it.
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
    Write-Verbose "[Utils] No duplicate usernames found in the provided data."
    return $false
}

# Get-StudentAccountFullList is the main function called by Process-DailyStudentUpdates.ps1
# to fetch the student list. It's an orchestrator within this utils script.
function Get-StudentAccountFullList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SchoolNumber, # e.g. "8881"
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,   # e.g., "$BaseDir/Output/DailyDownloads"
        [string]$FileNamePrefix = "DownloadedStudentList" # e.g., "DownloadedStudentList"
    )
    Write-Verbose "[Utils] Get-StudentAccountFullList called. School: $SchoolNumber, OutputPath: $OutputPath, Prefix: $FileNamePrefix"

    # Ensure connection (Connect-eduSTARMC handles Test-Proxy and Set-eMCCredentials)
    # It will throw if connection fails, which the main script will catch.
    if (-not $script:eduSTARMCSession) {
        Write-Verbose "[Utils] No active eduSTAR MC session. Attempting to connect..."
         $connection = Connect-eduSTARMC # This will throw on failure
        Write-Verbose "[Utils] Connection to eduSTAR MC established/verified. $($connection.Connected)"
    } else {
        Write-Verbose "[Utils] Existing eduSTAR MC session found."
    }

    if (-not $SchoolNumber) {
        Write-Warning "[Utils] No school number provided. Attempting to auto-detect..."
        $SchoolNumber = Set-eduSTARMCSchool # This will set the global variable
        Write-Verbose "[Utils] Auto-detected school number: $SchoolNumber"
        if (-not $SchoolNumber) {
            throw "[Utils] Failed to auto-detect school number. Exiting function."
        }
    }

    # Set the school context for the session if your API calls depend on it implicitly,
    # though Get-eduPassStudentAccount takes SchoolNumber explicitly.
    # Set-eduSTARMCSchool -SchoolNumber $SchoolNumber # This sets a global var, might not be needed if all funcs take SchoolNumber
    # Write-Verbose "[Utils] School context set to: $SchoolNumber (via Set-eduSTARMCSchool)"

    $dateString = Get-Date -Format "yyyyMMdd" # Use consistent date format
    $fileName = "${FileNamePrefix}_${dateString}.csv"
    $fullFilePath = Join-Path -Path $OutputPath -ChildPath $fileName

    if (-Not (Test-Path -Path $OutputPath)) {
        try {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            Write-Verbose "[Utils] Created output directory for download: $OutputPath"
        } catch {
            throw "[Utils] Failed to create output directory $($OutputPath): $($_.Exception.Message)"
        }
    }

    $students = Get-eduPassStudentAccount -SchoolNumber $SchoolNumber -Force    # Use -Force to always get fresh data for the daily run
                                                    # Or remove -Force to use caching as per Get-eduPassStudentAccount logic
   if ($null -eq $students) {
        Write-Host "Debug Info:"
        Write-Host "Session exists: $($null -ne $eduSTARMCSession)"
        Write-Host "School number: $global:SelectedSchool"
        Write-Host "Connection status: $($connection.Connected)"
        Write-Warning "No student data available. Exiting function."
        return $null

        try {
            $apiUrl = "https://apps.edustar.vic.edu.au/edustarmc/api/MC/GetStudents/{0}/FULL" -f $SchoolNumber
        
            # Ensure the session variable is correctly named and used
            $rawResponse = Invoke-RestMethod -Uri $apiUrl -Method Get -WebSession $script:eduSTARMCSession -ContentType "application/xml"
            Write-Verbose "Raw response received from API: $($null -ne $rawResponse)"
        }
        catch {
            Write-Error "Failed to retrieve student data from API: $($_.Exception.Message)"
            Write-Error "Failed to get student account list from eduSTAR MC: $($_.Exception.Message)"
            # Detailed error information for debugging
            Write-Error "Status Code: $($_.Exception.Response.StatusCode)"
            Write-Error "Status Description: $($_.Exception.Response.StatusDescription)"
            # $errorResponse = $_.Exception.Response.GetResponseStream()
            # $streamReader = New-Object System.IO.StreamReader($errorResponse)
            # $errorBody = $streamReader.ReadToEnd()
            # Write-Error "Response Body: $errorBody"
        }
    } else {

        Write-Verbose "Student data received. Processing $($students.Count) records."
        
        $selectedData = $students | Select-Object Username, FirstName, LastName, YearLevel, Class, Email
        $sortedData = $selectedData | Sort-Object -Property Username

        # Convert to CSV and remove quotes
        $csvContent = $sortedData | ConvertTo-Csv -NoTypeInformation | ForEach-Object { $_ -replace '"', '' } | Where-Object { $_.Trim() -ne "" }
        
        $csvContent | Set-Content -Path $fullFilePath
        # Write-Host "[DEBUG] Student list successfully downloaded and saved to: $fullFilePath "
        return $fullFilePath
    }
}

# Email functions (Send-ProcessingNotification, Send-AdminErrorNotification) are unchanged in their core logic
# They use $Global:Config and $Global:ProcessingSummary which are globally available.

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
    Write-Log -Message "Step 8: Performing automated file cleanup..." -Level Infomation
    $Global:ProcessingSummary.AppendLine("8. Performing automated file cleanup...")

    $cleanupConfig = $Global:Config.CleanupSettings
    if (-not $cleanupConfig) {
        Write-Warning "[Utils] Cleanup settings not found in configuration. Skipping cleanup."
        $Global:ProcessingSummary.AppendLine("8. Cleanup settings not found in configuration. Skipping cleanup.") | Out-Null
        return
    }
    if (-not $cleanupConfig.Enabled) {
        Write-Verbose "[Utils] Cleanup is disabled in configuration. Skipping cleanup." -Level Information
        $Global:ProcessingSummary.AppendLine("8. Cleanup is disabled in configuration. Skipping cleanup.") | Out-Null
        return
    }

    $today = Get-Date
    $runDay = $cleanupConfig.RunOnDayOfWeek
    if ($today.DayOfWeek -ne $runDay) {
        Write-Verbose "[Utils] Today is not the scheduled cleanup day ($runDay). Skipping scheduled file cleanup." -Level Information
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
#endregion List Comparison and Data Utilities

# Export functions if this were a .psm1 module
# Export-ModuleMember -Function Get-StudentAccountFullList, Compare-StudentLists, Get-RandomPasswordSimple, Set-eduPassStudentAccountPassword, Set-eduPassCloudServiceStatus, Connect-eduSTARMC, Disconnect-eduSTARMC, Test-DuplicationEntry, Set-eMCCredentials
# For a .ps1 imported with Import-Module, all functions are typically available.

Write-Verbose "[Utils] StudentDataUtils.psm1 loaded."
