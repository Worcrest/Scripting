function AskForIPAddress($prompt) {
    $valid = $false
    while (-not $valid) {
        $ipAddress = Read-Host $prompt
        $valid = $ipAddress -match "\b(?:(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\b"
        if (-not $valid) {
            Write-Host "That does not appear to be a valid IP address.  Please try again."
        }
    }
    return $ipAddress
}

$agentlessPorts = @(135, 445, 3121, 5120)
$agentPorts = @(3121, 4155)

$inboundPorts = @(135, 445, 4155, 5120)
$outboundPorts = @(3121)
$distributionServerPorts = @(443, 445)

$agentlessTotalTests = $agentlessPorts.Count
$agentTotalTests = $agentPorts.Count
$agentlessTestsPassed = 0
$agentTestsPassed = 0

$ivantiServerIP = AskForIPAddress "Enter the IP address of the Ivanti server"
$answer = Read-Host "Is the distribution server hosted on the Ivanti VM? (y/n, Leave blank if unsure)"
if ($answer.Length -eq 0 -or ($answer.ToLower())[0] -eq 'y') {
    $distributionServerIP = $ivantiServerIP
} else {
    $distributionServerIP = AskForIPAddress "Enter the IP address of the Distribution Server"
}

function GetAgentStatus($port) {
    $status = "Unknown"
    $agent = $false
    $agentless = $false
    if ($agentPorts -contains $port) {
        $status = "Agent"
        $agent = $true
    } 
    if ($agentlessPorts -contains $port) {
        $status = "Agentless"
        $agentless = $true
    } 
    
    if ($agent -eq $true -and $agentless -eq $true) {
        $status = "Agent / Agentless"
    }
    return $status    
}
$allInboundFirewallRules = Get-NetFirewallRule -Enabled True -Direction Inbound
Write-Host ""
Write-Host "Checking firewall rules..."
foreach ($port in $inboundPorts) {
	$agentStatus = GetAgentStatus $port
    if ($inboundPorts -contains $port) {
        $rule = $allInboundFirewallRules | Where-Object { ($_ | Get-NetFirewallPortFilter).LocalPort -eq $port }
        if ($rule) {
            $isEnabled = $true
            Write-Host "    ${agentStatus} Port ${port}: Inbound - Enabled: ${isEnabled}" -ForegroundColor Green
            if ($agentStatus -eq "Agent" -or ($port -in ($agentPorts) -and $agentStatus -eq "Agent / Agentless")) {
                $agentTestsPassed++
            }
            if ($agentStatus -eq "Agentless" -or ($port -in ($agentlessPorts) -and $agentStatus -eq "Agent / Agentless")) {
                $agentlessTestsPassed++
            }
        } else {
            Write-Host "    ${agentStatus} Port ${port}: Inbound - No rule found" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Checking outbound connections to the Ivanti server at $ivantiServerIP..."
foreach ($port in $outboundPorts) {
    $agentStatus = GetAgentStatus $port
    #Write-Host "    Attempting connection to Ivanti Server on port ${port}..."
    $Global:ProgressPreference = 'SilentlyContinue'
    $result = Test-NetConnection -ComputerName $ivantiServerIP -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($result) {
        Write-Host "    Connection Successful! - ${agentStatus} Port ${port}: Outbound" -ForegroundColor Green
        if ($agentStatus -eq "Agent" -or ($port -in ($agentPorts) -and $agentStatus -eq "Agent / Agentless")) {
            $agentTestsPassed++
        }
        if ($agentStatus -eq "Agentless" -or ($port -in ($agentlessPorts) -and $agentStatus -eq "Agent / Agentless")) {
            $agentlessTestsPassed++
        }
    } else {
        Write-Host "    Failed to reach Ivanti Server! - ${agentStatus} Port ${port}: Outbound" -ForegroundColor Red
    }
    $Global:ProgressPreference = 'Continue'
}

if ($agentlessTestsPassed -eq $agentlessTotalTests) {
    $color = "Green"
} else {
    $color = "Yellow"
}
Write-Host ""
Write-Host "Checking distribution server ports (required for agents)..."
# Check Distribution Server ports separately
$distributionServerOK = $false
foreach ($port in $distributionServerPorts) {
    $Global:ProgressPreference = 'SilentlyContinue'
    $result = Test-NetConnection -ComputerName $distributionServerIP -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($port -eq 443) { 
        $protocol = "HTTPS"
    }
    if ($port -eq 445) {
        $protocol = "SMB"
    }
    if ($result) {
        Write-Host "    Connection Successful! - Successfully connected to Distribution Server using $protocol" -ForegroundColor Green
        $distributionServerOK = $true
    } else {
        Write-Host "    Connection Failed! - Could not connect using Distribution Server using $protocol." -ForegroundColor Yellow
    }
    $Global:ProgressPreference = 'Continue'    
}
Write-Host ""
Write-Host "${agentlessTestsPassed}/${agentlessTotalTests} Agentless tests passed successfully" -ForegroundColor $color
if ($agentTestsPassed -eq $agentTotalTests) {
    Write-Host "${agentTestsPassed}/${agentTotalTests} Agent tests passed successfully" -ForegroundColor Green
} else {
    Write-Host "${agentTestsPassed}/${agentTotalTests} Agent tests passed successfully" -ForegroundColor Yellow
}
if ($distributionServerOK) {
    Write-Host "At least one distribution server test passed successfully" -ForegroundColor Green
} else {
    Write-Host "No distribution server tests passed.  Agent-based patching will not work without a distribution server" -ForegroundColor Yellow
}

