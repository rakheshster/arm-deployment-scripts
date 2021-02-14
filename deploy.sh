#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

function usage() {
	blue=$(tput setaf 4)
	normal=$(tput sgr0)
	powder_blue=$(tput setaf 153)
	bold=$(tput bold)
	underline=$(tput smul)
	# https://stackoverflow.com/questions/4332478/read-the-current-text-color-in-a-xterm/4332530#4332530 more colours

    printf "%s\n\n" "${blue}Usage:${normal} $0 -g <resourceGroupName> -d <artifactsStagingDirectory> [-l <resourceGroupLocation>] [-s <artifactsStorageAccount>] [-t <templateFilePath>] [-p <parametersFilePath>]" 1>&2; 

	printf "%s\n\n" "${powder_blue}Note:${normal} if the template contains an ${bold}_artifactsLocation${normal} parameter then the contents of <artifactsStagingDirectory> will be uploaded to a storage account you specify via <artifactsStorageAccount> (or ${underline}a random storage account will be created for this purpose${normal})"  1>&2;
	exit 1;
}

# check if we are logged in and exit script if not.
# this is a little workaround to see if we are still logged in. the `list-locations` subcommand needs you to be logged in.
# other `az account` subcommands seem to rely on cached information.
az account list-locations || exit 1

# check for the jq command
if ! command -v jq &> /dev/null; then echo "Cannot find jq. Please install it and retry."; exit 1; fi

# Initialize parameters specified from command line
while getopts ":g:d:s:l:t:p:" o; do
	case "${o}" in
		g)
			resourceGroupName=${OPTARG}
			;;
		d)
			artifactsStagingDirectory=${OPTARG}
			;;
		l)
			resourceGroupLocation=${OPTARG}
			;;
        s) 
			artifactsStorageAccount=${OPTARG}
            ;;
		t)
			templateFilePath=${OPTARG}
			;;
		p)
			parametersFilePath=${OPTARG}
			;;
	esac
done
shift $((OPTIND-1))

# Show usage and exit if mandatory parameters are not specified
if [ -z $artifactsStagingDirectory ]; then 
	usage
fi

# Show usage and exit if mandatory parameters are not specified
if [ -z "$resourceGroupName" ]; then
	usage
else
	# check if the resourcegroup exists
	testResourceGroup=$(az group show --name ${resourceGroupName} 2>/dev/null)
	if [ $? -eq 0 ];
		# all good, let's capture the location for future use
		resourceGroupLocation=$(az group show --name ${resourceGroupName} | jq -r '.location')
		echo "Specified resource group ${resourceGroupName} exists at location ${resourceGroupLocation}"
	else
		if [ ! -z $resourceGroupLocation ]; then
			# the resource group doesn't exist but we do have a location so let's create one
			echo "Couldn't find resource group ${resourceGroupName} so will create a new one at location ${resourceGroupLocation}"
			az group create --name $resourceGroupName --location $resourceGroupLocation
		else
			echo "Unable to find resource group ${resourceGroupName} and no location's specified to create a new one"
			exit 1
		fi
	fi
fi

# default templatefile if none specified
if [ -z "$templateFilePath" ]; then
	templateFilePath="${artifactsStagingDirectory}/azuredeploy.json"
	
	if [ -f "templateFilePath" ]; 
		echo "Found and will use ${templateFilePath} as the template"
	else
		echo "Missing templateFilePath. Tried ${templateFilePath}"
		exit 1
	fi
fi

# default parametersfile if none specified
if [ -z "$parametersFilePath" ]; then
	parametersFilePath="${artifactsStagingDirectory}/azuredeploy.parameters.json"

	if [ -f "parametersFilePath" ]; 
		echo "Found and will use ${parametersFilePath} as the parameters file"
	else
		echo "Continuing without a parameters file as none was specifed and nothing found at ${parametersFilePath} either"
		unset parametersFilePath
	fi
fi

unset uploadRequired
unset artifactsUrlRequired
# Check the template file to see if there's any mention of artifacts
# jq doesn't like comments so I strip them out first
testForArtifacts=$(grep -v "^\s*//" ${templateFilePath} | jq '.parameters._artifactsLocation')
if [ $testForArtifacts == "null" ]; then
	uploadRequired=false
else
	uploadRequired=true
fi

# if there is mention of artifacts then we must upload to the storage account
if [ $uploadRequired == true ];
	# explictly unset this variable so I know it's not set at the beginning of this 
	unset artifactsLocation
	unset artifactsLocationSasToken
	unset createstorageaccount

	# if there's a parameters file read it for the value of artifacts location & token
	if [ ! -z "$parametersFilePath" ]
		artifactsLocation=$(grep -v "^\s*//" ${parametersFilePath} | jq '.parameters._artifactsLocation.value')
	fi

	# if I found something above the variable wouldn't be null (no property) or "" (no value set). or it would still be unset if we don't have a params file.
	# if this is the case read from the template file to see if it has a defaultValue
	if [ -z $artifactsLocation ] || [ $artifactsLocation == "" ] || [ $artifactsLocation == "null" ]; 
		artifactsLocation=$(grep -v "^\s*//" ${templateFilePath} | jq '.parameters._artifactsLocation.defaultValue')
	fi

	# if it is empty still that means we don't have any location specified. 
	# so we'll have to provide the URL of the storage account as a parameter later
	if [ -z $artifactsLocation ] || [ $artifactsLocation == "" ];
		artifactsUrlRequired=true
	fi

	# I will create a container that has the resourceGroupName (in lower letters) with -stageartifacts suffixed
	resourceGroupNameLower=$(echo $resourceGroupName | tr "[:upper:]" "[:lower:]" | cut -c1-20)
	containername="${resourceGroupNameLower}-stageartifacts"

	# was any storage account specified? 
	if [ -z "$artifactsStorageAccount" ]; then
		# if no storage account is specified get our subscription id, strip dashes, extract the first 10 chars
		tempId=$(az account show | jq -r '.id' | tr -d '-' | cut -c1-10)
		# add that to some random numbers ($RANDOM is an in-built bash variable) to create a storage account name
		artifactsStorageAccount="stage${tempId}${RANDOM}"
		createstorageaccount=true
		echo "No storage account was specified. Will create ${artifactsStorageAccount}"
	else 
		# a storage account was specified, lets see if it exists
		testForStorageAccount=$(az storage account check-name --name ${artifactsStorageAccount} | jq '.nameAvailable')
		if [ $testForStorageAccount == "true" ]; 
			# the account does not exist, we need to create it
			createstorageaccount=true
			echo "Specified storage account ${artifactsStorageAccount} does not exist and will be created"
		else
			# the account exists and we can use that
			createstorageaccount=false
			echo "Found storage account ${artifactsStorageAccount}"
			# create the container within this storage account
			az storage container create -n ${containername} --account-name ${artifactsStorageAccount}
		fi
	fi

	# create a storage account if required
	if [ $createstorageaccount == true ]; then
		az storage account create -n $artifactsStorageAccount -g $resourceGroupName -l $resourceGroupLocation --sku Standard_LRS
		
		# if that went well create the container
		if [ $? -eq 0 ]; then
			az storage container create -n ${containername} --account-name ${artifactsStorageAccount}
		else
			echo "Error creating a storage account ${artifactsStorageAccount}"
			exit 1
	fi	

	# generate a SAS token and URL as we need it (there was nothing found in the template/ parameters file above)
	if [ $artifactsUrlRequired == true ];
		# generate a SAS token
		if [ $(uname) == "Darwin" ]; then
			sasexpiry=`date -v+2H '+%Y-%m-%dT%H:%MZ'`
		else
			sasexpiry=`date -u -d "2 hours" '+%Y-%m-%dT%H:%MZ'`
		fi
		artifactsLocationSasToken=$(az storage container generate-sas --account-name ${artifactsStorageAccount} --as-user --auth-mode login --expiry $sasexpiry --name ${containername} --permissions r)
		artifactsLocationBlobEndpoint=$(az storage account show --name ${artifactsStorageAccount} | jq -r '.primaryEndpoints.blob')
		artifactsLocation="${artifactsLocationBlobEndpoint}${containername}/"
	fi

	# now let's upload
	# loop through each file in the staging directory and upload
	for filename in ${artifactsStagingDirectory}/*; do
		az storage blob upload --name $(basename $filename) --container-name ${containername} --file $filename --account-name ${artifactsStorageAccount}
	done
fi

# Start deployment
echo "Starting deployment..."
if [ $artifactsUrlRequired == false ];
	az group deployment create --resource-group $resourceGroupName --template-file $templateFilePath --parameters-file $parametersFilePath
else
	az group deployment create --resource-group $resourceGroupName --template-file $templateFilePath --parameters-file $parametersFilePath --parameters _artifactsLocation=${artifactsLocation} --parameters _artifactsLocationSasToken=${artifactsLocationSasToken}
fi