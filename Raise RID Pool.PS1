$rid= get-adobject "CN=RID Manager$,CN=SYSTEM,DC=LCB,DC=LOCAL" –properties *
$rid. rIDAvailablePool
$rid. rIDAvailablePool=$rid. rIDAvailablePool+100000
Set-adobject –instance $rid
get-adobject “CN=RID Manager$,CN=SYSTEM,DC=LCB,DC=LOCAL” –properties *
