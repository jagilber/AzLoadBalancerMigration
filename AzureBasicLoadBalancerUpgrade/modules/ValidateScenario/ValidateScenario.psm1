# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")

Function Test-SupportedMigrationScenario {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSLoadBalancer]
        $BasicLoadBalancer,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,78}[A-Za-z0-9_])?$")]
        [string]
        $StdLoadBalancerName
    )

    $scenario = @{
        'ExternalOrInternal' = ''
    }

    # checking source load balance SKU
    log -Message "[Test-SupportedMigrationScenario] Verifying if Load Balancer $($BasicLoadBalancer.Name) is valid for migration"
    log -Message "[Test-SupportedMigrationScenario] Verifying source load balancer SKU"
    If ($BasicLoadBalancer.Sku.Name -ne 'Basic') {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] The load balancer '$($BasicLoadBalancer.Name)' in resource group '$($BasicLoadBalancer.ResourceGroupName)' is SKU '$($BasicLoadBalancer.SKU.Name)'. SKU must be Basic!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] Source load balancer SKU is type Basic"

    # Detecting if there are any backend pools that is not virtualMachineScaleSets, if so, exit
    log -Message "[Test-SupportedMigrationScenario] Checking if there are any backend pool members which are not virtualMachineScaleSets and that all backend pools are not empty"
    $backendPoolHasMembers = $false
    foreach ($backendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        foreach ($backendIpConfiguration in $backendAddressPool.BackendIpConfigurations) {
            $backendPoolHasMembers = $true
            if ($backendIpConfiguration.Id.split("/")[7] -ne "virtualMachineScaleSets") {
                log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer has backend pools that is not virtualMachineScaleSets, exiting" -Severity 'Error'
                return
            }
        }
    }
    If (!$backendPoolHasMembers) {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' has no backend pool membership, which is not supported for migration!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] All backend pools members virtualMachineScaleSets!"

    # Detecting if there are more than one VMSS in the backend pool, if so, exit
    # Basic Load Balancers doesn't allow more than one VMSS as a backend pool becuase they would be under different availability sets.
    # This is a sanity check to make sure that the script is not run on a Basic Load Balancer that has more than one VMSS in the backend pool.
    log -Message "[Test-SupportedMigrationScenario] Checking if there are more than one VMSS in the backend pool"
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { $_.split("/virtualMachines/")[0] } | Select-Object -Unique
    if ($vmssIds.count -gt 1) {
        log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer has more than one VMSS in the backend pool, exiting" -Severity 'Error'
        return
    }
    log -message "[Test-SupportedMigrationScenario] Basic Load Balancer has only one VMSS in the backend pool"

    # checking that source load balancer has sub-resource configurations
    log -Message "[Test-SupportedMigrationScenario] Checking that source load balancer is configured"
    If ($BasicLoadBalancer.LoadBalancingRules.count -eq 0) {
        log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer '$($BasicLoadBalancer.Name)' has no front end configurations, so there is nothing to migrate!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] Load balancer has at least 1 frontend IP configuration"

    # check if the load balancer name should be re-used, if so check if it's not standard already
    log -Message "[Test-SupportedMigrationScenario] Checking that standard load balancer name '$StdLoadBalancerName'"
    $chkStdLB = (Get-AzLoadBalancer -Name $StdLoadBalancerName -ResourceGroupName $BasicLoadBalancer.ResourceGroupName -ErrorAction SilentlyContinue)
    If ($chkStdLB) {
        log -Message "[Test-SupportedMigrationScenario] Load balancer resource '$($chkStdLB.Name)' already exists. Checking if it is a Basic SKU for migration"
        If ($chkStdLB.Sku.Name -ne 'Basic') {
            log -ErrorAction Stop -Severity 'Error' -Message "[Test-SupportedMigrationScenario] Load balancer resource '$($chkStdLB.Name)' is not a Basic SKU, so it cannot be migrated!"
            return
        }
        log -Message "[Test-SupportedMigrationScenario] Load balancer resource '$($chkStdLB.Name)' is a Basic Load Balancer. The same name will be re-used."
    }

    # check if load balancer backend pool contains VMSSes which are part of another LBs backend pools
    log -Message "[Test-SupportedMigrationScenario] Checking if backend pools contain members which are members of another load balancer's backend pools..."
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object{$_.split("/virtualMachines/")[0]} | Select-Object -Unique
    ForEach ($vmssId in $vmssIds) {
        $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVMSS
        $loadBalancerAssociations = @()
        ForEach ($nicConfig in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
            ForEach ($ipConfig in $nicConfig.ipConfigurations) {
                ForEach ($bepMembership in $ipConfig.LoadBalancerBackendAddressPools) {
                    $loadBalancerAssociations += $bepMembership.id.split('/')[0..8] -join '/'
                }
            }
        }

        If (($beps = $loadBalancerAssociations | Sort-Object | Get-Unique).Count -gt 1) {
            $message = @"
            [Test-SupportedMigrationScenario] One (or more) backend address pool VMSS members on basic load balancer '$($BasicLoadBalancer.Name)' is also member of
            the backend address pool on another load balancer. `nVMSS: '$($vmssId)'; `nMember of load balancer backend pools on: $beps
"@
            log 'Error' $message
            Exit
        }
    }

    # check if any VMSS instances have instance protection enabled
    log -Message "[Test-SupportedMigrationScenario] Checking for instances in backend pool member VMSS '$($vmssIds.split('/')[-2])' with Instance Protection configured"
    $vmssInstances = Get-AzVmssVM -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmssIds.split('/')[-2]

    ForEach ($instance in $vmssInstances) {
        If ($instance.ProtectionPolicy.ProtectFromScaleSetActions) {
            $message = @"
            [Test-SupportedMigrationScenario] VMSS '$($vmss.Name)' contains 1 or more instances with a ProtectFromScaleSetActions Instance Protection configured. This
            module cannot upgrade the associated load balancer because a VMSS cannot be a backend member of both basic and standard SKU load balancers. Remove the Instance
            Protection policy and re-run the module.
"@
            log -Severity 'Error'
            $vmssInstances.Remove($instance)
        }
    }
    log -Message "[Test-SupportedMigrationScenario] No VMSS instances with Instance Protection found"


    # detecting if source load balancer is internal or external-facing
    log -Message "[Test-SupportedMigrationScenario] Determining if LB is internal or external based on FrontEndIPConfiguration[0]'s IP configuration"
    If (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)) {
        log -Message "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a private IP address '$($BasicLoadBalancer.FrontendIpConfigurations[0].PrivateIpAddress)', so this LB is Internal"
        $scenario.ExternalOrInternal = 'Internal'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress)) {
        log -Message "[Test-SupportedMigrationScenario] FrontEndIPConfiguiration[0] is assigned a public IP address '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIpAddress.Id)', so this LB is External"

        # Detecting if there is a frontend IPV6 configuration, if so, exit
        log -Message "[Test-SupportedMigrationScenario] Determining if there is a frontend IPV6 configuration"
        foreach ($frontendIP in $BasicLoadBalancer.FrontendIpConfigurations) {
            $pip = Get-azPublicIpAddress -Name $frontendIP.PublicIpAddress.Id.split("/")[8] -ResourceGroupName $frontendIP.PublicIpAddress.Id.split("/")[4]
            if ($pip.PublicIpAddressVersion -eq "IPv6") {
                log -ErrorAction Stop -Message "[Test-SupportedMigrationScenario] Basic Load Balancer is using IPV6. This is not a supported scenario. PIP Name: $($pip.Name) RG: $($pip.ResourceGroupName)" -Severity "Error"
                return
            }
        }
        $scenario.ExternalOrInternal = 'External'
    }
    ElseIf (![string]::IsNullOrEmpty($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefix.Id)) {
        log -ErrorAction Stop -Severity 'Error' "[Test-SupportedMigrationScenario] FrontEndIPConfiguration[0] is assigned a public IP prefix '$($BasicLoadBalancer.FrontendIpConfigurations[0].PublicIPPrefixText)', which is not supported for migration!"
        return
    }
    log -Message "[Test-SupportedMigrationScenario] Load Balancer $($BasicLoadBalancer.Name) is valid for migration"
    return $scenario
}

Export-ModuleMember -Function Test-SupportedMigrationScenario