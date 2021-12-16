param Deployment string
param DeploymentID string
param DeploymentInfo object
param DNSServers array
param Global object
#disable-next-line no-unused-params
param Prefix string
param Environment string

var HubRGJ = json(Global.hubRG)

var gh = {
  hubRGPrefix:  contains(HubRGJ, 'Prefix') ? HubRGJ.Prefix : Prefix
  hubRGOrgName: contains(HubRGJ, 'OrgName') ? HubRGJ.OrgName : Global.OrgName
  hubRGAppName: contains(HubRGJ, 'AppName') ? HubRGJ.AppName : Global.AppName
  hubRGRGName:  contains(HubRGJ, 'name') ? HubRGJ.name : contains(HubRGJ, 'name') ? HubRGJ.name : '${Environment}${DeploymentID}'
}

var HubRGName = '${gh.hubRGPrefix}-${gh.hubRGOrgName}-${gh.hubRGAppName}-RG-${gh.hubRGRGName}'
var HubVNName = '${gh.hubRGPrefix}-${gh.hubRGOrgName}-${gh.hubRGAppName}-${gh.hubRGRGName}-vn'

var networkId = '${Global.networkid[0]}${string((Global.networkid[1] - (2 * int(DeploymentID))))}'
var networkIdUpper = '${Global.networkid[0]}${string((1 + (Global.networkid[1] - (2 * int(DeploymentID)))))}'
var addressPrefixes = [
  '${networkId}.0/23'
]
var SubnetInfo = (contains(DeploymentInfo, 'SubnetInfo') ? DeploymentInfo.SubnetInfo : [])

var Domain = split(Global.DomainName, '.')[0]

var RouteTableGlobal = {
  id: resourceId(HubRGName, 'Microsoft.Network/routeTables/', '${replace(HubVNName, 'vn', 'rt')}${Domain}${Global.RTName}')
}

resource NSG 'Microsoft.Network/networkSecurityGroups@2021-02-01' existing = [for (sn, index) in SubnetInfo : {
  name: '${Deployment}-nsg${sn.name}'
}]

var delegations = {
  default: []
  'Microsoft.Web/serverfarms': [
    {
      name: 'delegation'
      properties: {
        serviceName: 'Microsoft.Web/serverfarms'
      }
    }
  ]
  'Microsoft.ContainerInstance/containerGroups': [
    {
      name: 'aciDelegation'
      properties: {
        serviceName: 'Microsoft.ContainerInstance/containerGroups'
      }
    }
  ]
}

resource VNET 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${Deployment}-vn'
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    dhcpOptions: {
      dnsServers: array(DNSServers)
    }
    subnets: [for (sn,index) in SubnetInfo: {
      name: sn.name
      properties: {
        addressPrefix: '${((sn.name == 'snMT02') ? networkIdUpper : networkId)}.${sn.Prefix}'
        networkSecurityGroup: ! (contains(sn, 'NSG') && bool(sn.NSG)) ? null : /*
        */  {
              id: NSG[index].id
            }
        natGateway: ! (contains(sn, 'NGW') && bool(sn.NGW)) ? null : /*
        */  {
              id: resourceId('Microsoft.Network/natGateways','${Deployment}-ngwNAT01')
            }
        routeTable: contains(sn, 'Route') && bool(sn.Route) ? RouteTableGlobal : null
        privateEndpointNetworkPolicies: 'Disabled'
        delegations: contains(sn, 'delegations') ? delegations[sn.delegations] : delegations.default
      }
    }]
  }
}
