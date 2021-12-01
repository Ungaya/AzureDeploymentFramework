@allowed([
  'AZE2'
  'AZC1'
  'AEU2'
  'ACU1'
  'AWCU'
])
param Prefix string = 'ACU1'

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
])
param DeploymentID string = '1'
#disable-next-line no-unused-params
param Stage object
#disable-next-line no-unused-params
param Extensions object
param Global object = {
  n: '1'
}
param DeploymentInfo object

@secure()
param vmAdminPassword string

@secure()
#disable-next-line no-unused-params
param devOpsPat string

@secure()
#disable-next-line no-unused-params
param sshPublic string

var Deployment = '${Prefix}-${Global.OrgName}-${Global.Appname}-${Environment}${DeploymentID}'
var DeploymentURI = toLower('${Prefix}${Global.OrgName}${Global.Appname}${Environment}${DeploymentID}')

var appConfigurationInfo = (contains(DeploymentInfo, 'appConfigurationInfo') ? DeploymentInfo.appConfigurationInfo : json('null'))

var azSQLInfo = contains(DeploymentInfo, 'azSQLInfo') ? DeploymentInfo.azSQLInfo : []

var azSQL = [for (sql,index) in azSQLInfo : {
  match: ((Global.CN == '.') || contains(Global.CN, sql.Name))
}]

module SQL 'AZSQL-SQL.bicep' = [for (sql,index) in azSQLInfo : if(azSQL[index].match) {
  name: 'dp${Deployment}-azSQLDeploy${sql.name}'
  params: {
    Deployment: Deployment
    DeploymentURI: DeploymentURI
    azSQLInfo: sql
    Global: Global
    vmAdminPassword: vmAdminPassword
  }
  dependsOn: []
}]

