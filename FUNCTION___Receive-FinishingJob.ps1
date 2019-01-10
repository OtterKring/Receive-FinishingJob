function Receive-FinishingJob {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        $Job = $null,
        [Parameter()]
        [int32]$Throttle = 100,
        [int32]$TimeoutSeconds = 120,
        [switch]$NoCleanUp,
        [switch]$CleanAll,
        [switch]$Quiet
    )
    
    begin {
        ### VARIABLES ##################################
        [System.Collections.ArrayList]$AllJobs = @()
        [int32]$TotalJobCount = 0
        [int32]$JobCount = 0

        ### FUNCTIONS ##################################

        ## Get-ReceivableJobs : different filters for jobs, just to make the later code more readable
        function Get-ReceivableJobs {
        param(
            [Parameter(Mandatory)]
            $Jobs,
            [Parameter()]
            [int16]$Timeout,
            [switch]$IncludeRunning
        )
            if (-not($IncludeRunning)) {
                $Jobs | Get-Job | Where-Object {$_.State -eq 'Completed' -and $_.HasMoreData}
            } else {
                if (-not($Timeout)) {
                    $Jobs | Get-Job | Where-Object {$_.State -eq 'Running' -or ($_.State -eq 'Completed' -and $_.HasMoreData)}
                } else {
                    $Jobs | Get-Job | Where-Object {($_.State -eq 'Running' -and $_.PSBeginTime -gt (Get-Date).AddSeconds(-$Timeout)) -or ($_.State -eq 'Completed' -and $_.HasMoreData)}
                }
            }
        }
        ################################################

    }
    
    process {

        # collect incoming jobs
        $null = $AllJobs.Add($Job)

        # if there are REALLY quick jobs, get them, while the pipe is still running (stream)
        $CompletedJobs = Get-ReceivableJobs $AllJobs
        if ($CompletedJobs) {
            $JobCount = $JobCount + $CompletedJobs.Count
            if (-not($Quiet)) {
                Write-Progress -Activity 'Receiving Jobs...' -CurrentOperation "Received $JobCount of $($AllJobs.Count) piped jobs" -PercentComplete ($JobCount * 100 / $AllJobs.Count)
            }    
            $CompletedJobs | Receive-Job        
        }

    }
    
    end {

        # only do something, if the pipe delivered data...
        if ($AllJobs) {

            $TotalJobCount = $AllJobs.Count
            $ReceivableJobs = Get-ReceivableJobs -Jobs $AllJobs -IncludeRunning
        
            # if there are cunning jobs or completed jobs with data for retreival ...
            while ($ReceivableJobs) {

                # ... get only the completed ones ...
                $CompletedJobs = $ReceivableJobs | Where-Object {$_.State -eq "Completed" -and $_.HasMoreData}
                $CompletedJobCount = $CompletedJobs.Count
        
                # ... and if there are any, receive the data.
                if ($CompletedJobCount) {
                    $JobCount = $JobCount + $CompletedJobCount
                    if (-not($Quiet)) {
                        Write-Progress -Activity "Receiving Jobs (Timeout $TimeoutSeconds seconds)..." -CurrentOperation "Received $JobCount of $TotalJobCount total jobs" -PercentComplete ($JobCount * 100 / $TotalJobCount)
                    }
                    $CompletedJobs | Receive-Job
                }
        
                # customizable pause to reduce cpu time of this script.
                # longer pauses increase performance of local jobs
                Start-Sleep -Milliseconds $Throttle

                # Again get running and completed jobs with data, but sort those out which exceed the $TimeoutSeconds parameter
                $ReceivableJobs = Get-ReceivableJobs -Jobs $AllJobs -Timeout $TimeoutSeconds -IncludeRunning
            }
        
            # final statistics
            if (-not($Quiet)) {

                Write-Progress -Activity 'Finished' -Completed

                $FinalJobs = $AllJobs | Get-Job

                $OvertimeJobs = ($FinalJobs | Where-Object {$_.PSBeginTime -le (Get-Date).AddSeconds(-$TimeoutSeconds) -and ($_.State -eq 'Running' -or ($_.State -eq 'Completed' -and $_.HasMoreData))}).Count
                if ($OvertimeJobs) {Write-Host "$OvertimeJobs Jobs exceeded $TimeoutSeconds seconds timeout."}

                $FailedJobs = ($FinalJobs | Where-Object {$_.State -eq 'Failed'}).Count
                if ($FailedJobs) {Write-Host "$FailedJobs Jobs failed."}                

                $CompletedJobs = $FinalJobs | Where-Object {$_.State -eq 'Completed' -and -not($_.HasMoreData)}
                if ($CompletedJobs) {Write-Host "$($CompletedJobs.Count) Jobs completed."}

            }

            # cleanup as requested
            # DEFAULT: all completed jobs with no pending data will be remove, the rest stays for manual verification
            if (-not($NoCleanUp)) {

                if ($CleanAll) {
                    $AllJobs | Remove-Job -Force
                } else {
                    $CompletedJobs | Remove-Job -Force
                }

            }

        }
        
    }
}