// service fabric 3 node bronze durability cluster with no management role (MR)
// v0.1

targetScope = 'resourceGroup'
param location string
param resourceGroupName string
param keyVaultName string
param keyVaultResourceGroupName string

@description('Remote desktop user password. Must be a strong password')
@secure()
param adminPassword string

@description('Remote desktop user Id')
param adminUserName string

@description('Certificate Thumbprint')
param certificateThumbprint string

#disable-next-line no-hardcoded-env-urls
@description('Refers to the location URL in your key vault where the certificate was uploaded, it is should be in the format of https://<name of the vault>.vault.azure.net:443/secrets/<exact location>')
param certificateUrlValue string

@description('Name of your cluster - Between 3 and 23 characters. Letters and numbers only')
param clusterName string

@description('DNS Name')
param dnsName string = clusterName

@description('Cluster and NodeType 0 Durability Level. see: https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-capacity#durability-characteristics-of-the-cluster')
@allowed([
  'Bronze'
  'Silver'
  'Gold'
])
param durabilityLevel string = 'Bronze'

@description('Nodetype Network Name')
param nicName string = 'NIC'

@description('Nodetype0 Instance Count')
param nt0InstanceCount int = 3

@description('Nodetype0 Reverse Proxy Port')
param nt0reverseProxyEndpointPort int = 19081

@description('Public IP Address Name')
param publicIPName string = 'PublicIP-LB-FE'

@description('Cluster Reliability Level. see: https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-capacity#reliability-characteristics-of-the-cluster')
@allowed([
  'Bronze'
  'Silver'
  'Gold'
  'Platinum'
])
param reliabilityLevel string = 'Bronze'

@description('Resource Id of the key vault, is should be in the format of /subscriptions/<Sub ID>/resourceGroups/<Resource group name>/providers/Microsoft.KeyVault/vaults/<vault name>')
param sourceVaultValue string

@description('Virtual Network Subnet0 Name')
param subnet0Name string = 'Subnet-0'

@description('Virtual Network Subnet0 Address Prefix')
param subnet0Prefix string = '10.0.0.0/24'

@description('Virtual Network Name')
param virtualNetworkName string = 'VNet'

@description('Virtual Machine Image Offer')
param vmImageOffer string = 'WindowsServer'

@description('Virtual Machine OS Type')
param vmOSType string = 'Windows'

@description('Virtual Machine Image Publisher')
param vmImagePublisher string = 'MicrosoftWindowsServer'

@description('Virtual Machine Image SKU')
param vmImageSku string = '2022-Datacenter'

@description('Virtual Machine Image Version')
param vmImageVersion string = 'latest'

@description('Virtual Machine Nodetype0 Name')
@maxLength(9)
param vmNodeType0Name string = 'nt0'

@description('Virtual Machine Nodetype0 Size/SKU')
param vmNodeType0Size string = 'Standard_D2_v2'

@description('Virtual Network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

// VARIABLES
var applicationDiagnosticsStorageAccountName = toLower('sfdiag${uniqueString(subscription().subscriptionId, resourceGroupName, location)}3')
var supportLogStorageAccountName = toLower('sflogs${uniqueString(subscription().subscriptionId, resourceGroupName, location)}2')
var certificateStoreValue = 'My'
var lbFrontEndIpConfigurationName = 'LoadBalancerIPConfig'
var lbBackendAddressPoolName = 'LoadBalancerBEAddressPool'
var lbBackendNatPoolName = 'LoadBalancerBEAddressNatPool'
var lbHttpProbeName = 'FabricHttpGatewayProbe'
var lbProbeName = 'FabricGatewayProbe'
var lbName0 = 'LB-${clusterName}-${vmNodeType0Name}'
var lbID0 = resourceId('Microsoft.Network/loadBalancers', lbName0)
var lbIPConfig0 = '${lbID0}/frontendIPConfigurations/${lbFrontEndIpConfigurationName}'
var lbPoolID0 = '${lbID0}/backendAddressPools/${lbBackendAddressPoolName}'
var lbProbeID0 = '${lbID0}/probes/${lbProbeName}'
var lbHttpProbeID0 = '${lbID0}/probes/${lbHttpProbeName}'
var lbNatPoolID0 = '${lbID0}/inboundNatPools/${lbBackendNatPoolName}'

var nt0applicationEndPort = 30000
var nt0applicationStartPort = 20000
var nt0ephemeralEndPort = 65534
var nt0ephemeralStartPort = 49152
var nt0fabricHttpGatewayPort = 19080
var nt0fabricTcpGatewayPort = 19000

var overProvision = false
var vnetID = resourceId('Microsoft.Network/virtualNetworks', virtualNetworkName)
var subnet0Ref = '${vnetID}/subnets/${subnet0Name}'
var sfTags = {
  resourceType: 'Service Fabric'
  clusterName: clusterName
}

// RESOURCES
// used for adminuser and password test env
resource kv1 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  name: keyVaultName
  scope: resourceGroup(keyVaultResourceGroupName)
}

// Resource Group
module rg '../modules/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  scope: subscription()
  params: {
    name: resourceGroupName
    location: location
  }
}

// sf logs storage account cannot use CARML as not able to get object to run list* listkeys() at 'start'
resource supportLogStorageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: supportLogStorageAccountName
  location: location
  properties: {
  }
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
  tags: sfTags
  dependsOn: [
    rg
  ]
}

// sf application/service diagnostic account cannot use CARML as not able to get object to run list* listkeys() at 'start'
resource applicationDiagnosticsStorageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: applicationDiagnosticsStorageAccountName
  location: location
  properties: {
  }
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
  tags: sfTags
  dependsOn: [
    rg
  ]
}

// vnet and subnet
resource virtualNetworks 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnet0Name
        properties: {
          addressPrefix: subnet0Prefix
        }
      }
    ]
  }
  tags: sfTags
  dependsOn: [
    rg
  ]
}

// public ip address cannot use CARML as dnsSettings are not exposed
resource publicIp0 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: '${publicIPName}-0'
  location: location
  properties: {
    dnsSettings: {
      domainNameLabel: dnsName
    }
    publicIPAllocationMethod: 'Dynamic'
  }
  tags: sfTags
  dependsOn: [
    rg
  ]
}

// basic lb with public ip
resource lb0 'Microsoft.Network/loadBalancers@2021-08-01' = {
  name: lbName0
  location: location
  properties: {
    frontendIPConfigurations: [
      {
        name: lbFrontEndIpConfigurationName
        properties: {
          publicIPAddress: {
            id: publicIp0.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: lbBackendAddressPoolName
        properties: {
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'LBRule'
        properties: {
          backendAddressPool: {
            #disable-next-line use-resource-id-functions
            id: lbPoolID0
          }
          backendPort: nt0fabricTcpGatewayPort
          enableFloatingIP: false
          frontendIPConfiguration: {
            #disable-next-line use-resource-id-functions
            id: lbIPConfig0
          }
          frontendPort: nt0fabricTcpGatewayPort
          idleTimeoutInMinutes: 5
          probe: {
            #disable-next-line use-resource-id-functions
            id: lbProbeID0
          }
          protocol: 'tcp'
        }
      }
      {
        name: 'LBHttpRule'
        properties: {
          backendAddressPool: {
            #disable-next-line use-resource-id-functions
            id: lbPoolID0
          }
          backendPort: nt0fabricHttpGatewayPort
          enableFloatingIP: false
          frontendIPConfiguration: {
            #disable-next-line use-resource-id-functions
            id: lbIPConfig0
          }
          frontendPort: nt0fabricHttpGatewayPort
          idleTimeoutInMinutes: 5
          probe: {
            #disable-next-line use-resource-id-functions
            id: lbHttpProbeID0
          }
          protocol: 'tcp'
        }
      }
    ]
    probes: [
      {
        name: lbProbeName
        properties: {
          intervalInSeconds: 5
          numberOfProbes: 2
          port: nt0fabricTcpGatewayPort
          protocol: 'tcp'
        }
      }
      {
        name: lbHttpProbeName
        properties: {
          intervalInSeconds: 5
          numberOfProbes: 2
          port: nt0fabricHttpGatewayPort
          protocol: 'tcp'
        }
      }
    ]
    inboundNatPools: [
      {
        name: lbBackendNatPoolName
        properties: {
          backendPort: 3389
          frontendIPConfiguration: {
            #disable-next-line use-resource-id-functions
            id: lbIPConfig0
          }
          frontendPortRangeEnd: 4500
          frontendPortRangeStart: 3389
          protocol: 'tcp'
        }
      }
    ]
  }
  tags: sfTags
  dependsOn: [
    rg
  ]
}

resource vmNodeType0 'Microsoft.Compute/virtualMachineScaleSets@2022-08-01' = {
  name: vmNodeType0Name
  location: location
  properties: {
    overprovision: overProvision
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      extensionProfile: {
        extensions: [
          {
            name: '${vmNodeType0Name}_ServiceFabricNode'
            properties: {
              type: 'ServiceFabricNode'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                StorageAccountKey1: listKeys(supportLogStorageAccount.id, '2022-09-01').keys[0].value
                StorageAccountKey2: listKeys(supportLogStorageAccount.id, '2022-09-01').keys[1].value
              }
              publisher: 'Microsoft.Azure.ServiceFabric'
              settings: {
                clusterEndpoint: cluster.properties.clusterEndpoint
                nodeTypeRef: vmNodeType0Name
                dataPath: 'D:\\SvcFab'
                durabilityLevel: durabilityLevel
                enableParallelJobs: true
                nicPrefixOverride: subnet0Prefix
                certificate: {
                  thumbprint: certificateThumbprint
                  x509StoreName: certificateStoreValue
                }
              }
              typeHandlerVersion: '1.1'
            }
          }
          {
            name: '${vmNodeType0Name}_VMDiagnosticsVmExt'
            properties: {
              type: 'IaaSDiagnostics'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                storageAccountName: applicationDiagnosticsStorageAccountName
                storageAccountKey: listKeys(applicationDiagnosticsStorageAccount.id, '2022-09-01').keys[0].value
                #disable-next-line no-hardcoded-env-urls
                storageAccountEndPoint: 'https://core.windows.net/'
              }
              publisher: 'Microsoft.Azure.Diagnostics'
              settings: {
                WadCfg: {
                  DiagnosticMonitorConfiguration: {
                    overallQuotaInMB: '50000'
                    EtwProviders: {
                      EtwEventSourceProviderConfiguration: [
                        {
                          provider: 'Microsoft-ServiceFabric-Actors'
                          scheduledTransferKeywordFilter: '1'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'ServiceFabricReliableActorEventTable'
                          }
                        }
                        {
                          provider: 'Microsoft-ServiceFabric-Services'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'ServiceFabricReliableServiceEventTable'
                          }
                        }
                      ]
                      EtwManifestProviderConfiguration: [
                        {
                          provider: 'cbd93bc2-71e5-4566-b3a7-595d8eeca6e8'
                          scheduledTransferLogLevelFilter: 'Information'
                          scheduledTransferKeywordFilter: '4611686018427387904'
                          scheduledTransferPeriod: 'PT5M'
                          DefaultEvents: {
                            eventDestination: 'ServiceFabricSystemEventTable'
                          }
                        }
                      ]
                    }
                  }
                }
                StorageAccount: applicationDiagnosticsStorageAccountName
              }
              typeHandlerVersion: '1.5'
            }
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${nicName}-0'
            properties: {
              ipConfigurations: [
                {
                  name: '${nicName}-0'
                  properties: {
                    loadBalancerBackendAddressPools: [
                      {
                        #disable-next-line use-resource-id-functions
                        id: lbPoolID0
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        #disable-next-line use-resource-id-functions
                        id: lbNatPoolID0
                      }
                    ]
                    subnet: {
                      #disable-next-line use-resource-id-functions
                      id: subnet0Ref
                    }
                  }
                }
              ]
              primary: true
            }
          }
        ]
      }
      osProfile: {
        adminPassword: adminPassword // kv1.getSecret('adminPassword')  //adminPassword
        adminUsername: adminUserName // kv1.getSecret('adminUsername') //adminUserName
        computerNamePrefix: vmNodeType0Name
        secrets: [
          {
            sourceVault: {
              id: sourceVaultValue
            }
            vaultCertificates: [
              {
                certificateStore: certificateStoreValue
                certificateUrl: certificateUrlValue
              }
            ]
          }
        ]
      }
      storageProfile: {
        imageReference: {
          publisher: vmImagePublisher
          offer: vmImageOffer
          sku: vmImageSku
          version: vmImageVersion
        }
        osDisk: {
          caching: 'ReadOnly'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
    }
  }
  sku: {
    name: vmNodeType0Size
    capacity: nt0InstanceCount
    tier: 'Standard'
  }
  tags: {
    resourceType: 'Service Fabric'
    clusterName: clusterName
  }
}

resource cluster 'Microsoft.ServiceFabric/clusters@2020-03-01' = {
  name: clusterName
  location: location
  properties: {
    addOnFeatures: [
      'DnsService'
      'RepairManager'
    ]
    certificate: {
      thumbprint: certificateThumbprint
      x509StoreName: certificateStoreValue
    }
    clientCertificateCommonNames: []
    clientCertificateThumbprints: []
    diagnosticsStorageAccountConfig: {
      blobEndpoint: reference('Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}', '2022-05-01').primaryEndpoints.blob
      protectedAccountKeyName: 'StorageAccountKey1'
      queueEndpoint: reference('Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}', '2022-05-01').primaryEndpoints.queue
      storageAccountName: supportLogStorageAccountName
      tableEndpoint: reference('Microsoft.Storage/storageAccounts/${supportLogStorageAccountName}', '2022-05-01').primaryEndpoints.table
    }
    fabricSettings: [
      {
        parameters: [
          {
            name: 'ClusterProtectionLevel'
            value: 'EncryptAndSign'
          }
        ]
        name: 'Security'
      }
    ]
    managementEndpoint: 'https://${publicIp0.properties.dnsSettings.fqdn}:${nt0fabricHttpGatewayPort}'
    nodeTypes: [
      {
        name: vmNodeType0Name
        applicationPorts: {
          endPort: nt0applicationEndPort
          startPort: nt0applicationStartPort
        }
        clientConnectionEndpointPort: nt0fabricTcpGatewayPort
        durabilityLevel: durabilityLevel
        ephemeralPorts: {
          endPort: nt0ephemeralEndPort
          startPort: nt0ephemeralStartPort
        }
        httpGatewayEndpointPort: nt0fabricHttpGatewayPort
        reverseProxyEndpointPort: nt0reverseProxyEndpointPort
        isPrimary: true
        vmInstanceCount: nt0InstanceCount
      }
    ]
    reliabilityLevel: reliabilityLevel
    upgradeMode: 'Automatic'
    vmImage: vmOSType
  }
  tags: sfTags
  dependsOn: [
    supportLogStorageAccount
  ]
}

@description('The location the resource was deployed into.')
output location string = location

@description('cluster management endpoint.')
output managementEndpoint string = cluster.properties.managementEndpoint
