# What is this?

When I started with ARM some years ago the exported template from Azure had a bunch of deployment scripts. I never used them but I wanted to take a look at them today and couldn't find them anymore. Looks like the default exported templates don't contain these any more. Sounds like these scripts were present as late as 2019 as I found mention of them on [this blog post](https://iddles.co.uk/index.php/2019/11/09/azure-arm-concepts/). 

Luckily I had an older exported template lying around and it had these scripts so I'll put them up here. 

These default scripts are pretty limited though. I have since come across two other scripts that are also able to upload files from an `artifacts` folder such that you can run it on a deployed VM. Take a look at [this blog post](https://www.wintellect.com/arm-templates-and-cloud-init/) for the general idea. 

I found a bash version that does this in the official quick start templates at [this link](https://github.com/Azure/azure-quickstart-templates/blob/master/201-vmss-ubuntu-web-ssl/deploy.sh). And the PowerShell version can be found at [this link](https://github.com/Azure/azure-quickstart-templates/blob/master/Deploy-AzTemplate.ps1). I didn't want to risk losing them so I've added these to this repo. 