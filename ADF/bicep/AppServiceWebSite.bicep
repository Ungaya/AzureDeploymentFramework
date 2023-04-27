param Prefix string

@allowed([
  'I'
  'D'
  'T'
  'U'
  'P'
  'S'
  'G'
  'A'
])
param Environment string = 'D'

@allowed([
  '0'
  '1'
  '2'
  '3'
  '4'
  '5'
  '6'
  '7'
  '8'
  '9'
  '10'
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
])
param DeploymentID string
param Stage object
param Extensions object
param Global object
param DeploymentInfo object

param month string = utcNow('MM')
param year string = utcNow('yyyy')

// Use same PAT token for 3 month blocks, min PAT age is 6 months, max is 9 months
var SASEnd = dateTimeAdd('${year}-${padLeft((int(month) - (int(month) - 1) % 3), 2, '0')}-01', 'P9M')

var Deployment = '${Prefix}-${Global.OrgName}-${Global.Appname}-${Environment}${DeploymentID}'
var DeploymentURI = toLower('${Prefix}${Global.OrgName}${Global.Appname}${Environment}${DeploymentID}')

var regionLookup = json(loadTextContent('./global/region.json'))
var primaryPrefix = regionLookup[Global.PrimaryLocation].prefix

var GlobalRGJ = json(Global.GlobalRG)
var HubRGJ = json(Global.hubRG)
var HubKVJ = json(Global.hubKV)

var gh = {
  globalRGPrefix: contains(GlobalRGJ, 'Prefix') ? GlobalRGJ.Prefix : primaryPrefix
  globalRGOrgName: contains(GlobalRGJ, 'OrgName') ? GlobalRGJ.OrgName : Global.OrgName
  globalRGAppName: contains(GlobalRGJ, 'AppName') ? GlobalRGJ.AppName : Global.AppName
  globalRGName: contains(GlobalRGJ, 'name') ? GlobalRGJ.name : '${Environment}${DeploymentID}'

  hubRGPrefix: HubRGJ.?Prefix ?? Prefix
  hubRGOrgName: HubRGJ.?OrgName ?? Global.OrgName
  hubRGAppName: HubRGJ.?AppName ?? Global.AppName
  hubRGRGName: HubRGJ.?name ?? HubRGJ.?name ?? '${Environment}${DeploymentID}'

  hubKVPrefix: contains(HubKVJ, 'Prefix') ? HubKVJ.Prefix : Prefix
  hubKVOrgName: contains(HubKVJ, 'OrgName') ? HubKVJ.OrgName : Global.OrgName
  hubKVAppName: contains(HubKVJ, 'AppName') ? HubKVJ.AppName : Global.AppName
  hubKVRGName: contains(HubKVJ, 'RG') ? HubKVJ.RG : HubRGJ.name
}

var globalRGName = '${gh.globalRGPrefix}-${gh.globalRGOrgName}-${gh.globalRGAppName}-RG-${gh.globalRGName}'
var HubRGName = '${gh.hubRGPrefix}-${gh.hubRGOrgName}-${gh.hubRGAppName}-RG-${gh.hubRGRGName}'
var HubKVName = toLower('${gh.hubKVPrefix}-${gh.hubKVOrgName}-${gh.hubKVAppName}-${gh.hubKVRGName}-kv${HubKVJ.name}')

resource KV 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
  name: HubKVName
  scope: resourceGroup(HubRGName)
}

resource AppInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: '${DeploymentURI}AppInsights'
}

resource sadiag 'Microsoft.Storage/storageAccounts@2021-09-01' existing = {
  name: '${DeploymentURI}sadiag'
}
var SAS = sadiag.listServiceSAS('2021-09-01', {
  canonicalizedResource: '/blob/${sadiag.name}/${last(split(Global._artifactsLocation, '/'))}'
  signedResource: 'c'
  signedProtocol: 'https'
  signedPermission: 'rw'
  signedServices: 'b'
  signedExpiry: SASEnd
  keyToSign: 'key1'
}).serviceSasToken

var WebSiteInfo = DeploymentInfo.?WebSiteInfo ?? []

var WSInfo = [for (ws, index) in WebSiteInfo: {
  match: ((Global.CN == '.') || contains(array(Global.CN), ws.name))
  saName: toLower('${DeploymentURI}sa${ws.saname}')
}]

// merge appConfig, move this to the websiteInfo as a property to pass in these from the param file
var myAppConfig = {
  default: {

  }
  php: {

  }
  dotnet: {
    ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
    XDT_MicrosoftApplicationInsights_Mode: 'Recommended'
  }
  node: {
    WEBSITE_NODE_DEFAULT_VERSION: '~16'
    ApplicationInsightsAgent_EXTENSION_VERSION: '~2'
    XDT_MicrosoftApplicationInsights_NodeJS: '1'
    XDT_MicrosoftApplicationInsights_Mode: 'default'
  }
  java: {

  }
}

module website 'x.appService.bicep' = [for (ws, index) in WebSiteInfo: if (WSInfo[index].match) {
  name: 'dp${Deployment}-ws${ws.Name}'
  params: {
    ws: ws
    appprefix: 'ws'
    Deployment: Deployment
    DeploymentURI: DeploymentURI
    Global: Global
    globalRGName: globalRGName
    DeploymentID: DeploymentID
    Environment: Environment
    Prefix: Prefix
    Stage: Stage
    diagLogs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
      }
      // supported on premium
      // {
      //   category: 'AppServiceFileAuditLogs'
      //   enabled: true
      //   retentionPolicy: {
      //     days: 30
      //     enabled: false
      //   }
      // }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: false
        }
      }
    ]
  }
}]

module testResourcExists 'x.testResourceExists.ps1.bicep' = [for (ws, index) in WebSiteInfo: if (WSInfo[index].match) {
  name: 'testResourcExists-${Deployment}-ws${ws.Name}-config-appsettings'
  params: {
    resourceId: '${website[index].outputs.WebSiteId}/config/appsettings'
    userAssignedIdentityName: '${Deployment}-uaiReader'
  }
}]

module websiteSettings 'x.appServiceSettings.bicep' = [for (ws, index) in WebSiteInfo: if (WSInfo[index].match) {
  name: 'dp${Deployment}-ws${ws.Name}-settings'
  params: {
    ws: ws
    appprefix: 'ws'
    Deployment: Deployment
    appConfigCustom: contains(ws,'stack') ? myAppConfig[ws.stack] : myAppConfig.default
    setAppConfigCurrent: testResourcExists[index].outputs.Exists
    appConfigNew: {
      APPINSIGHTS_INSTRUMENTATIONKEY: AppInsights.properties.InstrumentationKey
      APPLICATIONINSIGHTS_CONNECTION_STRING: 'InstrumentationKey=${AppInsights.properties.InstrumentationKey}'
      MICROSOFT_PROVIDER_AUTHENTICATION_SECRET: contains(ws,'authsettingsV2') ? '@Microsoft.KeyVault(VaultName=${KV.name};SecretName=${ws.Name}-${ws.authsettingsV2.applicationId})' : null
      DIAGNOSTICS_AZUREBLOBCONTAINERSASURL: contains(ws,'webAppLogsContainer') ? '${sadiag.properties.primaryEndpoints.blob}${ws.webAppLogsContainer}?${SAS}' : null
      WEBSITE_HTTPLOGGING_CONTAINER_URL: contains(ws,'webAppLogsContainer') ? '${sadiag.properties.primaryEndpoints.blob}${ws.webAppLogsContainer}?${SAS}' : null
      DIAGNOSTICS_AZUREBLOBRETENTIONINDAYS: 15
      WEBSITE_HTTPLOGGING_RETENTION_DAYS: 15
    }
  }
}]
