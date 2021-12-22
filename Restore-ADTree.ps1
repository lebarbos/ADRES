<#
.Synopsis
   Recursively restores an object and all it's child objects from Active Directory Recycle Bin
.DESCRIPTION
   Recursively restores either: 
    - Any deleted child from a certain object, e.i. any objects delted from within an OU.
    - A deleted item and all it's deleted child objects, i.e. a whole OU Structure.

    Things worth noting:
     - If an object is deleted and a new object is created with the same RDN and then also delted, 
       the script will always choose the oldest (first) deleted object.
     - To only restore objects deleted AFTER a certain time, use the parameter 
       TimeFilter.

    Supports both -WhatIf and -Confirm
   
.EXAMPLE
   Restore-ADTree.ps1 -Identity OU=Org,DC=lab,DC=lcl

   Will restore any objects deleted from the Organizational Unit Org and any of their child objects.
.EXAMPLE
   Restore-ADTree.ps1 -Identity OU=Org,DC=lab,DC=lcl -TimeFilter '2014-10-17 08:00'

   Will restore any objects deleted from the Organizational Unit Org and any of their child objects
   that were deleted after the time specified.
.EXAMPLE
   Restore-ADTree.ps1 -lastKnownRDN Org

   Will restore the object with lastknownRDN 'Org' and all its deleted child objects.
.LINK
   http://blog.simonw.se
.NOTES
   AUTHOR:       Jimmy Andersson, Knowledge Factory
   DATE:		     2014-03-20
   CHANGE DATE:  2014-10-20
   VERSION:      1.0 - First version by Jimmy Andersson
                 2.0 - Rewrite by Simon Wåhlin
                       Added PowerShell best practices
                       Now supports filter by datetime
                       Supports -WhatIf and -Confirm
                       Will handle conflicts by only restoring the first (oldest) deleted object
                       Added error handling
#>
[Cmdletbinding(SupportsShouldProcess)]
Param (
    # Specifies LastKnownRDN of object to be restored.
	[Parameter(Mandatory,ParameterSetName='LastKnown')]
	[String]
	$lastKnownRDN,

    # Specifies DN of last known parent of object to restore.
	[Parameter(ParameterSetName='LastKnown')]
	[String]
	$lastKnownParent,

	# Specifies the identity of the object to be restored or its parent.
	[Parameter(Mandatory,ParameterSetName='Identity')]
	[String]
	$Identity,
	
	# Specifies which partition to restore from.
	# Defaults to default naming context.
	[Parameter(ParameterSetName='Identity')]
	[Parameter(ParameterSetName='LastKnown')]
	[String]
    $Partition = (Get-ADRootDSE).defaultNamingContext,

    # Only objects deleted afted this time will be restored.
    [Parameter(ParameterSetName='Identity')]
	[Parameter(ParameterSetName='LastKnown')]
	[DateTime]
	$TimeFilter = $(Get-Date 1601-01-01),

	# Specifies whether to process live children or not.
    # This will search for deleted objects that used to reside
    # within objects that are not deleted.
    #
    # Use this to specify a root OU and recursively restore
    # any object deleted from within that OU
	[Parameter(ParameterSetName='Identity')]
	[Parameter(ParameterSetName='LastKnown')]
	[switch]
	$Includelivechildren,

	[Parameter(ParameterSetName='Identity')]
	[Parameter(ParameterSetName='LastKnown')]
	[switch]
	$PassThru
)

Begin
{
    Import-Module ActiveDirectory -Verbose:$false
    $FilterDateTime = Get-Date $TimeFilter.ToUniversalTime() -f 'yyyyMMddHHmmss.0Z'
    function Restore-Tree
    <#
    .Synopsis
       Recursive function doing the actual restoring
    #>
    {
	    [CmdletBinding(SupportsShouldProcess)]
	    Param
	    (
		    [Parameter()]
		    [String]
		    $strObjectGUID,
		
		    [Parameter()]
		    [String]
		    $strNamingContext,

		    [Parameter()]
		    [String]
		    $strDelObjContainer,
		
		    [Parameter()]
		    [String]
		    $TimeFilter = '16010101000000.0Z',
	    
		    [Parameter()]
		    [Switch]
		    $IncludeLiveChildren,

	        [Parameter()]
	        [switch]
	        $PassThru
	    )
        Begin
        {
            
        }
        Process
        {
	        Try
            {
		        # Check if object exists already:
                Write-Verbose -Message ''
                Write-Verbose -Message "Processing object $strObjectGUID"
		        $objRestoredParent = Get-ADObject -Identity $strObjectGUID -Partition $strNamingContext -ErrorAction Stop

                Write-Verbose -Message "Found object $($objRestoredParent.distinguishedName)"
		        Write-Verbose -Message "$($objRestoredParent.distinguishedName) is a live object and will not be restored."

		        if($IncludeLiveChildren)
		        {
                    Write-Verbose -Message "Searching for live child objects to $($objRestoredParent.distinguishedName)"
                    $Param = @{
                        SearchScope = 'Onelevel'
                        SearchBase = $objRestoredParent.distinguishedName
                        ldapFilter = '(objectClass=*)'
                        ResultPageSize = 300
                        ResultSetSize = $Null
                        ErrorAction = 'SilentlyContinue'
                    }
	                $objChildren = Get-ADObject @Param

		            if ($objChildren -ne $null)
			        {
		    	        foreach ($objChild in $objChildren)
				        {
					        $Param = @{
						        strObjectGUID = $objChild.objectGUID
						        strNamingContext = $strNamingContext
                                strDelObjContainer = $strDelObjContainer
						        IncludeLiveChildren = $IncludeLiveChildren
                                TimeFilter = $TimeFilter
                                PassThru = $PassThru
					        }
					        Restore-Tree @Param
				        }
			        }
                    else
                    {
                        Write-Verbose -Message 'No live child objects found'
                    }
		        }
	        }
	        Catch
	        {
		        # Object did not exist, let's try to restore it
                Try
                {
                    # Resolve ObjectGUID to distinguishedName for better verbose message
                    $Param = @{
                        Identity = $strObjectGUID
                        Partition = $strNamingContext
                        includeDeletedObjects = $true
                        Properties = 'msDS-LastKnownRDN','lastknownparent','whenChanged'
                        ErrorAction = 'Stop'
                    }
		            $objRestoredParent = Get-ADObject @Param

			        Write-Verbose -Message "Restoring object $($objRestoredParent.distinguishedName)"
                    $ShouldProcessMsg = '{0} to {1} deleted at {2}' -f $objRestoredParent.'msDS-LastKnownRDN', $objRestoredParent.'lastknownparent', $objRestoredParent.'whenChanged'
                    Try
                    {
                        if($PSCmdlet.ShouldProcess($ShouldProcessMsg,'Restore'))
                        {
			                Restore-ADobject -Identity $strObjectGUID -Partition $strNamingContext -Confirm:$false -ErrorAction Stop
                        
                            $objRestoredParent = Get-ADObject -Identity $strObjectGUID -Partition $strNamingContext -ErrorAction Stop
			                Write-Verbose -Message "Restored object: $($objRestoredParent.DistinguishedName)"
                            if( $PassThru )
                            {
                                Write-Output $objRestoredParent
                            }
                        }
                    }
                    Catch
                    {
                        $objRestoredParent = $Null
                        Write-Warning -Message "Failed to restore object $($objRestoredParent.distinguishedName)"
                        Write-Warning -Message $_.Exception.Message
                    }
                }
                Catch
                {
                    # No deleted object found.
                }
	        }
	
            if($objRestoredParent)
            {
	            $strFilter = "(&(WhenChanged>=$TimeFilter)(lastknownParent=$($objRestoredParent.distinguishedName.Replace('\0','\\0'))))"
            
                Write-Verbose -Message "Searching for deleted child objects of $($objRestoredParent.distinguishedName.Replace('\0','\\0'))"

                $Param = @{
                    SearchScope = 'Subtree' 
                    SearchBase = $strDelObjContainer
                    includeDeletedObjects = $true
                    ldapFilter = $strFilter
                    ResultPageSize = 300
                    ResultSetSize = $null 
                    Properties = @('msDS-LastKnownRDN', 'WhenChanged')
                    ErrorAction = 'SilentlyContinue'
                }
                $objChildren = Get-ADObject @Param
                # If multiple objects are conflicting, select only the oldest one
                # to get newer objects, timeFilter will be used
                $objChildren = $objChildren |
                    Group-Object -Property msDS-LastKnownRDN |
                        foreach {
                            $_.Group |
                                Sort-Object -Property WhenChanged |
                                    Select-Object -First 1
                        }

	            if ($objChildren)
	            {
                    Write-Verbose -Message 'Processing found child objects...'
    	            foreach ($objChild in $objChildren)
		            {
                        $Param = @{
                            strObjectGUID = $objChild.objectGUID
                            strNamingContext = $strNamingContext
                            strDelObjContainer = $strDelObjContainer
                            IncludeLiveChildren = $IncludeLiveChildren
                            TimeFilter = $TimeFilter
                            PassThru = $PassThru
                        }
			            Restore-Tree @Param
		            }
	            }
                else
                {
                    Write-Verbose -Message 'No deleted child objects found.'
                }
            }
        }
    }
}
Process
{
    $strDelObjContainer = (Get-ADDomain).DeletedObjectsContainer

    Switch ($PSCmdlet.ParameterSetName)
    {
        'Identity'
        {
            $Param = @{
                Identity = $Identity
                Partition = $Partition
                includeDeletedObjects = $true
                Properties = @('lastknownparent', 'whenChanged', 'isDeleted')
            }
            $objSearchResult = Get-ADObject @Param
        }

        'LastKnown'
        {
            $FilterArray = @("(msds-lastknownRDN=$lastKnownRDN)","(WhenChanged>=$FilterDateTime)")

            if($PSBoundParameters.ContainsKey('lastknownParent'))
            {
                $FilterArray += "(lastknownParent=$lastKnownParent)"
            }
            
            $strFilter = '(&{0})' -f ($FilterArray -join '')
            $Param = @{
                SearchScope = 'SubTree'
                SearchBase = $strDelObjContainer
                includeDeletedObjects = $true
                ldapFilter = $strFilter
                Properties = @('lastknownparent', 'whenChanged', 'isDeleted', 'msDS-LastKnownRDN')
            }
	        $objSearchResult = Get-ADObject @Param
        }
    }

    if ($objSearchResult)
    {
        if ($objSearchResult.Count -gt 1)
        {
            Write-Warning -Message 'Search returned more than one object, please refine search parameters.'
            Write-Warning -Message ''
            Write-Warning -Message ("`n{0}" -f ($objSearchResult | Format-Table msDS-LastKnownRDN, lastknownparent, whenChanged -AutoSize | Out-String))
            Write-Warning -Message ''
            Throw
        }
        else
        {
            $Param = @{
                strObjectGUID = $objSearchResult.objectGUID
                strNamingContext = $partition
                IncludeLiveChildren = $includelivechildren
                strDelObjContainer = $strDelObjContainer
                TimeFilter = $FilterDateTime
                PassThru = $PassThru
            }
            Restore-Tree @Param
        }
    }
    else
    {
        Write-Warning -Message 'No objects matching specified search terms.'
    }
}