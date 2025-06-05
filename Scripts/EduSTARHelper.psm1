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

Export-ModuleMember -Function Set-eMCCredentials, Test-Proxy, Connect-eduSTARMC, Disconnect-eduSTARMC, Set-eduSTARMCSchool, Get-eduSTARMCSchool, Select-eduSTARMCSchool, Test-eduSTARMCSchoolNumber, Get-eduPassStudentAccount, Set-eduPassCloudServiceStatus, Set-eduPassStudentAccountPassword, Get-StudentAccountFullList

Write-Verbose "[Utils] eduSTARHelper module loaded successfully."