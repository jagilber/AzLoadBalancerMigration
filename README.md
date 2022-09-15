# Upgrade from Basic load balancer to Standard load balancer for a Virtual Machine Scale set

### In this article
  - Upgrade overview
  - Download the modules
  - Use the Module
  - Common questions
  - Next Steps

[Azure Standard Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview) offers a rich set of functionality and high availability through zone redundancy. To learn more about Azure Load Balancer SKUs, see [comparison table](https://docs.microsoft.com/en-us/azure/load-balancer/skus#skus).

The entire migration process for a load balancer with a Public or Private IP is handled by the PowerShell module. 

## Upgrade Overview

An Azure PowerShell module is available to migrate from a Basic to Standard load balancer. The PowerShell module exports a single function called 'Start-AzBasicLoadBalancerUpgrade' which performs the following procedures:

- Verifies that the Basic load balancer has a supported configuration
- Verifies tht the new Standard load balancer name is valid abd available.
- Determines whether the load balancer has a public or private IP address
- Backs up the current Basic load balancer state to enable migration retry if a migration fails
- Removes the load balancer from the Virtual Machine Scale set
- Deletes the Basic load balancer
- Creates a new Standard load balancer 
- Upgrades a Basic Public IP to the Standard SKU (Public Load balancer only)
- Upgrades a dynamically assigned Public IP a Static IP address (Public Load balancer only)
- Migrates Frontend IP configurations
- Migrates Backend address pools
- Migrates NAT rules
- Migrates Probes
- Migrates Load balancing rules
- Creates outbound rules for SNAT (Public Load balancer only)
- Creates NSG for inbound traffic (Public Load balancer only), ensuring that traffic to the backend pool members is allowed when moving to Standard load balancer's default-deny network access policy
- Logs the entire upgrade process to a log file called `Start-AzBasicLoadBalancerUpgrade.log` in the location where the module was executed

### Unsupported Scenarios

- Basic load balancers with a VMSS backend pool member which is also a member of a backend pool on a different load balancer
- Basic load balancers with backend pool members which are not VMSS's
- Basic load balancers with only empty backend pools
- Basic load balancers with IPV6 frontend IP configurations
- Basic load balancers with a VMSS backend pool member configured with 'Flexible' orchestration mode
- Migrating a Basic load balancer to an existing Standard load balancer

### Prerequisites

- Install the latest version of [PowerShell Desktop or Core ](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.2)
- Determine whether you have the latest Az module installed (8.2.0)
  - Install the latest Az PowerShell module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-8.3.0)

### Install the latest Az modules using Install-Module

```
PS C:\> Find-Module Az | Install-Module
```

## Install the 'VMSSBasicLoadBalancerMigration' module

Install the module from [PowerShell gallery](https://www.powershellgallery.com/packages/AzureVMSSLoadBalancerUpgrade/0.1.0)

```
PS C:\> Find-Module VMSSBasicLoadBalancerMigration | Install-Module
```

## Use the module

1. Use `Connect-AzAccount` to connect to the required Azure AD tenant and Azure subscription 

```
PS C:\> Connect-AzAccount -Tenant <TenantId> -Subscription <SubscriptionId> 
```

2. Find the Load Balancer you wish to migrate & record its name and containing resource group name

3. Examine the module parameters:
- *BasicLoadBalancerName [string] Required* - This parameter is the name of the existing Basic load balancer you would like to migrate
- *ResourceGroupName [string] Required* - This parameter is the name of the resource group containing the Basic load balancer
- *RecoveryBackupPath [string] Optional* - This parameter allows you to specify an alternative path in which to store the Basic load balancer ARM template backup file (defaults to the current working directory)
- *FailedMigrationRetryPath [string] Optional* - This parameter allows you to specify a path to a Basic load balancer backup state file when retrying a failed migration (defaults to current working directory)

4. Run the upgrade command.

### Example: migrate a basic load balancer to a standard load balancer with the same name, providing the basic load balancer name and resource group
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name>
```


###  Example: migrate a basic load balancer to a standard load balancer with the same name, providing the basic load object through the pipeline
```
PS C:\> Get-AzLoadBalancer -Name <basic load balancer name> -ResourceGroup <Basic load balancer resource group name> | Start-AzBasicLoadBalancerUpgrade
```


### Example: migrate a basic load balancer to a standard load balancer with the specified name
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name> -StandardLoadBalancerName <new standard load balancer name>
```

- Optionally, if you would like to specify different paths for the `-RecoveryBackupPath` and `-FailedMigrationRetryFilePath` parameters

### Example: migrate a basic load balancer to a standard load balancer with the specified name and store the basic load balancer backup file at the specified path
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -ResourceGroupName <load balancer resource group name> -BasicLoadBalancerName <existing basic load balancer name> -StandardLoadBalancerName <new standard load balancer name> -RecoveryBackupPath C:\BasicLBRecovery 
``` 

### Example: retry a failed migration (due to error or script termination) by providing the Basic load balancer backup state file
```
PS C:\> Start-AzBasicLoadBalancerUpgrade -FailedMigrationRetryFilePath C:\BasicLBRecovery\State_lb-basic-01_rg-basiclbmigration_20220912T1744261819.json
``` 

## Common Questions

### Will the module migrate my frontend IP address to the new Standard load balancer? 
Yes, for both public and internal load balancers, the module ensures that front end IP addresses are maintained. For public IPs, the IP is converted to a static IP prior to migration (if necessary). For internal front ends, the module will attempt to reassign the same IP address freed up when the Basic load balancer was deleted; if the private IP is not available the script will fail. In this scenario, remove the VNET connected device which has claimed the intended front end IP and rerun the module with the `-FailedMigrationRetryFilePath <backupFilePath>` parameter specified.

### How long does the upgrade take?
It usually takes a few minutes for the script to finish and it could take longer depending on the complexity of your load balancer configuration, number of backend pool members, and instance count of associated Virtual Machine Scale Sets. Keep the downtime in mind and plan for failover if necessary.

### Does the script migrate my backend pool members from my basic load balancer to the newly created standard load balancer?
Yes. The Azure PowerShell script migrates the virtual machine scale set to the newly created public or private standard load balancer.

### What happens if my migration fails mid-migration? 
The module is designed to accommodate failures, either due to unhandled errors or unexpected script termination. The failure design is a 'fail forward' approach, where instead of attempting to move back to the Basic load balancer, you should correct the issue causing the failure (see the error output or log file), and retry the migration again, specifying the `-FailedMigrationRetryFilePath <backupFilePath>` parameter. For public load balancers, because the Public IP Address SKU has been updated to Standard, moving the same IP back to a Basic load balancer will not be possible. The basic failure recovery procedure is:
  1. Address the cause of the migration failure. Check the log file `Start-AzBasicLoadBalancerUpgrade.log` for details
  1. Remove the new Standard load balancer (if created)
  1. Locate the basic load balancer state backup file. This will either be in the directory where the script was executed, or at the path specified with the `-RecoveryBackupPath` parameter during the failed execution. The file will be named: `State_<basicLBName>_<basicLBRGName>_<timestamp>.json`
  1. Rerun the migration script, specifying the `-FailedMigrationRetryFilePath <backupFilePath>` parameter instead of -BasicLoadBalancerName or passing the Basic load balancer over the pipeline

## Next Steps
[Learn about the Azure Load Balancer](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-overview)