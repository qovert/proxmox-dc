# Configure-DNS.ps1
# DNS Configuration script for Active Directory Domain Controller
# Configures DNS forwarders, scavenging, and reverse lookup zones

param(
    [Parameter(Mandatory=$true)]
    [array]$DnsForwarders,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$DcIpPrefix
)

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logColor = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "INFO" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $logColor
}

try {
    Write-Log "Starting DNS configuration for domain: $DomainName"
    
    # Import DNS Server module
    Import-Module DnsServer -Force
    
    # Configure DNS forwarders
    Write-Log "Configuring DNS forwarders: $($DnsForwarders -join ', ')"
    
    # Remove existing forwarders
    $existingForwarders = Get-DnsServerForwarder
    if ($existingForwarders) {
        Remove-DnsServerForwarder -IPAddress $existingForwarders.IPAddress -Force
        Write-Log "Removed existing DNS forwarders"
    }
    
    # Add new forwarders
    foreach ($forwarder in $DnsForwarders) {
        if ($forwarder -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
            Add-DnsServerForwarder -IPAddress $forwarder
            Write-Log "Added DNS forwarder: $forwarder"
        } else {
            Write-Log "Invalid IP address format: $forwarder" "WARNING"
        }
    }
    
    # Configure DNS scavenging
    Write-Log "Configuring DNS scavenging"
    Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00
    Set-DnsServerZoneAging -Name $DomainName -Aging $true -RefreshInterval 7.00:00:00 -NoRefreshInterval 7.00:00:00
    
    # Create reverse lookup zones
    Write-Log "Creating reverse lookup zone for network: $DcIpPrefix.0/24"
    $networkId = "$DcIpPrefix.0/24"
    $ipParts = $DcIpPrefix.Split('.')
    $reverseLookupZone = "$($ipParts[2]).$($ipParts[1]).$($ipParts[0]).in-addr.arpa"
    
    try {
        $zone = Get-DnsServerZone -Name $reverseLookupZone -ErrorAction Stop
        Write-Log "Reverse lookup zone already exists: $reverseLookupZone"
    } catch {
        Add-DnsServerPrimaryZone -NetworkId $networkId -ReplicationScope Domain
        Write-Log "Created reverse lookup zone: $reverseLookupZone"
    }
    
    # Configure DNS server settings
    Write-Log "Configuring DNS server settings"
    Set-DnsServerSetting -EnableDnsSec $true -EnableDnsSecValidation $true
    Set-DnsServerRecursion -Enable $true -AdditionalTimeout 4 -RetryInterval 3 -Timeout 8
    Import-DnsServerRootHint
    
    # Test DNS functionality
    Write-Log "Testing DNS functionality"
    $testResults = @()
    
    try {
        $domainTest = Resolve-DnsName -Name $DomainName -ErrorAction Stop
        $testResults += "Domain resolution: PASS"
        Write-Log "Domain resolution test: PASS"
    } catch {
        $testResults += "Domain resolution: FAIL - $($_.Exception.Message)"
        Write-Log "Domain resolution test: FAIL" "ERROR"
    }
    
    try {
        $externalTest = Resolve-DnsName -Name "google.com" -ErrorAction Stop
        $testResults += "External resolution: PASS"
        Write-Log "External resolution test: PASS"
    } catch {
        $testResults += "External resolution: FAIL - $($_.Exception.Message)"
        Write-Log "External resolution test: FAIL" "ERROR"
    }
    
    # Log results
    foreach ($result in $testResults) {
        Write-Log $result
    }
    
    # Check for failures
    $failures = $testResults | Where-Object { $_ -like "*FAIL*" }
    if ($failures.Count -gt 0) {
        Write-Log "$($failures.Count) DNS tests failed" "ERROR"
        exit 1
    } else {
        Write-Log "All DNS tests passed"
        exit 0
    }
    
} catch {
    Write-Log "DNS configuration failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
