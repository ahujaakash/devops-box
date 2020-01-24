#!/bin/bash -x

#
# Initializing global variables
#
#how to use it
# ../../par/per/core/pipeline1.json

function parametarize {
    # Regular Colors for shell outputs
    # export Red=`tput setaf 1`          # Red
    # export Green=`tput setaf 2`        # Green
    # export Yellow=`tput setaf 3`       # Yellow
    # export Blue=`tput setaf 4`         # Blue
    # export Purple=`tput setaf 5`       # Purple
    # export Cyan=`tput setaf 6`         # Cyan
    # export Color_Off=`tput sgr0`       # Text Reset

    for var in "$@"
    do
        echo "Parameter: ${var}"
    done

    echo "Setting parameters ..."
    export ENV="$1"
    export UNIT="$2"

    export SCRIPT_DIR=$(cd $(dirname "$0") && pwd);
    export BACKEND_FILE="backend.tf"

    export ROOT_DIR=$( cd ${SCRIPT_DIR}/../.. && pwd )
    export ENV_DIR="$ROOT_DIR/env"
    export PARAMETERS_FILE_INI="$ROOT_DIR/par/$ENV/$UNIT/vars.json"
    export PARAMETERS_FILE=$PARAMETERS_FILE_INI
}

#
# Prepare environment
#

# build params based on json file location
params=`echo $1 | awk -F"/par/" '{print $2}' | tr / " " | awk 'NF{NF-=1};1'`
parametarize $params

cd $SCRIPT_DIR
IFS=$'\n'

#
# Terraform Inicializing
#

function terraformInitialize {
    OUTPUT_FOLDER="../jsonoutput"
    JSON_NAME="output-$ENV-$UNIT.json"

    ##change the subscription
    sub_id=`cat $PARAMETERS_FILE_INI | jq .parameters.configurationSettings.value.name.subscriptionId | tr -d '"'`

    #echo "${Purple}changing subscription to $ENV $UNIT ${Color_Off}"
    #az account set --subscription $sub_id
    tenant_id=`az account show --query tenantId | tr -d '"'`

    name=`cat $PARAMETERS_FILE_INI | jq .parameters.terraformSettings.value.name.spn | tr -d '"'`
    appId=`cat $PARAMETERS_FILE_INI | jq .parameters.terraformSettings.value.name.id | tr -d '"'`
    vault=`cat $PARAMETERS_FILE_INI | jq .parameters.terraformSettings.value.name.vault | tr -d '"'`

    fullname=$name
    echo "retrieving $fullname, $appId in $vault"

    password=`az keyvault secret show --name $fullname --vault-name $vault --query value | tr -d '"'`

    echo "Setting environment variables for Terraform"
    echo "Setting ARM_SUBSCRIPTION_ID=$sub_id"
    export ARM_SUBSCRIPTION_ID=$sub_id
    echo "Setting ARM_CLIENT_ID=$appId"
    export ARM_CLIENT_ID=$appId
    echo "Setting ARM_CLIENT_SECRET=$password"
    export ARM_CLIENT_SECRET=$password
    echo "Setting ARM_TENANT_ID=$tenant_id"
    export ARM_TENANT_ID=$tenant_id

    # Not needed for public, required for usgovernment, german, china
    export ARM_ENVIRONMENT=public

    echo "${Cyan}environment variables are ready for terraform! ${Color_Off}"

    #logging in with spn cred
    #echo "logging in with spn cred..."
    #az login --service-principal -u $fullname -p $password --tenant $tenant_id
    #echo "loging in with Service Principal account ..."
    #echo "az login --service-principal --username $appId --password $password --tenant $tenant_id"
    #az login --service-principal --username $appId --password $password --tenant $tenant_id
    #az vm list-sizes --location westus

    #Reading the key pairs from the keyvault and put it in the user directory
    echo "Downloading keys..."
    kvName=`cat $PARAMETERS_FILE_INI | jq .parameters.keySettings.value.keyvaultName | tr -d '"'`
    privKey=`cat $PARAMETERS_FILE_INI | jq .parameters.keySettings.value.privateKey | tr -d '"'`
    publicKey=`cat $PARAMETERS_FILE_INI | jq .parameters.keySettings.value.publicKey | tr -d '"'`
    chefKey=`cat $PARAMETERS_FILE_INI | jq .parameters.keySettings.value.chefKey | tr -d '"'`
    winChefKey=`cat $PARAMETERS_FILE_INI | jq .parameters.keySettings.value.winChefKey | tr -d '"'`
    encryptorKey=`cat $PARAMETERS_FILE_INI | jq .parameters.keySettings.value.encryptor | tr -d '"'`

    #private key
    echo "private key"
    echo "az keyvault secret show --vault-name $kvName --name $privKey"
    #az keyvault secret show --vault-name $kvName --name $privKey
    az keyvault secret show --vault-name $kvName --name $privKey | jq -r .value > ~/.ssh/$privKey
    #public key
    echo "public key"
    echo "az keyvault secret show --vault-name $kvName --name $publicKey"
    #az keyvault secret show --vault-name $kvName --name $publicKey
    az keyvault secret show --vault-name $kvName --name $publicKey | jq -r .value > ~/.ssh/$publicKey

    echo "chef key"
    echo "az keyvault secret show --vault-name $kvName --name $chefKey"
    #az keyvault secret show --vault-name $kvName --name $chefKey
    az keyvault secret show --vault-name $kvName --name $chefKey | jq -r .value > ~/.ssh/$chefKey

    echo "win Chef key"
    echo "az keyvault secret show --vault-name $kvName --name $winChefKey"
    #az keyvault secret show --vault-name $kvName --name $chefKey
    az keyvault secret show --vault-name $kvName --name $winChefKey | jq -r .value > ~/.ssh/$winChefKey

    echo "encryptor key"
    echo "az keyvault secret show --vault-name $kvName --name $encryptorKey"
    #az keyvault secret show --vault-name $kvName --name $chefKey
    az keyvault secret show --vault-name $kvName --name $encryptorKey | jq -r .value > ~/.ssh/$encryptorKey

    #chmod
    sudo chmod -R 700 ~/.ssh
    sudo chmod 600 ~/.ssh/*
}

#
# Terraform Processing
#
echo "Above function Terraform processing"

function terraformProcessing {
    echo "Inside TerraformProcessing"
    export plan="$1"

    #provider set up
    #copy the provider.tf from script to the location
    cp ../../../../../../script/provider.tf ./provider-transit.tf
    #fill out the provide with values
    sed -i 's|^  subscription_id =.*|  subscription_id = "'$sub_id'"|' ./provider-transit.tf
    sed -i 's|^  client_id       =.*|  client_id       = "'$appId'"|' ./provider-transit.tf
    sed -i 's|^  client_secret   =.*|  client_secret   = "'$password'"|' ./provider-transit.tf
    sed -i 's|^  tenant_id       =.*|  tenant_id       = "'$tenant_id'"|' ./provider-transit.tf

    storage=`cat $PARAMETERS_FILE | jq .parameters.terraformSettings.value.name.storage | tr -d '"'`
    resourceGroup=`cat $PARAMETERS_FILE | jq .parameters.terraformSettings.value.name.resourceGroup | tr -d '"'`

    #key is the path from the current directory up to 4 level (the last 4 slashes from `pwd`)
    key=`echo $PWD | awk -F/ '{print $(NF-3)"/"$(NF-2)"/"$(NF-1)"/"$NF"/terraform.tfstate"}'`

    access_key=`az storage account keys list -n $storage -g $resourceGroup | jq .[1].value | tr -d '"'`

    #write down the key and access key to backend.tf
    echo "updating backend.tf"
    sed -i 's|^    access_key           =.*|    access_key           = "'$access_key'"|' $BACKEND_FILE
    sed -i 's|^    key                  =.*|    key                  = "'$key'"|' $BACKEND_FILE
    sed -i 's|^    storage_account_name =.*|    storage_account_name = "'$storage'"|' $BACKEND_FILE

}

echo "Going to Apply Scripts"

#
# Apply scripts
#
terraformInitialize
export plan="$2"

for step in `jq -c .deployments[] $1`
do
    # json file data
    deploymentId=`echo $step | jq '.deploymentId' | tr -d '"'`
    deploymentType=`echo $step | jq '.deploymentType' | tr -d '"'`
    DeploymentFile=`echo $step | jq '.DeploymentFile' | tr -d '"'`
    deploy=`echo $step | jq '.deploy' | tr -d '"'`
    # check value of deploy variable (set true as default)
    if [ "$deploy" != "true" ] && [ "$deploy" != "false" ]; then deploy="true"; fi

    if $deploy; then
        # build process...
        cd ../${DeploymentFile}

        # start build script
        if [ "$plan" == "plan" ]; then
            terraformProcessing plan
        else
            terraformProcessing
        fi

        cd $SCRIPT_DIR
    else
        echo "skipping the deployment"
    fi
done
