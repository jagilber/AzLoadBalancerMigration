# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/Log/Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "/UpdateVmssInstances/UpdateVmssInstances.psd1")
function NsgCreation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NsgCreation] Initiating NSG Creation"

    log -Message "[NsgCreation] Looping all VMSS in the backend pool of the Load Balancer"
    $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { ($_ -split '/virtualMachines/')[0].ToLower() } | Select-Object -Unique    
    
    foreach ($vmssId in $vmssIds) {
        $vmss = Get-AzResource -ResourceId $vmssId | Get-AzVmss

        # Check if VMSS already has a NSG
        log -Message "[NsgCreation] Checking if VMSS Named: $($vmss.Name) has a NSG"
        if (![string]::IsNullOrEmpty($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.NetworkSecurityGroup)) {
            log -Message "[NsgCreation] NSG detected in VMSS Named: $($vmss.Name) NetworkInterfaceConfigurations.NetworkSecurityGroup Id: $($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.NetworkSecurityGroup.Id)" -severity "Information"
            log -Message "[NsgCreation] NSG will not be created for VMSS Named: $($vmss.Name)" -severity "Information"
            break
        }

        # check vmss subnets for attached NSG's
        if (![string]::IsNullOrEmpty($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.Ipconfigurations.Subnet)) {
            $subnetIds = @($vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations.Ipconfigurations.Subnet.id)
            $found = $false

            foreach ($subnetId in $subnetIds) {
                $subnet = Get-AzResource -ResourceId $subnetId
                if (![string]::IsNullOrEmpty($subnet.Properties.NetworkSecurityGroup)) {
                    log -Message "[NsgCreation] NSG detected in Subnet for VMSS Named: $($vmss.Name) Subnet.NetworkSecurityGroup Id: $($subnet.Properties.NetworkSecurityGroup.Id)" -severity "Information"
                    log -Message "[NsgCreation] NSG will not be created for VMSS Named: $($vmss.Name)" -severity "Information"
                    $found = $true
                    break
                }
            }
            
            if ($found) { break }
        }

        log -Message "[NsgCreation] NSG not detected."

        log -Message "[NsgCreation] Creating NSG for VMSS: $vmssName"

        try {
            $ErrorActionPreference = 'Stop'
            $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $vmss.ResourceGroupName -Name ("NSG-" + $vmss.Name) -Location $vmss.Location -Force
        }
        catch {
            $message = @"
            [NsgCreation] An error occured while creating NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL
            BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually create an NSG which allows traffic to the
            backend ports on the VM/VMSS and associate it with the VM, VMSS, or subnet. Error: $_
"@
            log 'Error' $message -terminateOnError
        }

        log -Message "[NsgCreation] NSG Named: $("NSG-"+$vmss.Name) created."

        # Adding NSG Rule for each Load Balancing Rule
        # Note: For now I'm assuming there is no way to have more than one VMSS in a single LB
        log -Message "[NsgCreation] Adding one NSG Rule for each Load Balancing Rule"
        $loadBalancingRules = $BasicLoadBalancer.LoadBalancingRules
        $priorityCount = 100
        foreach ($loadBalancingRule in $loadBalancingRules) {
            $networkSecurityRuleConfig = @{
                Name                                = ($loadBalancingRule.Name + "-loadBalancingRule")
                Protocol                            = $loadBalancingRule.Protocol
                SourcePortRange                     = "*"
                DestinationPortRange                = $loadBalancingRule.BackendPort
                SourceAddressPrefix                 = "*"
                DestinationAddressPrefix            = "*"
                SourceApplicationSecurityGroup      = $null
                DestinationApplicationSecurityGroup = $null
                Access                              = "Allow"
                Priority                            = $priorityCount
                Direction                           = "Inbound"
            }
            log -Message "[NsgCreation] Adding NSG Rule Named: $($networkSecurityRuleConfig.Name) to NSG Named: $($nsg.Name)"
            $nsg | Add-AzNetworkSecurityRuleConfig @networkSecurityRuleConfig > $null
            $priorityCount++
        }

        # Adding NSG Rule for each inboundNAT Rule
        log -Message "[NsgCreation] Adding one NSG Rule for each inboundNatRule"
        $networkSecurityRuleConfig = $null
        $inboundNatRules = $BasicLoadBalancer.InboundNatRules
        foreach ($inboundNatRule in $inboundNatRules) {
            if ([string]::IsNullOrEmpty($inboundNatRule.FrontendPortRangeStart)) {
                $dstportrange = ($inboundNatRule.BackendPort).ToString()
            }
            else {
                $dstportrange = (($inboundNatRule.FrontendPortRangeStart).ToString() + "-" + ($inboundNatRule.FrontendPortRangeEnd).ToString())
            }
            $networkSecurityRuleConfig = @{
                Name                                = ($inboundNatRule.Name + "-NatRule")
                Protocol                            = $inboundNatRule.Protocol
                SourcePortRange                     = "*"
                DestinationPortRange                = $dstportrange
                SourceAddressPrefix                 = "*"
                DestinationAddressPrefix            = "*"
                SourceApplicationSecurityGroup      = $null
                DestinationApplicationSecurityGroup = $null
                Access                              = "Allow"
                Priority                            = $priorityCount
                Direction                           = "Inbound"
            }
            log -Message "[NsgCreation] Adding NSG Rule Named: $($networkSecurityRuleConfig.Name) to NSG Named: $($nsg.Name)"
            $nsg | Add-AzNetworkSecurityRuleConfig @networkSecurityRuleConfig > $null
            $priorityCount++
        }

        # Saving NSG
        log -Message "[NsgCreation] Saving NSG Named: $($nsg.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg > $null
        }
        catch {
            $message = @"
            [NsgCreation] An error occured while adding security rules to NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO BACKEND POOL MEMBERS WILL
            BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually rules in NSG '$("NSG-"+$vmss.Name)' which allows traffic
            to the backend ports on the VM/VMSS and associate the NSG with the VM, VMSS, or subnet. Error: $_
"@
            log 'Error' $message -terminateOnError
        }

        # Adding NSG to VMSS
        log -Message "[NsgCreation] Adding NSG Named: $($nsg.Name) to VMSS Named: $($vmss.Name)"
        foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
            $networkInterfaceConfiguration.NetworkSecurityGroup = $nsg.Id
        }

        # Saving VMSS
        log -Message "[NsgCreation] Saving VMSS Named: $($vmss.Name)"
        try {
            $ErrorActionPreference = 'Stop'
            Update-AzVmss -ResourceGroupName $vmss.ResourceGroupName -VMScaleSetName $vmss.Name -VirtualMachineScaleSet $vmss > $null
        }
        catch {
            $message = @"
            [NsgCreation] An error occured while updating VMSS '$($vmss.name)' to associate the new NSG '$("NSG-"+$vmss.Name)'. TRAFFIC FROM LOAD BALANCER TO
            BACKEND POOL MEMBERS WILL BE BLOCKED UNTIL AN NSG WITH AN ALLOW RULE IS CREATED! To recover, manually associate NSG '$("NSG-"+$vmss.Name)'
            with the VM, VMSS, or subnet. Error: $_
"@
            log 'Error' $message -terminateOnError
        }

        UpdateVmssInstances -vmss $vmss
    }
    log -Message "[NsgCreation] NSG Creation Completed"
}

Export-ModuleMember -Function NsgCreation