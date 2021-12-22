<#  ==============================================================================================================================================
   CleanupDCs.ps1 V1.51: Performs automatic cleanup of DCs removed from a forest

                   Usage: .\CleanupDCs -action <action> 
                   ======

                   Parameters:
                   ===========
                      -action can be set to:
                            ListDCs:                   Creates a file called DClist.txt conatining al the DCs in the forest
                            MetadataCleanup:           Performs a metadata cleanup of the DCs of DCList.txt
                            DNSCleanup:                Deletes all DNS records registered by the DCs in DCList.txt
                            AccountCleanup:            Deletes the computer account of the DCs of DCLIST.txt
                            ResetTrustPwd:             Resets the password of every trust relationship of the domain 

                   Logs the output in CleanupDCs.log in the current directory


                   How to use:
                   =====================
                   DO NOT FORGET TO UNCOMMENT THE METADATA CLEANUP NTDSUTIL COMMAND !!!

                       - On the first DC restored (the DC of the forest root domain), logon with the root domain administrator account (rid 500):
                           - Run .\CleanupDcs.ps1 -action ListDCs to create file DCList.txt containing all the DCs of the forest
                           - Edit DCList.txt and remove the DCs you want to keep.
                           - Run .\CleanupDcs.ps1 -action MetadataCleanup to perform a metadata Cleanup of the root domain DCs present in DCList.txt 
                           - Run .\CleanupDcs.ps1 -action DNSCleanup to delete the DNS records registered by the root domain DCs present in DCList.txt 
                           - Run .\CleanupDcs.ps1 -action ResetTrustPwd to restore the password of every trust relationship of the root domain 

                       - On the first DC restored of each child domain, logon with the child domain administrator account (rid 500):
                           - Copy DCList.txt from the Root DC.
                           - Run .\CleanupDcs.ps1 -action AccountCleanup to delete the computer account of the child domain DCs present in DCList.txt 
                           - Run .\CleanupDcs.ps1 -action DNSCleanup to delete the DNS records of the child domain DCs present in DCList.txt 
                           - Run .\CleanupDcs.ps1 -action ResetTrustPwd to restore the password of every trust relationship of the child domain 

 Disclaimer:
 This sample script is not supported under any Microsoft standard support program or service. 
 The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims 
 all implied warranties including, without limitation, any implied warranties of merchantability 
 or of fitness for a particular purpose. The entire risk arising out of the use or performance of 
 the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, 
 or anyone else involved in the creation, production, or delivery of the scripts be liable for any 
 damages whatsoever (including, without limitation, damages for loss of business profits, business 
 interruption, loss of business information, or other pecuniary loss) arising out of the use of or 
 inability to use the sample scripts or documentation, even if Microsoft has been advised of the 
 possibility of such damages

 ========================================================================================================================================================
#>
param ([parameter(Mandatory=$true)]$action)
$debugPreference = "inquire"

    # Function ListKeptDCs
    #    Displays the DCs that will be kept and returns their number
    # ---------------------------------------------------------------
    function ListKeptDCs
    {
          $keptDCs=0
          $DCList = get-content DCList.txt 
          write-host "The following DCs will be kept:"
          $ldapQuery = "(&(objectCategory=nTDSDSA))"
          $ObjAD = new-object System.DirectoryServices.DirectoryEntry
          $ADSearcher = new-object system.directoryservices.directorysearcher -argumentlist $ObjAD,$ldapQuery
          $Root = New-Object DirectoryServices.DirectoryEntry "LDAP://CN=Sites,CN=Configuration,$ForestRootDomain"
          $ADSearcher.SearchRoot = $Root
          try 
          {
                $QueryResult = $ADSearcher.findall()
                $QueryResult | 
                foreach {
                      $ldapObj=$_.Path.replace("LDAP://CN=NTDS Settings,","")
                      if (!($DCList | where {$_ -eq $ldapObj}))
                      {
                            $keptDCs++
                            write-host "  $ldapObj"
                      }
                }
          }
          catch 
          {
              write-host $_ -fore red
              break
          }
          
          return $KeptDCs
    }         


    #  Initialization
    # ----------------
        start-transcript .\CleanupDCs.Log
        $listedDCs=0
        $removedDCs=0
        $DNSCleanupDCs=0
        $ComputerAccountCleanupDCs=0
        $TrustPwdReset=0
        $rep=""
        $Info = "CleanupDC.ps1 V1.5 "
    
        $usage = @"
Usage: .\CleanupDCs -action <action> 
Valid actions are:
      ListDCs:         Creates a file called DClist.txt containing all DCs in the forest
      MetadataCleanup: Performs a Metadata cleanup of all the DCs of DCList.txt
      DNSCleanup:      Deletes all DNS records registered by the DCs in DCList.txt
      AccountCleanup:  Deletes the computer account a Metadata cleanup of all the DCs of DCList.txt
      ResetTrustPwd:   Resets the password of every trust relationship of the domain 
Example: 
      .\CleanupDCs -action ListDCs

"@

        cls
        switch ($Action) {
              "ListDCs"           {$Info = $Info + "List forest DCs in DCList.txt"}
              "DNSCleanup"        {$Info = $Info + "Cleanup DNS records registered by DCs of DCList.txt"}
              "MetadataCleanup"   {$Info = $Info + "Perform a MetadataCleanup of all DCs of DCList.txt"}
              "AccountCleanup"    {$Info = $Info + "Deletes the computer account of all DCs of DCList.txt"}
              "ResetTrustPwd"     {$Info = $Info + "Resets the password of every trust relationship oof the domain"}
              default {
                    write-host $info
                    write-host $usage
                    stop-transcript
                    exit
              }
        }
    
        Write-host $Info `n
    
        try 
        {
            $RootDSE=([ADSI]"LDAP://RootDSE")
            $ForestRootDomain=$RootDSE.rootDomainNamingContext
            $CurrentDomain=$RootDSE.Get("defaultNamingContext")
        }
        catch 
        {
            write-host $_ -fore red
            break
        }
        
        

    #  Action: List DCs
    #  -------------------
        if ($action -eq "ListDCs")
        {
              if (test-path .\DCList.txt)
              {
                    remove-item .\DCList.txt
              }

              $ldapQuery = "(&(objectClass=nTDSDSA))"
              $ObjAD = new-object System.DirectoryServices.DirectoryEntry
              $ADSearcher = new-object system.directoryservices.directorysearcher -argumentlist $ObjAD,$ldapQuery
              $Root = New-Object DirectoryServices.DirectoryEntry "LDAP://CN=Sites,CN=Configuration,$ForestRootDomain"
              $ADSearcher.SearchRoot = $Root
              write-host "`nThe following DCs will be added to DCList.txt:" 
              try 
              {
                    $QueryResult = $ADSearcher.findall()
                    $QueryResult | 
                    foreach {
                          $ldapObj=$_.Path.replace("LDAP://CN=NTDS Settings,","")
                          add-content -path .\DCList.txt -value $ldapObj
                          write-host "    $ldapObj" 
                          $ListedDCs++
                    }
              }
              catch 
              {
                  write-host $_ -fore red
                  break
              }
              $KeptDCs="na"
              $TrustPwdReset="na"
        }


    #  Action: MetadataCleanup
    #  -----------------------
        if ($action -eq "MetadataCleanup")
        {
              # Check DCList.txt is present
              if(!(test-path .\DCList.txt))
              {
                    write-host "File DCList.txt not found, please select action ListDCs to create the file`n" -fore red
                    stop-transcript 
	                exit
              }
              
              # Lists the DCs that will be kept and make sure not all of them will be removed
              $KeptDCs=ListKeptDCs
              if (!($KeptDCs))
              {
                    write-host "None`n`n"
                    write-host "The procedure would cleanup ALL DCs of the forest, as a result it will not be performed" -fore red
                    write-host "Pleasea make sure you removed the DCs you want to keep from DCList.txt`n" -fore red
                    stop-transcript 
                    exit
              }
        
              # Prompts the user to proceed
              write-host "`nWe are now ready to remove ALL other DCs of the forest."
              write-host " !!!   This operation should be done ONLY in a test envrironment" -fore red
              write-host " !!!   In a production environment, it will lead to a major outage highly impacting production" -fore red
              write-host " !!!   Only run in production in case of a real disaster recovery" -fore red
              $rep=""
              while (!($rep -eq "Metadata Cleanup DCs"))
              {
                    if ($rep -eq "q")
                    {
                         stop-transcript     
                         exit
                    }
                    else
                    {     
                         $rep=read-host ("`nPlease enter `"Metadata Cleanup DCs`" to perform a metadata cleanup of all other DCs or `"q`" to quit")
                    }
              }
              
              # Perform the metdata cleanup of the DCs
              $DCList = get-content DCList.txt 
              write-host "`nPerforming a metadata cleanup of the following DCs:" 
              foreach ($DCName in $DCList) {
                    $NTDSobj=[ADSI]"LDAP://CN=NTDS Settings,$dcName"
                    if ($NTDSObj.name)   # makes sure object NTDS setting exists
                    {
                          write-host "  $DCName" -fore yellow
                          # Uncomment the following line to perform the metadata cleanup
                           ntdsutil.exe "metadata cleanup" "remove selected server $DCName" quit quit 
                          $removedDCs++
                    }
                    else
                    {
                          write-host "  $DCName has no NTDS Settings object" -fore red
                    }
              }
              write-host "`n`n" 
              $TrustPwdReset="na"   
        }


    #  Action: DNSCleanup
    #  ------------------
        if ($action -eq "DNSCleanup")
        {
              if(!(test-path .\DCList.txt))
              {
                    write-host "File DCList.txt not found, please select action ListDCs to create the file`n" -fore red
                    stop-transcript
	                exit
              }

              # Lists the DCs that will be kept and make sure not all of them will be removed
              $KeptDCs=ListKeptDCs
              if (!($KeptDCs))
              {
                    write-host "The procedure would delete DNS records of ALL DCs of the forest, as a result it will not be performed" -fore red
                    write-host "Please make sure you removed the DCs you want to keep from DCList.txt`n" -fore red
                    stop-transcript
                    exit
              }
        
              # Prompts the user to proceed
              write-host "`nWe are now ready to remove DNS records from ALL other DCs of the forest."
              write-host " !!!   This operation should be done ONLY in a test envrironment" -fore red
              write-host " !!!   In a production environment, it will lead to a major outage highly impacting production" -fore red
              write-host " !!!   Only run in production in case of a real disaster recovery" -fore red
              $rep=""
              while (!($rep -eq "DNS Cleanup"))
              {
                    if ($rep -eq "q")
                    {
                         stop-transcript     
                         exit
                    }
                    else
                    {     
                         $rep=read-host("`nPlease enter `"DNS Cleanup`" to delete DNS records of other DCs or `"q`" to quit")
                    }
              }
             
              # Deletes the DNS records of the DCs
              $DCList = get-content DCList.txt 
              write-host "`nDeleting DNS records of the following DCs:"         
              try 
              {
                    foreach ($DCName in $DCList) {
                          $DCShortName = ($DCName.split(",")[0]).split("cn=")[1]
                          if(!$DCShortName)
                          {
                            write-host "    Null Detected - skipping"
                            continue
                          }
                          (Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_AType"  |where {$_.TextRepresentation -like "*$DCShortName*"}) | 
                          foreach {
                                $DCIPAddr = $_.IPAddress
                                # Deletes the A record with the IP address
                                (Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_AType"  |where {$_.IPAddress -like "*$DCIPAddr"}) | remove-wmiObject
                                # Deletes the A records with the DC name
                                $_ | remove-wmiObject
                          }
                          # Deletes the NS records
                          (Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_NSType"  |where {$_.TextRepresentation -like "*$DCShortName*"})  | remove-wmiObject
                          # Deletes the SRV DNS records  
                          (Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_SRVType"  |where {$_.TextRepresentation -like "*$DCShortName*"}) | remove-wmiObject
                          # Deletes the CNAME DNS records  
                          (Get-WmiObject -Namespace "root\MicrosoftDNS" -Class "MicrosoftDNS_CNAMEType"  |where {$_.RecordData -like "*$DCShortName*"})  |remove-wmiObject
    
                          write-host "    $DCShortName"  -fore yellow
                          $DNSCleanupDCs++
                    } 
              }
              catch 
              {
                    write-host $_ -fore red
                    break
              }

              write-host "`n`n" 
              $TrustPwdReset="na"   
        }
 
 
    #  Action: Accountcleanup
    #  ----------------------
        if ($action -eq "AccountCleanup")
        {
              if(!(test-path .\DCList.txt))
              {
                    write-host "File DCList.txt not found, please select action ListDCs to create the file`n" -fore red
                    stop-transcript
	                exit
              }

              # Lists the DCs that will be kept and make sure not all of them will be removed
              $KeptDCs=ListKeptDCs
              if (!($KeptDCs))
              {
                    write-host "The procedure would delete the computer account of ALL DCs of the forest, as a result it will not be performed" -fore red
                    write-host "Please make sure you removed the DCs you want to keep from DCList.txt`n" -fore red
                    stop-transcript
                    exit
              }
        
              # Prompts the user to proceed
              write-host "`nWe are now ready to delete the computer account of ALL other DCs of the forest."
              write-host " !!!   This operation should be done ONLY in a test envrironment" -fore red
              write-host " !!!   In a production environment, it will lead to a major outage highly impacting production" -fore red
              write-host " !!!   Only run in production in case of a real disaster recovery" -fore red
              $rep=""
              while (!($rep -eq "Account Cleanup"))
              {
                    if ($rep -eq "q")
                    {
                         stop-transcript     
                         exit
                    }
                    else
                    {     
                         $rep=read-host("`nPlease enter `"Account Cleanup`" to delete the computer account of other DCs or `"q`" to quit")
                    }
              }
             
              # Deletes the computer accounts and their child objects
              $DCList = get-content DCList.txt 
              write-host "`nDeleting computer account of the following DCs:" 
              foreach ($DCName in $DCList) {
                    $DCShortName = ($DCName.split(",")[0]).split("cn=")[1]                    
                    $ldapQuery = "(&(cn=$DCShortName))"                       # We need to perform a LDAP query since the computer account might be in a sub OU
                    $ObjAD = new-object System.DirectoryServices.DirectoryEntry
                    $ADSearcher = new-object system.directoryservices.directorysearcher -argumentlist $ObjAD,$ldapQuery
                    $Root = New-Object DirectoryServices.DirectoryEntry "LDAP://OU=Domain Controllers,$CurrentDomain"
                    $ADSearcher.SearchRoot = $Root
                    
                    try 
                    {
                          $QueryResult = $ADSearcher.findall()
                          if ($QueryResult.count -ne 0)
                          {
                                [ADSI]$computerAccount = $QueryResult[0].path
                                $ComputerAccount.psbase.deleteTree()
                                $ComputerAccount.psbase.commitChanges()
                                write-host "    $DCShortName deleted"  -fore yellow
                                $ComputerAccountCleanupDCs++
                          }
                          else 
                          {
                                write-host "    $DCShortName not present in current domain"  -fore yellow
                          }
                          
                    }
                    catch 
                    {
                          write-host $_ -fore red
                          break
                    }


              }
              write-host "`n`n"    
              $TrustPwdReset="na"
        }
 
    #  Action: ResetTrustPwd
    #  ----------------------
        if ($action -eq "ResetTrustPwd")
        {
              # Prompts the user to proceed
              write-host "`nWe are now ready to reset the password of all trusts relationships of domain $CurrentDomain"
              write-host " !!!   This operation should be done ONLY in a test envrironment" -fore red
              write-host " !!!   In a production environment, it will lead to a major outage highly impacting production" -fore red
              write-host " !!!   Only run in production in case of a real disaster recovery" -fore red
              $rep=""
              while (!($rep -eq "Reset Trusts Password"))
              {
                    if ($rep -eq "q")
                    {
                         stop-transcript     
                         exit
                    }
                    else
                    {     
                         $rep=read-host("`nPlease enter `"Reset Trusts Password`" to reset the domain's trust relationships password or `"q`" to quit")
                    }
              }
             
              $TrustPass=read-host "Please enter the trust password" -asSecureString
              $currentDomainFQDN = (Get-Item env:USERDNSDOMAIN).value
                             
              try 
              {
                    $trustCollection=[System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().GetAllTrustRelationships()
                    $trustCollection |
                    foreach {
                          write-host "Resetting password of trust with domain $($_.targetName)" -fore yellow
                          netdom trust $currentDomainFQDN /domain:$($_.targetName) /resetOneSide /passwordT:$TrustPass
                          $TrustPwdReset++
                    }
              }
              catch 
              {
                    write-host $_ -fore red
                    break
              }


              write-host "`n`n"   
              $KeptDCs="na" 
        }
     

    # Statistics
    # --------------
    Write-Host "`n=================================="
    Write-Host " Statistics:" -fore green
    Write-Host "      DCs Listed: $listedDCs" -fore green
    Write-Host "      DCs metadata cleanup: $removedDCs" -fore green
    Write-Host "      DCs computer account deleted: $ComputerAccountCleanupDCs" -fore green
    Write-Host "      DCs Removed from DNS: $DNSCleanupDCs" -fore green
    Write-Host "      DCs Kept: $KeptDCs" -fore green
    Write-Host "      Trusts password reset: $TrustPwdReset" -fore green
    Write-Host "=================================="
    stop-transcript                      
