Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

function CreateIPMonitorJob {
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

                    foreach ($ipAddressPort in $IpAddressPorts.GetEnumerator()) {
                        $tcpClient = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
                        $tcpClient.SendTimeout = $tcpClient.ReceiveTimeout = 1000
                        [IAsyncResult]$asyncResult = $tcpClient.BeginConnect($ipAddressPort.Key, $ipAddressPort.Value[0], $null, $null)
            
                        if (!$asyncResult.AsyncWaitHandle.WaitOne(1000, $false)) {
                            $tcpTestSucceeded = $false
                        }
                        else {
                            $tcpTestSucceeded = $tcpTestSucceeded -and $tcpClient.Connected
                        }
                        Write-Verbose "[CreateIPMonitorJob] tcpClient: computer:$($ipAddressPort.Key) port:$($ipAddressPort.Value[0])
                            $($tcpClient | convertto-json -Depth 1 -WarningAction SilentlyContinue)"
                    }
                    Write-Output $tcpTestSucceeded
                }
                catch {
                    Write-Verbose "[CreateIPMonitorJob] exception:$($_)"
                }
                finally {
                    if ($tcpClient) {
                        if ($tcpClient.Connected) {
                            $tcpClient.Close()
                        }
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
    $publicIpInfo = ''
    $tcpTestLastResult = $null
    $tcpTestSucceeded = $false

    log -Message "[WaitJob] Checking Job Id: $($JobId)"
    $tcpJob = CreateIPMonitorJob -IpAddressPorts $global:PublicIps

    while ($job = get-job -Id $JobId) {
        $jobInfo = (receive-job -Id $JobId)

        if (!$Message) {
            $Message = $job.Name
        }

        if ($jobInfo) {
            log -Message "[WaitJob] Receiving Job: $($jobInfo)"
        }
        else {
            log -Message "[WaitJob] Receiving Job No Update: $($job | ConvertTo-Json -Depth 1 -WarningAction SilentlyContinue)" -Severity "Verbose"
        }

        if ($global:PublicIps) {
            $tcpTestSucceeded = @((Receive-Job -Id $tcpJob.Id))[-1]
            if (![string]::IsNullOrEmpty($tcpTestSucceeded)) {
                $tcpTestLastResult = $tcpTestSucceeded
            }
            else {
                $tcpTestSucceeded = $tcpTestLastResult
            }

            $publicIpInfo = "Public IP Available:$tcpTestSucceeded"
        }

        $status = "State:$($job.State) $publicIpInfo Execution Time:$(((get-date) - $job.PSBeginTime).Minutes) minutes"
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

    if ($tcpJob) {
        RemoveJob -JobId $tcpJob.Id
    }
}

Export-ModuleMember -Function WaitJob
