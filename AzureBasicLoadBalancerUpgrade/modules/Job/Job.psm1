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

    $job = $null
    log -Message "[WaitJob] Checking Job Id: $($JobId)"

    while ($job = get-job -Id $JobId) {
        $jobInfo = (receive-job -Id $JobId)

        if (!$Message) {
            $Message = $job.Name
        }

        if ($jobInfo) {
            log -Message "[WaitJob] Receiving Job: $($jobInfo)"
        }
        else {
            log -Message "[WaitJob] Receiving Job No Update: $($job | ConvertTo-Json -Depth 1 -WarningAction SilentlyContinue)" -Severity "Debug"
        }

        $status = "State:$($job.State) Minutes Executing:$(((get-date) - $job.PSBeginTime).Minutes)"
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
