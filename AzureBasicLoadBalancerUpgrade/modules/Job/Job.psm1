Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

function CreateIPMonitorJob {
    if ($global:PublicIps) {
        $tcpJob = Start-Job -ScriptBlock {
            param($pips)
            $ProgressPreference = 'SilentlyContinue'
            $WarningPreference = 'SilentlyContinue'
            while ($true) {
                try {
                    Start-Sleep -Seconds 10
                    $tcpTestSucceeded = $true
                    foreach ($pip in $pips.GetEnumerator()) {
                        $tcpClient = [Net.Sockets.TcpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
                        $tcpClient.ReceiveTimeout = 1000
                        $tcpClient.SendTimeout = 1000
                        $tcpClient.Connect($pip.Key, $pip.Value[0])
                        $tcpTestSucceeded = $tcpTestSucceeded -and $tcpClient.Connected
                        Write-Verbose "tcpClient: computer:$($pip.Key) port:$($pip.Value[0])`n$($tcpClient | convertto-json -Depth 1 -WarningAction SilentlyContinue)"

                        if ($tcpClient.Connected) {
                            $tcpClient.Close()
                        }
                    }

                    Write-Output $tcpTestSucceeded
                }
                catch {
                    Write-Verbose "exception:$($_)"
                }
                finally {
                    $tcpClient.Dispose()
                }
            }
        } -ArgumentList @($global:PublicIps)
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

    $tcpTestSucceeded = $null
    $job = $null
    $tcpTestLastResult = $null
    $publicIpInfo = ''

    log -Message "[WaitJob] Checking Job Id: $($JobId)"

    $tcpJob = CreateIPMonitorJob

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
