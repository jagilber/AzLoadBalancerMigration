Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")

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

    if ($global:PublicIps) {
        $tcpJob = Start-Job -ScriptBlock {
            param($pips)
            $ProgressPreference = 'SilentlyContinue'
            $WarningPreference = 'SilentlyContinue'
            while ($true) {
                $tcpTestSucceeded = $true
                foreach ($pip in $pips.GetEnumerator()) {
                    Write-Verbose "(Test-NetConnection -ComputerName $($pip.Key.IpAddress) -Port $($pip.Value[0])).TcpTestSucceeded"
                    $tcpTestSucceeded = $tcpTestSucceeded -and (Test-NetConnection -ComputerName $pip.Key -Port $pip.Value[0]).TcpTestSucceeded
                }
                Write-Output $tcpTestSucceeded
                Start-Sleep -seconds 1
            }
        } -ArgumentList @($global:PublicIps)
    }

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
