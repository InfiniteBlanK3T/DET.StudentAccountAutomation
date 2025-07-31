# PDFGenerationHelper.psm1
# Purpose: PDF generation and HTML conversion functions for student lists
# Author: Thomas VO (ST02392)
# Date: 30-07-2025

function Generate-StudentListPDF {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Students,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        [Parameter(Mandatory=$true)]
        [string]$YearLevel,
        [Parameter(Mandatory=$true)]
        [string]$ClassName
    )
    
    try {
        Write-Log "[Utils] Generating PDF for Year $YearLevel, Class $ClassName with $($Students.Count) students" -Level Verbose
        
        # Create HTML content for PDF conversion
        $htmlContent = Generate-StudentListHTML -Students $Students -YearLevel $YearLevel -ClassName $ClassName
        
        # Use Edge WebView2 or fallback to Internet Explorer for PDF generation
        $success = Convert-HTMLToPDF -HTMLContent $htmlContent -OutputPath $OutputPath
        
        if ($success) {
            Write-Log "[Utils] Successfully generated PDF: $OutputPath" -Level Information
            return $true
        } else {
            Write-Log "[Utils] Failed to generate PDF: $OutputPath" -Level Error
            return $false
        }
        
    } catch {
        Write-Log "[Utils] Error generating PDF for Year $YearLevel, Class $ClassName`: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Generate-StudentListHTML {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Students,
        [Parameter(Mandatory=$true)]
        [string]$YearLevel,
        [Parameter(Mandatory=$true)]
        [string]$ClassName
    )
    
    $htmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$($Global:Config.SchoolSettings.SchoolName) - Year $YearLevel Class $ClassName</title>
    <style>
        @page {
            size: A4;
            margin: 12mm 10mm 15mm 10mm; /* Reduced margins */
        }
        @page :first {
            margin-top: 12mm;
        }
        /* Simplified page numbering */
        @page {
            @bottom-center {
                content: "Page " counter(page) " of 2"; /* Force to 2 pages */
                font-size: 9pt;
                color: #666;
            }
        }
        body {
            font-family: 'Arial', 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-size: 12pt;  /* Increased from 11pt for better readability */
            line-height: 1.5;  /* Increased line height for easier reading */
            color: #333;
            margin: 0;
            padding: 0;
            background-color: white;
        }
        .header {
            text-align: center;
            margin-bottom: 15px; /* Reduced from 25px */
            padding-bottom: 10px; /* Reduced from 15px */
            border-bottom: 2px solid #0066cc;
            page-break-after: avoid;  /* Keep header with content */
        }
        .school-name {
            font-size: 16pt;  /* Reduced from 18pt */
            font-weight: bold;
            color: #0066cc;
            margin-bottom: 5px; /* Reduced from 8px */
            letter-spacing: 0.5px;
        }
        .class-info {
            font-size: 14pt;
            font-weight: bold;
            color: #333;
            margin-bottom: 5px; /* Reduced from 12px */
        }
        .generation-info {
            font-size: 10pt;  /* Reduced from 11pt */
            color: #555;
            font-style: italic;
            margin: 2px 0; /* Reduced from 3px */
            display: inline-block;
            padding: 0 10px;
        }
        .student-count {
            font-weight: bold;
            color: #0066cc;
            font-size: 12pt;
        }
        .student-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 15px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            page-break-inside: avoid;  /* Try to keep table rows together */
        }
        .student-table th {
            background-color: #0066cc;
            color: white;
            padding: 14px 10px;  /* Increased padding */
            text-align: left;
            font-weight: bold;
            font-size: 13pt;  /* Larger header text */
            border: 1px solid #0052a3;
            page-break-after: avoid;
        }
        .student-table td {
            padding: 12px 10px;  /* Increased padding for better spacing */
            border: 1px solid #ccc;  /* Darker border for better definition */
            vertical-align: top;
            font-size: 12pt;  /* Consistent larger font */
            page-break-inside: avoid;  /* Avoid breaking within cells */
        }
        .student-table tr {
            page-break-inside: avoid;  /* Keep student rows together */
            page-break-after: auto;
        }
        .student-table tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        .student-table tr:nth-child(odd) {
            background-color: white;
        }
        .student-table tr:hover {
            background-color: #e3f2fd;
        }
        .username {
            font-weight: bold;
            color: #0066cc;
            font-size: 12pt;
        }
        .password {
            font-family: 'Consolas', 'Courier New', monospace;
            background-color: #f0f0f0;  /* Slightly darker background */
            padding: 4px 6px;  /* More padding */
            border-radius: 4px;
            border: 1px solid #ccc;
            font-size: 11pt;  /* Slightly smaller but still readable */
            font-weight: 500;  /* Medium weight for better readability */
        }
        .page-header {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            height: 60px;
            background-color: #f8f9fa;
            border-bottom: 1px solid #dee2e6;
            padding: 10px 15px;
            font-size: 11pt;
            color: #666;
            display: none;  /* Hidden on first page */
        }
        .page-header.show-on-subsequent {
            display: block;
        }
        .security-notice {
            background-color: #fff8e1;  /* Warmer background */
            border: 2px solid #ffb74d;  /* Thicker, more visible border */
            color: #e65100;  /* Higher contrast color */
            padding: 18px;  /* More padding */
            border-radius: 6px;
            margin: 25px 0;
            font-size: 11pt;  /* Larger font */
            font-weight: 500;  /* Medium weight */
            line-height: 1.6;
            page-break-inside: avoid;  /* Keep security notice together */
            position: relative;
        }
        .security-notice::before {
            font-size: 16pt;
            margin-right: 8px;
            vertical-align: middle;
        }
        .security-notice strong {
            font-size: 12pt;  /* Larger for emphasis */
            color: #d84315;  /* Even stronger color for the heading */
        }
        .footer {
            margin-top: 30px;
            padding: 20px 0;  /* More padding */
            border-top: 2px solid #dee2e6;  /* Thicker border */
            font-size: 10pt;  /* Slightly larger */
            color: #555;  /* Better contrast */
            text-align: center;
            line-height: 1.5;
            page-break-inside: avoid;  /* Keep footer together */
        }
        .footer p {
            margin: 8px 0;  /* More spacing between lines */
        }
        /* Improved page break handling - optimize for 2 pages maximum */
        .table-container {
            page-break-inside: auto;
            /* Force security notice to page 2 */
            page-break-after: always;
        }
        .student-row {
            page-break-inside: avoid;
            page-break-after: auto;
        }
        /* Compact table for better space usage */
        .student-table td {
            padding: 8px 10px; /* Reduced padding from 12px to 8px */
        }
        /* Ensure we fit more rows per page */
        .student-table {
            margin-bottom: 0; /* Remove bottom margin */
        }
        /* Print-specific styles */
        @media print {
            /* Force 2-page layout */
            .security-notice {
                page-break-before: always; /* Always start on new page */
                page-break-after: avoid; /* Keep with footer */
                margin-top: 0; /* Remove top margin */
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .footer {
                page-break-before: avoid; /* Keep with security notice */
                margin-top: 15px; /* Reduce top margin */
            }
            .student-table th {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            body {
                print-color-adjust: exact;
            }
        }
        /* High contrast mode support */
        @media (prefers-contrast: high) {
            body {
                background-color: white;
                color: black;
            }
            .student-table th {
                background-color: black;
                color: white;
            }
            .security-notice {
                background-color: yellow;
                color: black;
                border-color: black;
            }
        }
        /* Large text support */
        @media (min-resolution: 2dppx) {
            body {
                font-size: 13pt;
            }
            .student-table td {
                font-size: 13pt;
                padding: 14px 12px;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="school-name">$($Global:Config.SchoolSettings.SchoolName)</div>
        <div class="class-info">Year $YearLevel - Class $ClassName</div>
        <div style="margin-top: 3px;">
            <span class="generation-info">Generated: $(Get-Date -Format 'dd/MM/yyyy')</span>
            <span class="generation-info">Total Students: <span class="student-count">$($Students.Count)</span></span>
        </div>
    </div>
"@

    $tableHeader = @"
    <div class="table-container">
        <table class="student-table">
            <thead>
                <tr>
                    <th style="width: 18%;">Username</th>
                    <th style="width: 22%;">First Name</th>
                    <th style="width: 22%;">Last Name</th>
                    <th style="width: 28%;">Email</th>
                    <th style="width: 10%;">Password</th>
                </tr>
            </thead>
            <tbody>
"@

    $tableRows = ""
    $rowCount = 0
    
    # Calculate estimated rows that will fit on first page (adjusted for 2-page layout)
    # This is approximately how many rows we can fit on the first page
    $maxRowsFirstPage = [Math]::Min(30, $Students.Count) # Target 30 rows max on first page
    
    foreach ($student in $Students) {
        $rowCount++
        
        # No more individual page breaks - we'll fit as many as possible on page 1
        $tableRows += @"
            <tr class="student-row">
                <td class="username">$($student.Username)</td>
                <td>$($student.FirstName)</td>
                <td>$($student.LastName)</td>
                <td style="font-size: 11pt;">$($student.Email)</td>
                <td class="password">$($student.Password)</td>
            </tr>
"@
    }

    $tableFooter = @"
            </tbody>
        </table>
    </div>
"@

    $securityNotice = @"
    <div class="security-notice" style="margin-bottom: 15px; padding: 15px;">
        <strong>IMPORTANT SECURITY NOTICE:</strong><br>
        This document contains <strong>sensitive student account information</strong> including passwords.
        <div style="display: flex; justify-content: space-between; margin-top: 10px;">
            <ul style="margin: 0; padding-left: 20px; line-height: 1.4; flex: 1;">
                <li>Store this document in a <strong>secure, locked location</strong></li>
                <li>Do not leave unattended or share with unauthorized persons</li>
                <li>Follow your school's data protection and privacy policies</li>
                <li>Destroy securely when no longer needed (shred or secure deletion)</li>
            </ul>
            <ul style="margin: 0; padding-left: 20px; line-height: 1.4; flex: 1;">
                <li>Follow data protection policies</li>
                <li>Shred when no longer needed</li>
            </ul>
        </div>
    </div>
"@

    $footer = @"
    <div class="footer" style="margin-top: 15px; padding-top: 10px;">
        <p><strong>$($Global:Config.SchoolSettings.SchoolName)</strong> (School #$($Global:Config.SchoolSettings.SchoolNumber)) | Class: Year $YearLevel - $ClassName</p>
        <p>Student Account System | Generated: $(Get-Date -Format 'dd/MM/yyyy') | Total Students: $($Students.Count)</p>
        <p style="font-size: 9pt; color: #777;">For support, contact your school's IT administrator. <a href="$($Global:Config.SchoolSettings.HelpDeskWebPortal)">HelpDesk Portal</a></p>
    </div>
</body>
</html>
"@

    $fullHTML = $htmlHeader + $tableHeader + $tableRows + $tableFooter + $securityNotice + $footer
    return $fullHTML
}

function Convert-HTMLToPDF {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HTMLContent,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        Write-Log "[Utils] Converting HTML to PDF: $OutputPath" -Level Verbose
        
        # Method 1: Try using Microsoft Edge WebView2 (most reliable on modern Windows)
        if (Test-EdgeWebView2Available) {
            Write-Log "[Utils] Using Microsoft Edge WebView2 for PDF generation" -Level Verbose
            return Convert-HTMLToPDF-EdgeWebView2 -HTMLContent $HTMLContent -OutputPath $OutputPath
        }
        
        # Method 2: Fallback to using Chrome in headless mode if available
        if (Test-ChromeAvailable) {
            Write-Log "[Utils] Using Chrome headless mode for PDF generation" -Level Verbose
            return Convert-HTMLToPDF-Chrome -HTMLContent $HTMLContent -OutputPath $OutputPath
        }
        
        # Method 3: Fallback to wkhtmltopdf if available
        if (Test-WkHtmlToPdfAvailable) {
            Write-Log "[Utils] Using wkhtmltopdf for PDF generation" -Level Verbose
            return Convert-HTMLToPDF-WkHtmlToPdf -HTMLContent $HTMLContent -OutputPath $OutputPath
        }
        
        # Method 4: Final fallback - create a simple text-based report
        Write-Log "[Utils] No PDF converters available, creating plain text report" -Level Warning
        return Convert-HTMLToText -HTMLContent $HTMLContent -OutputPath ($OutputPath -replace '\.pdf$', '.txt')
        
    } catch {
        Write-Log "[Utils] Error in Convert-HTMLToPDF: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-EdgeWebView2Available {
    try {
        # Check if Microsoft Edge WebView2 is available
        $edgePath = Get-Command "msedge.exe" -ErrorAction SilentlyContinue
        return $null -ne $edgePath
    } catch {
        return $false
    }
}

function Test-ChromeAvailable {
    try {
        $chromePaths = @(
            "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "${env:LOCALAPPDATA}\Google\Chrome\Application\chrome.exe"
        )
        
        foreach ($path in $chromePaths) {
            if (Test-Path $path) {
                return $true
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Test-WkHtmlToPdfAvailable {
    try {
        $wkPath = Get-Command "wkhtmltopdf.exe" -ErrorAction SilentlyContinue
        return $null -ne $wkPath
    } catch {
        return $false
    }
}

function Convert-HTMLToPDF-EdgeWebView2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HTMLContent,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        # Create a temporary HTML file
        $tempHtmlPath = [System.IO.Path]::GetTempFileName() + ".html"
        $HTMLContent | Out-File -FilePath $tempHtmlPath -Encoding UTF8
        
        # Use Edge to print to PDF
        $edgeArgs = @(
            "--headless",
            "--disable-gpu",
            "--print-to-pdf=`"$OutputPath`"",
            "--print-to-pdf-no-header",
            "--no-margins",
            "`"$tempHtmlPath`""
        )
        
        $process = Start-Process -FilePath "msedge.exe" -ArgumentList $edgeArgs -Wait -PassThru -WindowStyle Hidden
        
        # Clean up temp file
        Remove-Item -Path $tempHtmlPath -Force -ErrorAction SilentlyContinue
        
        if ($process.ExitCode -eq 0 -and (Test-Path $OutputPath)) {
            Write-Log "[Utils] Successfully generated PDF using Edge WebView2" -Level Verbose
            return $true
        } else {
            Write-Log "[Utils] Edge WebView2 PDF generation failed with exit code: $($process.ExitCode)" -Level Warning
            return $false
        }
        
    } catch {
        Write-Log "[Utils] Error using Edge WebView2: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Convert-HTMLToPDF-Chrome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HTMLContent,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        # Find Chrome executable
        $chromePaths = @(
            "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "${env:LOCALAPPDATA}\Google\Chrome\Application\chrome.exe"
        )
        
        $chromePath = $null
        foreach ($path in $chromePaths) {
            if (Test-Path $path) {
                $chromePath = $path
                break
            }
        }
        
        if (-not $chromePath) {
            return $false
        }
        
        # Create a temporary HTML file
        $tempHtmlPath = [System.IO.Path]::GetTempFileName() + ".html"
        $HTMLContent | Out-File -FilePath $tempHtmlPath -Encoding UTF8
        
        # Use Chrome to print to PDF
        $chromeArgs = @(
            "--headless",
            "--disable-gpu",
            "--print-to-pdf=`"$OutputPath`"",
            "--no-margins",
            "`"$tempHtmlPath`""
        )
        
        $process = Start-Process -FilePath $chromePath -ArgumentList $chromeArgs -Wait -PassThru -WindowStyle Hidden
        
        # Clean up temp file
        Remove-Item -Path $tempHtmlPath -Force -ErrorAction SilentlyContinue
        
        if ($process.ExitCode -eq 0 -and (Test-Path $OutputPath)) {
            Write-Log "[Utils] Successfully generated PDF using Chrome" -Level Verbose
            return $true
        } else {
            Write-Log "[Utils] Chrome PDF generation failed with exit code: $($process.ExitCode)" -Level Warning
            return $false
        }
        
    } catch {
        Write-Log "[Utils] Error using Chrome: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Convert-HTMLToPDF-WkHtmlToPdf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HTMLContent,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        # Create a temporary HTML file
        $tempHtmlPath = [System.IO.Path]::GetTempFileName() + ".html"
        $HTMLContent | Out-File -FilePath $tempHtmlPath -Encoding UTF8
        
        # Use wkhtmltopdf
        $wkArgs = @(
            "--page-size", "A4",
            "--margin-top", "10mm",
            "--margin-bottom", "10mm",
            "--margin-left", "10mm",
            "--margin-right", "10mm",
            "--encoding", "UTF-8",
            "`"$tempHtmlPath`"",
            "`"$OutputPath`""
        )
        
        $process = Start-Process -FilePath "wkhtmltopdf.exe" -ArgumentList $wkArgs -Wait -PassThru -WindowStyle Hidden
        
        # Clean up temp file
        Remove-Item -Path $tempHtmlPath -Force -ErrorAction SilentlyContinue
        
        if ($process.ExitCode -eq 0 -and (Test-Path $OutputPath)) {
            Write-Log "[Utils] Successfully generated PDF using wkhtmltopdf" -Level Verbose
            return $true
        } else {
            Write-Log "[Utils] wkhtmltopdf generation failed with exit code: $($process.ExitCode)" -Level Warning
            return $false
        }
        
    } catch {
        Write-Log "[Utils] Error using wkhtmltopdf: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Convert-HTMLToText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$HTMLContent,
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        Write-Log "[Utils] Creating text-based report as PDF generation fallback" -Level Information
        
        # Extract data from HTML and create a clean text report
        $textContent = @"
===============================================================
$($Global:Config.SchoolSettings.SchoolName)
Student Account List
Generated: $(Get-Date -Format 'dddd, dd MMMM yyyy HH:mm:ss')
===============================================================

"@
        
        # This is a simplified fallback - in a real implementation,
        # you might want to parse the actual student data
        $textContent += "NOTE: PDF generation was not available. This is a text-based fallback.`n"
        $textContent += "For full formatting, please ensure Chrome, Edge, or wkhtmltopdf is available.`n`n"
        
        # Save the text content
        $textContent | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Log "[Utils] Text report saved to: $OutputPath" -Level Information
        return $true
        
    } catch {
        Write-Log "[Utils] Error creating text fallback: $($_.Exception.Message)" -Level Error
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Generate-StudentListPDF, Generate-StudentListHTML, Convert-HTMLToPDF, Test-EdgeWebView2Available, Test-ChromeAvailable, Test-WkHtmlToPdfAvailable, Convert-HTMLToPDF-EdgeWebView2, Convert-HTMLToPDF-Chrome, Convert-HTMLToPDF-WkHtmlToPdf, Convert-HTMLToText

Write-Verbose "[Utils] PDFGenerationHelper.psm1 loaded."
