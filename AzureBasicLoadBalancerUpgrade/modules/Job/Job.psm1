Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

function StartIPMonitorJob {
    param(
        [Parameter(Mandatory = $True, Position = 0)]
        [hashtable]$IpAddressPorts
    )
    # cloud shell does not have test-netconnection. using tcpclient
    $tcpJob = $null
    if ($IpAddressPorts) {
        $tcpJob = Start-Job -ScriptBlock {
            param([hashtable]$IpAddressPorts)
            $WarningPreference = $ProgressPreference = 'SilentlyContinue'

            while ($true) {
                $tcpClient = $null
                try {
                    Start-Sleep -Seconds 5
                    $tcpTestSucceeded = $true
                    # check all ip addresses
                    foreach ($ipAddressPort in $IpAddressPorts.GetEnumerator()) {
                        $portTestSucceeded = $false
                        # checak all ports for each ip address
                        foreach ($port in $ipAddressPort.Value) {
                            $tcpClient = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
                            $tcpClient.SendTimeout = $tcpClient.ReceiveTimeout = 1000
                            [IAsyncResult]$asyncResult = $tcpClient.BeginConnect($ipAddressPort.Key, $port, $null, $null)

                            if (!$asyncResult.AsyncWaitHandle.WaitOne(1000, $false)) {
                                $portTestSucceeded = $false
                            }
                            else {
                                $portTestSucceeded = $portTestSucceeded -or $tcpClient.Connected
                            }
                            Write-Verbose "[CreateIPMonitorJob] tcpClient: computer:$($ipAddressPort.Key) port:$($port) $portTestSucceeded"
                            $tcpClient.Dispose()
                        }
                        $tcpTestSucceeded = $tcpTestSucceeded -and $portTestSucceeded
                    }
                    Write-Output $tcpTestSucceeded
                }
                catch {
                    Write-Verbose "[CreateIPMonitorJob] exception:$($PSItem)"
                }
                finally {
                    if ($tcpClient) {
                        $tcpClient.Dispose()
                    }
                }
            }
        } -ArgumentList @($IpAddressPorts)
    }
    return $tcpJob
}

function RemoveJob {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$JobId
    )

    log -Message "[RemoveJob] Removing Job Id: $($JobId)"
    if (Get-Job -Id $JobId) {
        Remove-Job -Id $JobId -Force
        log -Message "[RemoveJob] Job Removed: $($JobId)"
    }
    else {
        log -Message "[RemoveJob] Job Id Not Found: $($JobId)" -Severity "Warning"
    }
}

function WaitJob {
    [CmdletBinding()]
    param(
        [Parameter(Position = 1)]
        [string]$Message,

        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$JobId
    )

    $job = $null
    $percentAvailable = 0
    $publicIpInfo = ''
    $samples = 1
    $status = ''
    $tcpTestLastResult = $null
    $tcpTestSucceeded = $false
    $trueResults = 0

    log -Message "[WaitJob] Checking Job Id: $($JobId)"
    $tcpJob = StartIPMonitorJob -IpAddressPorts $global:PublicIps

    while ($job = get-job -Id $JobId) {
        $jobInfo = (receive-job -Id $JobId)

        if (!$Message) {
            $Message = $job.Name
        }

        if ($jobInfo) {
            log -Message "[WaitJob] Receiving Job: $($jobInfo)"
        }
        elseif ($DebugPreference -ieq 'Continue') {
            log -Message "[WaitJob] Receiving Job No Update: $($job | ConvertTo-Json -Depth 1 -WarningAction SilentlyContinue)" -Severity "Debug"
        }

        if ($global:PublicIps -and (Get-Job -id $tcpJob.Id)) {
            $tcpTestSucceeded = @((Receive-Job -Id $tcpJob.Id))[-1]
            if (![string]::IsNullOrEmpty($tcpTestSucceeded)) {
                $tcpTestLastResult = $tcpTestSucceeded
                if ($tcpTestLastResult) {
                    $trueResults++
                }
                $percentAvailable = [Math]::Round(($trueResults / $samples++) * 100)
            }
            else {
                $tcpTestSucceeded = $tcpTestLastResult
            }

            $publicIpInfo = "IP Avail:$tcpTestSucceeded ($percentAvailable% Total Avail)"
        }

        $executionTime = ((get-date) - $job.PSBeginTime).Minutes
        $status = "$publicIpInfo Minutes Executing:$executionTime State:$($job.State)"
        Write-Progress -Activity $Message -id 0 -Status $status

        if ($job.State -ine "Running") {
            log -Message "[WaitJob] Job Not Running: $($job)"

            if ($job.State -imatch "fail" -or $job.StatusMessage -imatch "fail") {
                log -Message "[WaitJob] Job Failed: $($job)" -Severity "Error"
            }

            RemoveJob -JobId $JobId
            Write-Progress -Activity 'Complete' -id 0 -Completed
            break
        }

        Start-Sleep -Seconds 1
    }

    log -Message "[WaitJob] Job Complete: $status"

    if ($tcpJob) {
        RemoveJob -JobId $tcpJob.Id
    }
}

Export-ModuleMember -Function WaitJob
