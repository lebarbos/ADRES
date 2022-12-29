#Conectar no Automation Account
$azConn = Get-AutomationConnection -Name 'AzureRunAsConnection'
Add-AzureRMAccount -ServicePrincipal -Tenant $azConn.TenantID -ApplicationId $azConn.ApplicationId -CertificateThumbprint $azConn.CertificateThumbprint

#Definir TAG que serÃ¡ validada para o start das VMs
$azVMs = Get-AzureRMVM | Where-Object {$_.Tags.Auto -eq 'Start-Stop'}

#Executar o start das VMs
$azVMS | Start-AzureRMVM