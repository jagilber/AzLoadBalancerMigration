cd .\modules\BacakupBasicLoadBalancer
New-ModuleManifest -Path BackupBasicLoadBalancer.psd1 -RootModule BackupBasicLoadBalancer -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru
cd ../../


New-ModuleManifest -Path Start-AzBasicLoadBalancerMigration.psd1 -RootModule Start-AzBasicLoadBalancerMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru


New-ModuleManifest -Path Log.psd1 -RootModule Log -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path PublicFEMigration.psd1 -RootModule PublicFEMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path RemoveLBFromVMSS.psd1 -RootModule RemoveLBFromVMSS -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path BackendPoolMigration.psd1 -RootModule BackendPoolMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path NatRulesMigration.psd1 -RootModule NatRulesMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path UpdateVmssInstances.psd1 -RootModule UpdateVmssInstances -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path ProbesMigration.psd1 -RootModule ProbesMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path LoadBalacingRulesMigration.psd1 -RootModule LoadBalacingRulesMigration -Author "Victor Santana" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path InboundNatPoolsMigration.psd1 -RootModule InboundNatPoolsMigration -Author "Matthew Bratschun" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path OutboundRulesCreation.psd1 -RootModule OutboundRulesCreation -Author "Matthew Bratschun" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path NSGCreation.psd1 -RootModule NSGCreation -Author "Matthew Bratschun" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path ValidateScenario.psd1 -RootModule ValidateScenario -Author "Matthew Bratschun" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru

New-ModuleManifest -Path ScenariosMigration.psd1 -RootModule ScenariosMigration -Author "Matthew Bratschun" -CompanyName "Microsoft" -Copyright "(c) 2022 Microsoft. All rights reserved." -FunctionsToExport '*' -CmdletsToExport '*' -AliasesToExport '*'  -PassThru