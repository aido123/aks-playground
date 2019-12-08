#!/bin/bash

# Usage
#./connect.sh -s "Subscription Name" -r "Resource Group Name" -c "Cluster Name" -t "tenantid" -u "username@tenantname.onmicrosoft.com" -p "password" -n "Namespace"

while getopts ":s:r:c:t:u:p:n:" opt; do
  case $opt in
    s) subscription="$OPTARG"
    ;;
    r) resourceGroup="$OPTARG"
    ;;
    c) clusterName="$OPTARG"
    ;;
    t) tenantId="$OPTARG"
    ;;
    u) username="$OPTARG"
    ;;
    p) password="$OPTARG"
    ;;
    n) namespace="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

xsplatId="04b07795-8ddb-461a-bbee-02f9e1bf7b46"

bearerToken=$(curl -s -X POST -d "grant_type=password&scope=user.read%20openid%20profile%20offline_access&client_id=$xsplatId&username=$username&password=$password&resource=https%3A%2F%2Fmanagement.azure.com%2F" "https://login.microsoftonline.com/$tenantId/oauth2/token" | tr -d '\n'  | jq -r '.access_token')

subscriptions=$(curl -s -X GET -H "Authorization: Bearer $bearerToken" https://management.azure.com/subscriptions?api-version=2019-06-01)

subscriptionId=$(echo "$subscriptions" | jq -r --arg subscription "$subscription" '.value[] | select(.displayName==$subscription)' | jq '.subscriptionId' | sed 's/"//g')

curl -s -X POST -H "Content-Length: 0" -H "Authorization: Bearer $bearerToken" "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ContainerService/managedClusters/$clusterName/listClusterUserCredential?api-version=2019-08-01" | jq -r '.kubeconfigs[0].value' | base64 --decode > "$HOME/.kube/config"

clusterUser=$(kubectl config view --output 'jsonpath={.users[0].name}')
clientId=$(kubectl config view --output 'jsonpath={.users[0].user.auth-provider.config.client-id}')
serverId=$(kubectl config view --output 'jsonpath={.users[0].user.auth-provider.config.apiserver-id}')

token=$(curl -s -X POST -d "grant_type=password&scope=user.read%20openid%20profile%20offline_access&client_id=$clientId&username=$username&password=$password&resource=$serverId%2F" "https://login.microsoftonline.com/$tenantId/oauth2/token")

accessToken=$(echo "$token" | tr -d '\n'  | jq -r '.access_token')
refreshToken=$(echo "$token" | tr -d '\n'  | jq -r '.refresh_token')
expiresIn=$(echo "$token" | tr -d '\n'  | jq -r '.expires_in')
expiresOnInt=$(echo "$token" | tr -d '\n'  | jq -r '.expires_on')
expiresOn=$(date --date @"$expiresOnInt" +"%Y-%m-%d %H:%M:%S")

kubectl config set-credentials "$clusterUser"  --auth-provider-arg=expires-on="$expiresOn" --auth-provider-arg=expires-in="$expiresIn"  --auth-provider-arg=access-token="$accessToken" --auth-provider-arg=refresh-token="$refreshToken"
kubectl config set-context --current --namespace="$namespace"