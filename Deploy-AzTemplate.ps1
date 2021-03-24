#Requires -Version 3.0
#Requires -Module Az.Resources
#Requires -Module Az.Storage

Param(
    [string] [Parameter(Mandatory = $true)] $ArtifactStagingDirectory,
    [string] [Parameter(Mandatory = $true)][alias("ResourceGroupLocation")] $Location,
    [string] $ResourceGroupName = (Split-Path $ArtifactStagingDirectory -Leaf),
    [switch] $UploadArtifacts,
    [string] $StorageAccountName,
    [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
    [string] $TemplateFile = $(if ($PSVersionTable.Platform -ne "Unix") { $ArtifactStagingDirectory + '\azuredeploy.json' } else { $ArtifactStagingDirectory + '/azuredeploy.json' }),
    [string] $TemplateParametersFile = $(if ($PSVersionTable.Platform -ne "Unix") { $ArtifactStagingDirectory + '\azuredeploy.parameters.json' } else { $ArtifactStagingDirectory + '/azuredeploy.parameters.json' }),
    [string] $DSCSourceFolder = $(if ($PSVersionTable.Platform -ne "Unix") { $ArtifactStagingDirectory + '\DSC' } else { $ArtifactStagingDirectory + '/DSC' }),
    [switch] $BuildDscPackage,
    [switch] $ValidateOnly,
    [string] $DebugOptions = "None",
    [string] $Mode = "Incremental",
    [string] $DeploymentName = ((Split-Path $TemplateFile -LeafBase) + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')),
    [switch] $Dev
)

try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("AzQuickStarts-$UI$($host.name)".replace(" ", "_"), "1.0")
}
catch { }

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Format-ValidationOutput {
    param ($ValidationOutput, [int] $Depth = 0)
    Set-StrictMode -Off
    return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
}

$OptionalParameters = New-Object -TypeName Hashtable
$TemplateArgs = New-Object -TypeName Hashtable
$ArtifactStagingDirectory = ($ArtifactStagingDirectory.TrimEnd('/')).TrimEnd('\')

Write-Host "Using template file:  $TemplateFile"

#try a few different default options for param files when the -dev switch is use
if ($Dev) {
    $TemplateParametersFile = $TemplateParametersFile.Replace('azuredeploy.parameters.json', 'azuredeploy.parameters.dev.json')
    if (!(Test-Path $TemplateParametersFile)) {
        $TemplateParametersFile = $TemplateParametersFile.Replace('azuredeploy.parameters.dev.json', 'azuredeploy.parameters.1.json')
    }
}

Write-Host "Using parameter file: $TemplateParametersFile"

if (!$ValidateOnly) {
    $OptionalParameters.Add('DeploymentDebugLogLevel', $DebugOptions)
}

$TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$TemplateParametersFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))

$TemplateJSON = Get-Content $TemplateFile -Raw | ConvertFrom-Json

$TemplateSchema = $TemplateJson | Select-Object -expand '$schema' -ErrorAction Ignore

# When you are deploying to a subscription (e.g. deploying a resource group to a subscription) the schema looks like this https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#
# When you are deploying to a resource group the schema looks like this https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#
if ($TemplateSchema -like '*subscriptionDeploymentTemplate.json*') {
    $deploymentScope = "Subscription"
}
else {
    $deploymentScope = "ResourceGroup"
    $OptionalParameters.Add('Mode', $Mode)
}

Write-Host "Running a $deploymentScope scoped deployment..."

# Parse the template file to see if there's any mention of the _artifactsLocation. 
# If there is something then $useAbsolutePathStaging is set to $true - this is a signal to upload stuff to this location later.
# Note: at this point we don't actually read the value of what's set there. All we care about is whether this template has an _artifactsLocation paramter or not.
# The actual value of this paramter is read from the paramters file a few steps later. 
$ArtifactsLocationName = '_artifactsLocation'
$ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
$ArtifactsLocationParameter = $TemplateJson | Select-Object -expand 'parameters' -ErrorAction Ignore | Select-Object -Expand $ArtifactsLocationName -ErrorAction Ignore
$useAbsolutePathStaging = $($ArtifactsLocationParameter -ne $null)

# If the switch is set or the standard parameter is present in the template, upload all artifacts
if ($UploadArtifacts -Or $useAbsolutePathStaging) {
    # Convert relative paths to absolute paths if needed
    $ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
    $DSCSourceFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCSourceFolder))

    # Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
    if (Test-Path $TemplateParametersFile) {
        $JsonParameters = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
        if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
            $JsonParameters = $JsonParameters.parameters
        }
    }
    else {
        $JsonParameters = @{ }
    }
    # if using _artifacts* parameters, add them to the optional params and get the value from the param file (if any)
    if ($useAbsolutePathStaging) {
        $OptionalParameters[$ArtifactsLocationName] = $JsonParameters | Select-Object -Expand $ArtifactsLocationName -ErrorAction Ignore | Select-Object -Expand 'value' -ErrorAction Ignore
        $OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select-Object -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select-Object -Expand 'value' -ErrorAction Ignore
    }
    # Create DSC configuration archive
    if ((Test-Path $DSCSourceFolder) -and ($BuildDscPackage)) {
        $DSCSourceFilePaths = @(Get-ChildItem $DSCSourceFolder -File -Filter '*.ps1' | ForEach-Object -Process { $_.FullName })
        foreach ($DSCSourceFilePath in $DSCSourceFilePaths) {
            $DSCArchiveFilePath = $DSCSourceFilePath.Substring(0, $DSCSourceFilePath.Length - 4) + '.zip'
            Publish-AzVMDscConfiguration $DSCSourceFilePath -OutputArchivePath $DSCArchiveFilePath -Force -Verbose
        }
    }

    # Create a storage account name if none was provided
    if ($StorageAccountName -eq '') {
        $StorageAccountName = 'stage' + ((Get-AzContext).Subscription.Id).Replace('-', '').substring(0, 8) + (Get-Random -Maximum 999)
    }

    Write-Host "Storage account name: $StorageAccountName..."

    $StorageAccount = (Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName })

    # Create the storage account if it doesn't already exist
    if ($StorageAccount -eq $null) {
        $StorageResourceGroupName = 'ARM_Deploy_Staging'
        Write-Host "Creating Storage account..."
        if ((Get-AzResourceGroup -Name $StorageResourceGroupName -Verbose -ErrorAction SilentlyContinue) -eq $null) {
            New-AzResourceGroup -Name $StorageResourceGroupName -Location $Location -Verbose -Force -ErrorAction Stop
        }
        $StorageAccount = New-AzStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $StorageResourceGroupName -Location "$Location"
    }

    if ($StorageContainerName.length -gt 63) {
        $StorageContainerName = $StorageContainerName.Substring(0, 63)
    }
    $ArtifactStagingLocation = $StorageAccount.Context.BlobEndPoint + $StorageContainerName + "/"   

    # Generate the value for artifacts location if it is not provided in the parameter file
    if ($useAbsolutePathStaging -and $OptionalParameters[$ArtifactsLocationName] -eq $null) {
        # If the defaultValue for _artifactsLocation is using the template location, use the defaultValue, otherwise set it to the staging location
        $defaultValue = $ArtifactsLocationParameter | Select-Object -Expand 'defaultValue' -ErrorAction Ignore
        if ($defaultValue -like '*deployment().properties.templateLink.uri*') {
            $OptionalParameters.Remove($ArtifactsLocationName) # just use the defaultValue if it's using the template language function
        }
        else {
            $OptionalParameters[$ArtifactsLocationName] = $ArtifactStagingLocation   
        }
    } 

    #Write-Host ($StorageAccount | Out-String)

    # Copy files from the local storage staging location to the storage account container
    New-AzStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

    $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process { $_.FullName }
    foreach ($SourcePath in $ArtifactFilePaths) {
        
        if ($SourcePath -like "$DSCSourceFolder*" -and $SourcePath -like "*.zip" -or !($SourcePath -like "$DSCSourceFolder*")) {
            #When using DSC, just copy the DSC archive, not all the modules and source files
            $blobName = ($SourcePath -ireplace [regex]::Escape($ArtifactStagingDirectory), "").TrimStart("/").TrimStart("\")
            Set-AzStorageBlobContent -File $SourcePath -Blob $blobName -Container $StorageContainerName -Context $StorageAccount.Context -Force
        }
    }
    # Generate a 2 hour SAS token for the artifacts location if one was not provided in the parameters file
    if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
        $OptionalParameters[$ArtifactsLocationSasTokenName] = (New-AzStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(2))
    }

    $TemplateArgs.Add('TemplateUri', $ArtifactStagingLocation + (Get-ChildItem $TemplateFile).Name + $OptionalParameters[$ArtifactsLocationSasTokenName])

    # The original version of this template converted the above $OptionalParameters[$ArtifactsLocationSasTokenName] to a SecureString
    # When I did that the deployment failed with an error: "Expected 'String, Uri'. Actual 'Object'" 
    # This was on macOS, so PowerShell Core. Could be this issue? https://github.com/Azure/azure-powershell/issues/6292
    # So I decided to skip SecureString. It's a short lived token anyways. 
    # $OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString $OptionalParameters[$ArtifactsLocationSasTokenName] -AsPlainText -Force

}
else {

    $TemplateArgs.Add('TemplateFile', $TemplateFile)

}

if(Test-Path $TemplateParametersFile){
    $TemplateArgs.Add('TemplateParameterFile', $TemplateParametersFile)
}

#Write-Host "Template Args:"
#Write-Host ($TemplateArgs | Out-String)

#Write-Host "Optional Params:"
#Write-Host ($OptionalParameters | Out-String)

# Create the resource group only when it doesn't already exist - and only in RG scoped deployments
if ($deploymentScope -eq "ResourceGroup") {
    if ((Get-AzResourceGroup -Name $ResourceGroupName -Location $Location -Verbose -ErrorAction SilentlyContinue) -eq $null) {
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Verbose -Force -ErrorAction Stop
    }
}
if ($ValidateOnly) {
    if ($deploymentScope -eq "Subscription") {
        #subscription scoped deployment
        $ErrorMessages = Format-ValidationOutput (Test-AzDeployment -Location $Location @TemplateArgs @OptionalParameters)
    }
    else {
        #resourceGroup deployment 
        $ErrorMessages = Format-ValidationOutput (Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName @TemplateArgs @OptionalParameters)
    }
    if ($ErrorMessages) {
        Write-Output '', 'Validation returned the following errors:', @($ErrorMessages), '', 'Template is invalid.'
    }
    else {
        Write-Output '', 'Template is valid.'
    }
}
else {

    $ErrorActionPreference = 'Continue' # Switch to Continue" so multiple errors can be formatted and output
    if ($deploymentScope -eq "Subscription") {
        #subscription scoped deployment
        New-AzDeployment -Name $DeploymentName `
            -Location $Location `
            @TemplateArgs `
            @OptionalParameters `
            -Verbose `
            -ErrorVariable ErrorMessages
    }
    else {
        New-AzResourceGroupDeployment -Name $DeploymentName `
            -ResourceGroupName $ResourceGroupName `
            @TemplateArgs `
            @OptionalParameters `
            -Force -Verbose `
            -ErrorVariable ErrorMessages
    }
    $ErrorActionPreference = 'Stop' 
    if ($ErrorMessages) {
        Write-Output '', 'Template deployment returned the following errors:', '', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message })
        Write-Error "Deployment failed."
    }

}