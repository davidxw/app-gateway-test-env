@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param name string

param location string = resourceGroup().location
param tags object = {}

param appgwSubnetName string = 'appgw-subnet'
param containerAppEnvSubnetName string = 'containerapp-env-subnet'

param vnetPrefix string = '192.168.0.0/16'
param appgwSubnetAddressPrefix string = '192.168.0.0/24'
param containerAppEnvSubnetAddressPrefix string = '192.168.1.0/24'

var resourceToken = toLower(uniqueString(subscription().id, name, location))


var vnetName = toLower('vnet-${resourceToken}')
var appGatewayName = toLower('appgw-${resourceToken}')
var containerAppEnvName = toLower('ca-env-${resourceToken}')
var nsgName = toLower('${name}-nsg-${resourceToken}')
var laName = toLower('loganalytics-${resourceToken}')
var appGatewayPublicIpName = toLower('appgw-public-ip-${resourceToken}')

var containerAppDetails = [
  {
    name: 'containerapp1'
    image: 'davidxw/webtest:latest'
    targetPort: 8080
  }
  {
    name: 'containerapp2'
    image: 'davidxw/webtest:latest'
    targetPort: 8080
  }
]

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAppGatewayManagement'
        properties: {
          priority: 100
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowWebHttp'
        properties: {
          priority: 200
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowWebHttps'
        properties: {
          priority: 300
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/VirtualNetworks@2021-08-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetPrefix
      ]
    }
  }
}

resource subnet_appGateway 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: appgwSubnetName
  properties: {
    addressPrefix: appgwSubnetAddressPrefix
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

resource subnet_containerAppEnv 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: containerAppEnvSubnetName
  properties: {
    addressPrefix: containerAppEnvSubnetAddressPrefix
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    delegations: [
      {
        name: 'app'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: laName
  location: location
  tags: tags
}

resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: subnet_containerAppEnv.id
      internal: false
    }
    workloadProfiles: [
      {
        workloadProfileType: 'Consumption'
        name: 'Consumption'
      }
    ]
  }
}

resource containerApps 'Microsoft.App/containerApps@2024-03-01' = [ for containerApp in containerAppDetails: {
  name: containerApp.name
  location: location
  properties: {
    environmentId: containerAppEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: true
        targetPort: containerApp.targetPort
      }
    }
    template: {
      containers: [
        {
          name: containerApp.name
          image: containerApp.image
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}]

var appGatewayFrontendPort = 80

var containerApp1Hostname = containerApps[0].properties.configuration.ingress.fqdn
var containerApp2Hostname = containerApps[1].properties.configuration.ingress.fqdn
var subnetAppGatewayId = subnet_appGateway.id

// var containerApp1Hostname = 'containerapp1.reddune-9abc9434.australiaeast.azurecontainerapps.io'
// var containerApp2Hostname = 'containerapp2.reddune-9abc9434.australiaeast.azurecontainerapps.io'
// var subnetAppGatewayId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, appgwSubnetName)

resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: appGatewayPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource appGateway 'Microsoft.Network/applicationGateways@2021-08-01' = {
  name: appGatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetAppGatewayId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIp'
        properties: {
          publicIPAddress: {
            id: appGatewayPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort'
        properties: {
          port: appGatewayFrontendPort
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backendPool1'
        properties: {
          backendAddresses: [
            {
              fqdn: containerApp1Hostname
            }
          ]
        }
      }
      {
        name: 'backendPool2'
        properties: {
          backendAddresses: [
            {
              fqdn: containerApp2Hostname
            }
          ]
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'appGatewayFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'appGatewayFrontendPort')
          }
          protocol: 'Http'
          sslCertificate: null
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'appGatewayRoutingRule1'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'backendPool1')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'appGatewayBackendHttpsSettings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'echo'
        properties: {
          protocol: 'Https'
          path: '/api/echo'
          pickHostNameFromBackendHttpSettings: true
          timeout: 60
          interval: 30
          match: {
             statusCodes: [
              '200-399'
             ]
          }
        }
      }]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpsSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, 'echo')
          }
        }
      }
    ]
  }
}

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'logs'
  scope: appGateway
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
    ]
  }
}

