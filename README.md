# What is this?

This repo is probably of not much use to anyone but I wanted to put it up in GitHub just in case anyways. 

When I started with ARM some years ago the exported template from Azure had a bunch of deployment scripts. I never used them but I wanted to take a look at them today and couldn't find them anymore. Looks like the default exported templates don't contain these any more. Sounds like these scripts were present as late as 2019 as I found mention of them on [this blog post](https://iddles.co.uk/index.php/2019/11/09/azure-arm-concepts/). 

Luckily I had an older exported template lying around and it had these scripts so I'll put them up here in the `originals` folders. 

These default scripts are pretty limited though. I have since come across two other PowerShell scripts that are also able to upload files from an `artifacts` folder such that you can run it on a deployed VM. Take a look at [this blog post](https://www.wintellect.com/arm-templates-and-cloud-init/) for the general idea. For some background on the `_artifactsLocation` parameter [another post from the same author](https://www.wintellect.com/devops-understanding-arm-artifactslocation/) is worth a read.

I found a Bash version that sort of does this in the official quick start templates at [this link](https://github.com/Azure/azure-quickstart-templates/blob/master/201-vmss-ubuntu-web-ssl/deploy.sh). And the PowerShell version can be found at [this link](https://github.com/Azure/azure-quickstart-templates/blob/master/Deploy-AzTemplate.ps1). I didn't want to risk losing them so I've added these to this repo. 

I might modify these scripts so I've tagged a `v0` release so anyone looking for the official version of these scripts can use that instead. 

# Updates
I have modified the two PowerShell scripts to make them more OS agnostic. 

## The PowerShell script
Here's what the PowerShell script `Deploy-AzTemplate.ps1` does. (A quick reminder, I didn't create this so this is mostly me working backwards to understand what it does). 

  * It expects a `$ArtifactStagingDirectory` variable pointing to a local directory containing artifacts to upload and a `$ResourceGroupLocation` variable pointing to an Azure location. 
  * If not manually specified, it expects the template and parameters file to be in this `$ArtifactStagingDirectory` directory along with any other files to upload. 
  * It checks the template and parameter files for any mention of an `_artifactsLocation` parameter. If there is then it assumes we need to upload from the `$ArtifactStagingDirectory`. If there is no mention of an `_artifactsLocation` parameter it does nothing. 
  * There's a special case too like do an upload anyways via an `$UploadArtifacts` parameter irrespective of `_artifactsLocation` being present or not.
  * If an upload is required and you have specified a storage account name `$StorageAccountName` it creates it if it does not already exist (this is where the Azure location `$ResourceGroupLocation` comes into play); and uploads the contents of `$ArtifactStagingDirectory` to a container it creates within this storage account in either case. 
  * It also checks if `_artifactsLocation` parameter actually has any value (in the template or parameters). If there is a value then it is assumed it must be pointing to a URL in the storage account that was specified so we don't really need to do anything. If there is no value then it generates a URL and SAS token to the storage account that was created and passes that to the actual deployment cmdlet. 

## The Bash script
The Bash script `deploy.sh` does none of this but I am working on it to sort of bring it up to par with the PowerShell script. Also, it was using the older `azure` commands than the newer `az` ones so was broken to begin. I may or may not succeed as I am doing it mainly for kicks. Thanks to PowerShell Core one can use the PowerShell scripts from macOS or Linux and so we don't really need the Bash script. 

*Note*: As long as this warning is present please consider `deploy.sh` as not working. 