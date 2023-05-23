# Receive-FinishingJob
A function to include into your multi-job pipeline to automatically receive finishing jobs

## Why ...

Powershell Jobs can speed up your script tremendously by parallelizing processes. It's not multi-threading, which is realized using `Runspaces` in Powershell. [(Find more on Runspaces here.)](https://blogs.technet.microsoft.com/heyscriptingguy/2015/11/26/beginning-use-of-powershell-runspaces-part-1/) However, when e.g. retreiving information from multiple machines in your network, you do not need the complicated runspace code to get every bit of performance out of your code, but can do just as well with `Start-Job` or `Invoke-Command -AsJob` or other cmdlets supportings this.

What always bugged me about this, that there was not mechanism to wait for the jobs you started, which auto-receives the results and eventually cleans up your finished jobs.

## Enter `Receive-FinishingJob`

`Receive-FinishingJob` is a function to do just that:

* collect the jobs you started from the pipeline
* immediately start checking them for being completed and then receive the result (->streaming)
* continue waiting for all jobs to finish when the pipeline is done delivering jobs
* enable a timeout for (too) long running jobs
* clean up as needed

... and do all this quietly on request.

## How To ...

Imagine you have licensable fonts installed on some machines and want to check, which ones.

You can do it one by one (Arial):

    Get-ADComputer -Filter 'Enabled -eq "true"' `
        | Where-Object { ...whatever ...} `
        | Foreach-Object {
            if (Test-Connection $_.Name -Count 1 -Quiet) {
                Invoke-Command -ComputerName $_.Name -ScriptBlock {Test-Path C:\Windows\Fonts\Arial*}
            }
          }

Granted, testing for Arial* will most likely give you `True` for every machine, but you will know which font to look for in your environment, right?

Ok, this will probably take very long, because each machine will be tested after the other. How about sending out the test to the whole bunch of machines and return the results as they appear? This is were jobs come in handy ... and the `Receive-FinishingJob` function to save you some coding:


    Get-ADComputer -Filter 'Enabled -eq "True"' `
        | Where-Object { ...whatever... } `
        | Foreach-Object {
            if (Test-Connection $_.Name -Count 1 -Quiet) {
                Invoke-Command -AsJob -ComputerName $_.DNSName -ScriptBlock {
                    [PSCustomObject]@{
                        Arial = Test-Path C:\Windows\Fonts\Arial*
                        User = (Get-WmiObject win32_computersystem).UserName
                    }
                }
            }
          } `
        | Receive-FinishingPipeJob -Throttle 500 -TimeoutSeconds 240 `
        | Where-Object {$_.Arial} `
        | Select-Object PSComputerName,User,Arial `
        | Out-GridView


I am encapsulating my remote code into a `PSCustomObject` so I can add the remotely logged on user to the data stream, too.

As you can see `Receive-FinishingJob` supports a `-Throttle` parameter, which set the loop iteration interval to check the status of the jobs in milliseconds. The higher the value, the slower the check, the less CPU time the loop uses, the more CPU time is left for the jobs. Default is 100ms, which is quite fast. `-TimeoutSeconds` sets the timeout for the jobs you startet in seconds. If they take longer, the function starts ignoring them and you have to take care of the results manually later.
If you don't supply the `-Quiet` parameter, the function will inform you about completed, timed out and failed jobs in the end.
The parameters `-NoCleanup` and `-CleanAll` tell the function, how much of the jobs you want to keep in the end:
* `-NoCleanup` leaves the jobs untouched
* `-CleanAll` removes them all
The default will only remove successfully received jobs.


Happy coding!
Max

---

P.S.:
`Test-Connect` is quite slow on non replying clients. If you want to speed that up, try the [Super Fast Ping Command `Test-OnlineFast`](https://community.idera.com/database-tools/powershell/powertips/b/tips/posts/final-super-fast-ping-command) by [Tobias Weltner](https://twitter.com/TobiasPSP). It's an absolute must imho to check the online status of clients in a whole IP range.
