using module "C:\Users\Florian\Downloads\netapp-manageability-sdk-9.4\lib\DotNet\ManageOntap.dll"
using namespace NetApp.Manage

$PORT = 443                 # always use HTTPS
$ZAPI_MAJOR_VERSION = 1     # default
$ZAPI_MINOR_VERSION = 130   # Ontap 9.3

<#
    .SYNOPSIS
    Create Snapshot via ZAPI
    .DESCRIPTION
    Create Snapshot via ZAPI
    .PARAMETER Hostname
    IP or Hostname of Cluster or SVM to connect to
    .PARAMETER Vserver
    vServer of the volume to create snapshot on
    .PARAMETER Credential
    PS Credential containing username and password
    .PARAMETER Volume
    Volume name to create snapshot on
    .PARAMETER Snapshot
    Name of Snapshot
    .PARAMETER SnapmirrorLabel
    Snapmirror label for Snapshot
#>
function Global:Invoke-ZapiSnapshot {
    [CmdletBinding()]

    PARAM (
        [parameter(
            Mandatory=$True,
            Position=0,
            HelpMessage="IP or Hostname of Cluster or SVM to connect to")][String]$Hostname,
        [parameter(
            Mandatory=$False,
            Position=1,
            HelpMessage="vServer of the volume to create snapshot on")][Alias("Svm")][String]$Vserver,
        [parameter(
            Mandatory=$True,
            Position=2,
            HelpMessage="PS Credential containing username and password")][PSCredential]$Credential,
        [parameter(
            Mandatory=$True,
            Position=3,
            HelpMessage="Volume name to create snapshot on")][String]$Volume,
        [parameter(
            Mandatory=$True,
            Position=4,
            HelpMessage="Name of Snapshot")][String]$Snapshot,
        [parameter(
            Mandatory=$True,
            Position=5,
            HelpMessage="Snapmirror label for Snapshot")][String]$SnapmirrorLabel
    )

    BEGIN {
        # Connection to Filer
        $Server = [NaServer]::new($Hostname, $ZAPI_MAJOR_VERSION, $ZAPI_MINOR_VERSION)
        $Server.ServerType = [NaServer+SERVER_TYPE]::FILER
        $Server.Vserver = $Vserver
        $Server.Style = [NaServer+AUTH_STYLE]::LOGIN_PASSWORD
        $Server.SetAdminUser($Credential.UserName, $Credential.GetNetworkCredential().Password)
        $Server.Port = $PORT
    }

    PROCESS {
        ### snapshot-create API
        $Api = [NaElement]::new("snapshot-create")
        $Api.AddNewChild("volume", $Volume)
        $Api.AddNewChild("snapshot", $Snapshot)
        $Api.AddNewChild("snapmirror-label", $SnapmirrorLabel)

        Write-Verbose "Invoking API:`n$Api"
        $null = $Server.InvokeElem($Api)
    }
}

<#
    .SYNOPSIS
    List Snapshots via ZAPI
    .DESCRIPTION
    List Snapshots via ZAPI
    .PARAMETER Hostname
    IP or Hostname of Cluster or SVM to connect to.
    .PARAMETER Vserver
    vServer of the volume to create snapshot on. Only required if not connect to vServer LIF.
    .PARAMETER Credential
    PS Credential containing username and password.
    .PARAMETER Volume
    Volume name to list snapshots for.
    .PARAMETER Snapshot
    Name of Snapshot.
    .PARAMETER Tag
    Continuation tag from previous call.
#>
function Global:Get-ZapiSnapshots {
    [CmdletBinding()]

    PARAM (
        [parameter(
            Mandatory=$True,
            Position=0,
            HelpMessage="IP or Hostname of Cluster or SVM to connect to.")][String]$Hostname,
        [parameter(
            Mandatory=$False,
            Position=1,
            HelpMessage="vServer of the volume to create snapshot on. Only required if not connect to vServer LIF.")][Alias("Svm")][String]$Vserver,
        [parameter(
            Mandatory=$True,
            Position=2,
            HelpMessage="PS Credential containing username and password.")][PSCredential]$Credential,
        [parameter(
            Mandatory=$False,
            Position=3,
            HelpMessage="Volume name to list snapshots for.")][String]$Volume,
        [parameter(
            Mandatory=$False,
            Position=4,
            HelpMessage="Name of Snapshot.")][String]$Snapshot,
        [parameter(
            Mandatory=$False,
            Position=5,
            HelpMessage="Continuation tag from previous call.")][String]$Tag
    )

    BEGIN {
        # Connection to Filer
        $Server = [NaServer]::new($Hostname, $ZAPI_MAJOR_VERSION, $ZAPI_MINOR_VERSION)
        $Server.ServerType = [NaServer+SERVER_TYPE]::FILER
        $Server.Vserver = $Vserver
        $Server.Style = [NaServer+AUTH_STYLE]::LOGIN_PASSWORD
        $Server.SetAdminUser($Credential.UserName, $Credential.GetNetworkCredential().Password)
        $Server.Port = $PORT
    }

    PROCESS {
        ### snapshot-get-iter API
        $Api = [NaElement]::new("snapshot-get-iter")

        # if continuation tag is specified set it
        if ($Tag) {
            $Api.AddNewChild("tag", $Tag)
        }

        # desired attributes
        $Attr = [NaElement]::new("desired-attributes")
        $Api.AddChildElement($Attr) #Nested Object
        $AttrInfo = [NaElement]::new("snapshot-info")
        $Attr.AddChildElement($AttrInfo) #Nested Object
        $AttrInfo.AddNewChild("access-time", $null)
        $AttrInfo.AddNewChild("vserver", $null)
        $AttrInfo.AddNewChild("volume", $null)
        $AttrInfo.AddNewChild("name", $null)
        $AttrInfo.AddNewChild("snapmirror-label", $null)

        # query to filter for specific volume or snapshot
        $Query = [NaElement]::new("query")
        $Api.AddChildElement($query)
        $QueryInfo = [NaElement]::new("snapshot-info")
        $Query.AddChildElement($QueryInfo)
        if ($Volume) {
            $QueryInfo.AddNewChild("volume", $Volume)
        }
        if ($Snapshot) {
            $QueryInfo.AddNewChild("snapshot", $Snapshot)
        }
        
        Write-Verbose "Invoking API:`n$Api"
        $Output = $Server.InvokeElem($Api)

        $AttributesList = $Output.GetChildByName("attributes-list")
        foreach ($SnapshotInfo in $AttributesList.GetChildren()) {
            $SnapshotObject = [PSCustomObject]@{
                Vserver = $SnapshotInfo.GetChildContent("vserver")
                Volume = $SnapshotInfo.GetChildContent("volume")
                Name = $SnapshotInfo.GetChildContent("name")
                Created = [System.TimeZoneInfo]::ConvertTimeFromUtc(([datetime]'1/1/1970').AddSeconds($SnapshotInfo.GetChildContent("access-time")),[System.TimeZoneInfo]::Local)
                SnapmirrorLabel = $SnapshotInfo.GetChildContent("snapmirror-label")
            }
            Write-Output $SnapshotObject
        }

        # if next-tag is specified, then result is truncated and we need to continue retrieving snapshots from next tag
        $NextTag = $Output.GetChildContent("next-tag")
        if ($NextTag) {
            Get-ZapiSnapshots -Hostname $Hostname -Vserver $Vserver -Credential $Credential -Volume $Volume -Tag $NextTag
        }
    }
}

<#
    .SYNOPSIS
    Create Consistency Point Snapshot via ZAPI on multiple volumes
    .DESCRIPTION
    Create Consistency Point Snapshot via ZAPI on multiple volumes
    .PARAMETER Hostname
    IP or Hostname of Cluster or SVM to connect to
    .PARAMETER Vserver
    vServer of the volume to create snapshot on
    .PARAMETER Credential
    PS Credential containing username and password
    .PARAMETER Volume
    Volume name to create snapshot on
    .PARAMETER Snapshot
    Name of Snapshot
    .PARAMETER SnapmirrorLabel
    Snapmirror label for Snapshot
    .PARAMETER FenceTimeout
    Timeout for IO fencing until cp commit must be completed
    .PARAMETER FenceTimeoutSeconds
    Timeout in seconds for IO fencing until cp commit must be completed
#>
function Global:Invoke-ZapiConsistencySnapshot {
    [CmdletBinding(DefaultParameterSetName="none")]

    PARAM (
        [parameter(
            Mandatory=$True,
            Position=0,
            HelpMessage="IP or Hostname of Cluster or SVM to connect to")][String]$Hostname,
        [parameter(
            Mandatory=$False,
            Position=1,
            HelpMessage="vServer of the volume to create snapshot on")][Alias("Svm")][String]$Vserver,
        [parameter(
            Mandatory=$True,
            Position=2,
            HelpMessage="PS Credential containing username and password")][PSCredential]$Credential,
        [parameter(
            Mandatory=$True,
            Position=3,
            HelpMessage="List of volume names to create snapshot on")][String[]]$Volumes,
        [parameter(
            Mandatory=$True,
            Position=4,
            HelpMessage="Name of Snapshot")][String]$Snapshot,
        [parameter(
            Mandatory=$True,
            Position=5,
            HelpMessage="Snapmirror label for Snapshot")][String]$SnapmirrorLabel,
        [parameter(
            Mandatory=$False,
            ParameterSetName="FenceTimeout",
            Position=6,
            HelpMessage="Timeout for IO fencing until cp commit must be completed")][ValidateSet("urgent","medium","relaxed")][String]$FenceTimeout,
        [parameter(
            Mandatory=$False,
            ParameterSetName="FenceTimeoutSeconds",
            Position=7,
            HelpMessage="Timeout in seconds for IO fencing until cp commit must be completed")][ValidateRange(5,120)][Int]$FenceTimeoutSeconds
    )

    BEGIN {
        # Connection to Filer
        $Server = [NaServer]::new($Hostname, $ZAPI_MAJOR_VERSION, $ZAPI_MINOR_VERSION)
        $Server.ServerType = [NaServer+SERVER_TYPE]::FILER
        $Server.Vserver = $Vserver
        $Server.Style = [NaServer+AUTH_STYLE]::LOGIN_PASSWORD
        $Server.SetAdminUser($Credential.UserName, $Credential.GetNetworkCredential().Password)
        $Server.Port = $PORT
    }

    PROCESS {
        ### cg-start API
        $Api = [NaElement]::new("cg-start")
        $Api.AddNewChild("snapshot", $Snapshot)
        $VolumesElement = [NaElement]::new("volumes")
        foreach ($Volume in $Volumes) {
            $VolumesElement.AddNewChild("volume-name",$Volume)
        }
        $Api.AddChildElement($VolumesElement)
        $Api.AddNewChild("snapmirror-label", $SnapmirrorLabel)
        if ($FenceTimeout) {
            $Api.AddNewChild("timeout", $FenceTimeout)
        }
        if ($FenceTimeoutSeconds) {
            $Api.AddNewChild("user-timeout", $FenceTimeoutSeconds)
        }

        Write-Verbose "Invoking API:`n$Api"
        $Result = $Server.InvokeElem($Api)

        $CgId = $Result.GetChildContent("cg-id")

         ### cg-commit API
         $Api = [NaElement]::new("cg-commit")
         $Api.AddNewChild("cg-id", $CgId)
 
         Write-Verbose "Invoking API:`n$Api"
         $Result = $Server.InvokeElem($Api)
    }
}