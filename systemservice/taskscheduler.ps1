$Action = New-ScheduledTaskAction -Execute "C:\Path\To\application.exe"
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "RunDotNetAppAtBoot" -Action $Action -Trigger $Trigger -Principal $Principal
