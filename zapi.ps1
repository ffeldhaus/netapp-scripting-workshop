using module "C:\Users\Florian\Downloads\netapp-manageability-sdk-9.4\lib\DotNet\ManageOntap.dll"
using namespace NetApp.Manage

# Input
$Hostname = 'filer'
$Username = 'user'
$Password = 'password'
$Port = 443

$ZapiMajorVersion = 1   # default
$ZapiMinorVersion = 130 # Ontap 9.3

# Connection to Filer
$Server = [NaServer]::new($Hostname, $ZapiMajorVersion, $ZapiMinorVersion)
$Server.ServerType = [NaServer+SERVER_TYPE]::FILER
$Server.Style = [NaServer+AUTH_STYLE]::LOGIN_PASSWORD
$server.SetAdminUser($username, $password)
$server.Port = $Port

$Volume = "florianf"
$Snapshot = "snap"

### snapshot-get-iter API
$Api = [NaElement]::new("snapshot-get-iter")
$Attr = [NaElement]::new("desired-attributes")
$Api.AddChildElement($Attr) #Nested Object
$AttrInfo = [NaElement]::new("snapshot-info")
$Attr.AddChildElement($AttrInfo) #Nested Object
$AttrInfo.AddNewChild("access-time", $null)

# Representing query element
$Query = [NaElement]::new("query")
$Api.AddChildElement($query)
$QueryInfo = [NaElement]::new("snapshot-info")
$Query.AddChildElement($QueryInfo)
$QueryInfo.AddNewChild("name", $Snapshot)
$QueryInfo.AddNewChild("volume", $Volume)

$Output = $server.InvokeElem($Api)

$Output.GetChildByName("attributes-list").GetChildByName("snapshot-info").GetChildContent("access-time")