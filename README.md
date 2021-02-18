# What is this?

When I started with ARM some years ago the exported template from Azure had a bunch of deployment scripts. I never used them but I wanted to take a look at them today (Feb 2021) and couldn't find them anymore. Looks like the default exported templates don't contain these any more. Sounds like these scripts were present as late as 2019 as I found mention of them on [this blog post](https://iddles.co.uk/index.php/2019/11/09/azure-arm-concepts/). 

Luckily I had an older exported template lying around and it had these scripts so I'll put them up here in the `originals` folders. 

These default scripts are pretty limited though. I have since come across two other PowerShell scripts that are also able to upload files from an `artifacts` folder such that you can run it on a deployed VM. Take a look at [this blog post](https://www.wintellect.com/arm-templates-and-cloud-init/) for the general idea. For some background on the `_artifactsLocation` parameter [another post from the same author](https://www.wintellect.com/devops-understanding-arm-artifactslocation/) is worth a read.

I found a Bash version that sort of does this in the official quick start templates at [this link](https://github.com/Azure/azure-quickstart-templates/blob/master/201-vmss-ubuntu-web-ssl/deploy.sh). And the PowerShell version can be found at [this link](https://github.com/Azure/azure-quickstart-templates/blob/master/Deploy-AzTemplate.ps1). I didn't want to risk losing them so I've added these to this repo. 

While this repo began as a place to put the original scripts I am now using it to focus mainly on the two PowerShell and one Bash scripts. To make it easy for others I have tagged a `v0` release so anyone looking for the official version of these scripts can use that instead. 

# The PowerShell script
Here's what the PowerShell script `Deploy-AzTemplate.ps1` does. (A quick reminder, I didn't create this so this is mostly me working backwards to understand what it does). I made some cosmetic changes to the script and made it a bit OS agnostic, but otherwise it is pretty much how I found it. 

  * It expects a `$ArtifactStagingDirectory` variable pointing to a local directory containing artifacts to upload and a `$ResourceGroupLocation` variable pointing to an Azure location. 
  * If the specified `$resourceGroupName` does not exist it creates on at `$ResourceGroupLocation`.
  * If not manually specified, it expects the template and parameters file to be in this `$ArtifactStagingDirectory` directory along with any other files to upload. 
  * It checks the template and parameter files for any mention of an `_artifactsLocation` parameter. If there is then it assumes we need to upload from the `$ArtifactStagingDirectory`. If there is no mention of an `_artifactsLocation` parameter it does nothing. 
  * There's a special case too like do an upload anyways via an `$UploadArtifacts` parameter irrespective of `_artifactsLocation` being present or not.
  * If an upload is required and you have specified a storage account name `$StorageAccountName` but it does not exist, the script creates it at location `$ResourceGroupLocation` in a new resource group called `ARM_Deploy_Staging`; and then uploads the contents of `$ArtifactStagingDirectory` to a container it creates within this storage account in either case. 
  * It also checks if `_artifactsLocation` parameter actually has any value (in the template or parameters). If there is a value then it is assumed it must be pointing to a URL in the storage account that was specified so we don't really need to do anything. If there is no value then it generates a URL and SAS token to the storage account that was created and passes that to the actual deployment cmdlet. 

# The Bash script
The original Bash script `deploy.sh` did none of the above. Moreover it used the older `azure` than newer `az` commands so was in need of a huge update. I have reworked it entirely to now be kind of on-par with the PowerShell script. There are some differences in terms of its parameters (e.g. there's no parameter to upload artifacts anyways, and I don't create the storage account in a new resource group called `ARM_Deploy_Staging` but reuse the existing one). Other than these it does pretty much everything else and I am quite pleased with it. This was something I undertook just for kicks (get familiar with the `az` commands and do some Bash scripting). Thanks to PowerShell Core one can use the PowerShell scripts from macOS or Linux and so we don't really need a Bash script. 
