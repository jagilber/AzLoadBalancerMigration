# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
function NatRulesMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[NatRulesMigration] Initiating Nat Rules Migration"
    $inboundNatRules = $BasicLoadBalancer.InboundNatRules
    foreach ($inboundNatRule in $inboundNatRules) {
        log -Message "[NatRulesMigration] Adding Nat Rule $($inboundNatRule.Name) to Standard Load Balancer"

        try {
            $ErrorActionPreference = 'Stop'
            if([string]::IsNullOrEmpty($inboundNatRule.BackendAddressPool.Id)){
                $bkeaddpool = $inboundNatRule.BackendAddressPool.Id
            }
            else{
                $bkeaddpool = (Get-AzLoadBalancerBackendAddressPool -LoadBalancer $StdLoadBalancer -Name ($inboundNatRule.BackendAddressPool.Id).split('/')[-1])
            }

            $inboundNatRuleConfig = @{
                Name                    = $inboundNatRule.Name
                Protocol                = $inboundNatRule.Protocol
                FrontendPort            = $inboundNatRule.FrontendPort
                BackendPort             = $inboundNatRule.BackendPort
                IdleTimeoutInMinutes    = $inboundNatRule.IdleTimeoutInMinutes
                EnableFloatingIP        = $inboundNatRule.EnableFloatingIP
                EnableTcpReset          = $inboundNatRule.EnableTcpReset
                FrontendIpConfiguration = (Get-AzLoadBalancerFrontendIpConfig -LoadBalancer $StdLoadBalancer -Name ($inboundNatRule.FrontendIpConfiguration.Id).split('/')[-1])
                FrontendPortRangeStart  = $inboundNatRule.FrontendPortRangeStart
                FrontendPortRangeEnd    = $inboundNatRule.FrontendPortRangeEnd
                BackendAddressPool      = $bkeaddpool
            }
            $StdLoadBalancer | Add-AzLoadBalancerInboundNatRuleConfig @inboundNatRuleConfig > $null
        }
        catch {
            $message = @"
            [NatRulesMigration] Failed to add inbound nat rule config '$($inboundNatRule.Name)' to new standard load balancer '$($stdLoadBalancer.Name)' in resource
            group '$($StdLoadBalancer.ResourceGroupName)'. Migration will continue, FAILED RULE WILL NEED TO BE MANUALLY ADDED to the load balancer. Error: $_
"@
            log "Error" $message
        }
    }
    log -Message "[NatRulesMigration] Saving Standard Load Balancer $($StdLoadBalancer.Name)"

    try {
        $ErrorActionPreference = 'Stop'
        Set-AzLoadBalancer -LoadBalancer $StdLoadBalancer > $null
    }
    catch {
        $message = @"
        [NatRulesMigration] Failed to update new standard load balancer '$($stdLoadBalancer.Name)' in resource
        group '$($StdLoadBalancer.ResourceGroupName)' after attempting to add migrated inbound NAT rule
        configurations. Migration will continue, INBOUND NAT RULES WILL NEED TO BE MANUALLY ADDED to the load
        balancer. Error: $_
"@
        log "Error" $message
    }
    log -Message "[NatRulesMigration] Nat Rules Migration Completed"
}

Export-ModuleMember -Function NatRulesMigration