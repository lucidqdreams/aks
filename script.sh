## POWERSHELL
# parameters
$subscription="labs"
$location='westus2'
$rg="aksservices"
$wafpolicyname="wafpolicyGeo"

# Code
select-azsubscription $subscription
new-azresourcegroup -location $location -name $rg

# Create a geo-match allow custom rule
$var = New-AzApplicationGatewayFirewallMatchVariable -VariableName RequestUri
$condition = New-AzApplicationGatewayFirewallCondition -MatchVariable $var -Operator GeoMatch -MatchValue "US"  -NegationCondition $False
$AllowUS = New-AzApplicationGatewayFirewallCustomRule -Name allowUS -Priority 1 -RuleType MatchRule -MatchCondition $condition -Action Allow

# Create a geo-match deny custom rule
$var = New-AzApplicationGatewayFirewallMatchVariable -VariableName RequestUri
$condition = New-AzApplicationGatewayFirewallCondition -MatchVariable $var -Operator GeoMatch -MatchValue "US"  -NegationCondition $False
$Deny = New-AzApplicationGatewayFirewallCustomRule -Name allowUS -Priority 2 -RuleType MatchRule -MatchCondition $condition -Action Block


# Create a firewall policy
$wafPolicy = New-AzApplicationGatewayFirewallPolicy -Name $wafpolicyname -ResourceGroup $rg -Location $location -CustomRule $Deny, $AllowUS


#Azure Cloud Shell Bash
subscription="Labs"
rg="aksservices"
location="westus2"
solutionname="akslab"
LetsEncryptEmail='matthew.quickenden@gmail.com'
domainsuffix="$solutionname.ci.avahc.com"
domaintext1="svc1"
domaintext2="svc2"

# Alias
#AliasFILE=.bash_aliases
#if test -f "$AliasFILE"; then
#    echo "$AliasFILE exist"
#else	
#	touch $AliasFILE
#	echo "alias k=kubectl" > $AliasFILE
	alias k=kubectl
#fi


### Working Logic
cd ~
workingDir=$rg-$solutionname-k8sapgw
if test -d "$workingDir"; then
    echo "$workingDir exist"  > deployment.log
	cd $workingDir
else	
	echo "creating working directory in cloud shell" > deployment.log
	mkdir $workingDir
	cd $workingDir
fi

cat <<EOF > envParams.sh
#!/bin/bash

# base parameters
solutionname="$solutionname"
subscription="$subscription"
rg="$rg"
location="$location"
workingDir="$workingDir"

# Networking
vnetName="$solutionname-vnet"
aksSubnetName="kubernetes"
agwSubnetName="agw"

# these arent used if used for existing rg & vnet
vnetAddressSpace="10.9.0.0/16"
aksSubnetCIDR="10.9.1.0/24"
agwSubnetCIDR="10.9.2.0/24"

# AKS cluster parameters
aksClusterName="$solutionname-k8s"
aksDockerBridgeAddress='172.17.0.1/16'
aksDnsServiceIP='10.2.0.10'
aksServiceCIDR='10.2.0.0/24'

# Application Gateway parameters
agwName="$solutionname-agw"
agwPIP="$solutionname-pip"
# agwSku="Standard_v2"
agwSku="WAF_v2"

# AKS node pool 1
PrimaryNodePoolk8sVersion="1.15.7"
PrimaryNodePoolNodeSize="Standard_DS2_v2"
PrimaryNodePoolNodeCount=3
PrimaryNodePoolmaxpods=20
PrimaryNodePoolmincount=1
PrimaryNodePoolmaxcount=3

# AKS node pool 2
SecondaryNodePool="nodepool2"
SecondaryNodePoolk8sVersion="1.14.8"
SecondaryNodePoolNodeSize="Standard_DS2_v2"
SecondaryNodePoolCount=3
SecondaryNodemaxpods=10
SecondaryNodemincount=1
SecondaryNodemaxcount=3

# DNS Parameters

# certificate Manager
LetsEncryptEmail="$LetsEncryptEmail"

# Ingress Parameters 
domainsuffix="$domainsuffix"
wafPolicyGeoMatch="wafpolicyGeoMatch"

# Service 1
domaintext1="$domaintext1"
domainname1="$domaintext1.$domainsuffix"
SecretName1="$domaintext1-tls"
SecretNameStage1="$domaintext-tls-stage"

# service 2
domaintext2="$domaintext2"
domainname2="$domaintext2.$domainsuffix"
SecretName2="$domaintext2-tls"
SecretNameStage2="$domaintext2-tls-stage"

# URL path (currently not working, issue logged on MS docs https://github.com/MicrosoftDocs/azure-docs/issues/46938) 
URLPath="/app/*"

# Created Discovered / Derived / Parameters
EOF

source envParams.sh

## Set up environment
az account set --subscription $subscription
subscriptionId=$(az account show --subscription $subscription | jq -r ".id")
echo "Subscription '$subscription' with ID '$subscriptionId' has been targeted" >> deployment.log
echo "subscriptionId='$subscriptionId'" >> envParams.sh
tenantId=$(az account show | jq -r ".tenantId")
echo "tenantId='$tenantId'" >> envParams.sh

## Create Resource Group (testing)
az group create -l $location -n $rg

## Create virtual Network and AKS subnet (testing)
az network vnet create \
  --name $vnetName \
  --resource-group $rg \
  --location $location \
  --address-prefix $vnetAddressSpace \
  --subnet-name $aksSubnetName \
  --subnet-prefix $aksSubnetCIDR

# Create virtual agw subnet (testing)az 
az network vnet subnet create \
  --name $agwSubnetName \
  --resource-group $rg \
  --vnet-name $vnetName \
  --address-prefix $agwSubnetCIDR 

echo "Creating DNS zone in $rg for $domainsuffix" >> deployment.log
az network dns zone create -g $rg -n $domainsuffix
dnsid=$(az network dns zone show -g $rg -n $domainsuffix | jq -r ".id")
echo "dnsid='$dnsid'" >> envParams.sh
nameserversarray=($(az network dns zone show -g $rg -n $domainsuffix | jq -c ".nameServers"))

az network dns zone show -g $rg -n $domainsuffix | jq -c ".nameServers"

## Create Public IP Address
az network public-ip create --name $agwPIP --resource-group $rg --allocation-method Static --sku Standard
$publicipid=$(az network public-ip show --name $agwPIP --resource-group $rg | jq -r ".id" )
echo "found resource group '$publicipid'" >> deployment.log
echo "publicipid='$publicipid'" >> envParams.sh

## Get resource group & subnet resource IDs
rgid=$(az group show --name $rg | jq -r ".id" )
echo "found resource group '$rgid'" >> deployment.log
echo "rgid='$rgid'" >> envParams.sh

aksSubnetId=$(az network vnet subnet show -g $rg -n $aksSubnetName  --vnet-name $vnetName | jq -r '.id')
echo "found subnet '$aksSubnetId'" >> deployment.log
echo "aksSubnetId='$aksSubnetId'" >> envParams.sh

agwSubnetId=$(az network vnet subnet show -g $rg -n $agwSubnetName  --vnet-name $vnetName | jq -r '.id')
echo "found subnet '$agwSubnetId'" >> deployment.log
echo "agwSubnetId='$agwSubnetId'" >> envParams.sh

## Application Gateway
echo "Creating app-gateway with '$location, $agwName, $rg, $agwSku, $agwSubnetName, $vnetName, $agwPIP'" >> deployment.log

wafpolicygeomatch=$(az network application-gateway waf-policy show --resource-group $rg --name $wafPolicyGeoMatch | jq -r ".id")
echo "waf policy $wafpolicygeomatch" >> depployment.log

az network application-gateway create \
   --capacity 2 \
   --frontend-port 80 \
   --http-settings-cookie-based-affinity Disabled \
   --http-settings-port 80 \
   --http-settings-protocol Http \
   --location $location \
   --name $agwName \
   --resource-group $rg \
   --sku $agwSku \
   --subnet $agwSubnetName \
   --vnet-name $vnetName \
   --public-ip-address $agwPIP \
   --routing-rule-type basic \
   --waf-policy $wafpolicygeomatch \
   --no-wait

## AKS Cluster
echo "Creating AKS with '$rg, aksClusterName, $$aksSubnetId, $aksDockerBridgeAddress, $aksDnsServiceIP, $PrimaryNodePoolk8sVersion, $PrimaryNodePoolNodeSize, $PrimaryNodePoolNodeCount, $location" >> deployment.log

az aks create \
    --resource-group $rg \
    --name $aksClusterName \
    --network-plugin azure \
    --vnet-subnet-id $aksSubnetId \
    --docker-bridge-address $aksDockerBridgeAddress \
    --dns-service-ip $aksDnsServiceIP \
    --service-cidr $aksServiceCIDR \
    --generate-ssh-keys \
    --kubernetes-version $PrimaryNodePoolk8sVersion \
    --node-vm-size $PrimaryNodePoolNodeSize \
    --node-count $PrimaryNodePoolNodeCount \
    --enable-addons monitoring \
    --location $location 
    
#	--max-count $PrimaryNodePoolmaxcount \
#    --max-pods $PrimaryNodePoolmaxpods \
#    --min-count $PrimaryNodePoolmincount \
#    --enable-cluster-autoscaler
	
## Add Second NodePool  
## There are just not enough IPs in  a /25
#az aks nodepool add \
#	--cluster-name $aksClusterName \
#	--name $SecondaryNodePool \
#	--resource-group $rg \
#	--node-count $SecondaryNodePoolCount \
#	--kubernetes-version $SecondaryNodePoolk8sVersion \
#	--vnet-subnet-id $aksSubnetId

## Connect to AKS cluster
az aks get-credentials --resource-group $rg --name $aksClusterName --overwrite-existing --subscription $subscription >> deployment.log
#echo "\nalias ks-$aksClusterName='kubectl config use-context $aksClusterName'" >> $AliasFILE
#alias ks-$aksClusterName='kubectl config use-context $aksClusterName'

## kubesystem dashboard rbac acccess for dashboard
kubectl create clusterrolebinding kubernetes-dashboard --clusterrole=cluster-admin --serviceaccount=kube-system:kubernetes-dashboard
echo "creating kubernetes-dashboard" >> deployment.log
#az aks browse --resource-group $rg --name $aksClusterName

## Create Managed Identity 
aksidentity=$aksClusterName'identity'
echo "aksidentity='$aksidentity'" >> envParams.sh
agentpoolresourcegroup='MC_'$rg'_'$aksClusterName'_'$location
az identity create -g $agentpoolresourcegroup -n $aksidentity > k8sidentity.json
az identity show -g $agentpoolresourcegroup -n $aksidentity >> deployment.log

## Extract Parameters from managed Identity
clientid=$(jq -r ".clientId" k8sidentity.json)
echo "clientid='$clientid'" >> envParams.sh
identityresourceid=$(jq -r ".id" k8sidentity.json)
echo "identityresourceid='$identityresourceid'" >> envParams.sh
principalId=$(jq -r ".principalId" k8sidentity.json)
echo "principalId='$principalId'" >> envParams.sh
AppGatewayID=$( az network application-gateway show  --resource-group $rg --name $agwName | jq -r ".id")
echo "AppGatewayID='$AppGatewayID'" >> envParams.sh
aksspnid=$(az aks show -g $rg -n $aksClusterName --query servicePrincipalProfile.clientId -o tsv)
echo "aksspnid='$aksspnid'" >> envParams.sh
echo "$clientid, $identityresourceid, $principalId, $AppGatewayID, $aksspnid" >> deployment.log


# DNS SPN
az ad sp create-for-rbac -n $aksClusterName > dnsspn.json

dnsspnappId=$(jq -r ".appId" dnsspn.json)
echo "dnsspnappId='$dnsspnappId'" >> envParams.sh
dnsspndisplayName=$(jq -r ".displayName" dnsspn.json)
echo "dnsspndisplayName='$dnsspndisplayName'" >> envParams.sh
dnsspnname=$(jq -r ".name" dnsspn.json)
echo "dnsspnname='$dnsspnname'" >> envParams.sh
dnsspnpassword=$(jq -r ".password" dnsspn.json)
echo "dnsspnpassword='$dnsspnpassword'" >> envParams.sh
dnsspntenant=$(jq -r ".tenant" dnsspn.json)
echo "dnsspntenant='$dnsspntenant'" >> envParams.sh

# Create DNS K8s Secret File for DNS
cat <<EOF > azure.json
{
  "tenantId": "$tenantId",
  "subscriptionId": "$subscriptionId",
  "resourceGroup": "$rg",
  "aadClientId": "$dnsspnappId",
  "aadClientSecret": "$dnsspnpassword"
}
EOF
kubectl create secret generic azure-dns-config --from-file=azure.json

# DNS roles | assign the rights to the created service principal, using the resource ids from previous step
# 1. as a reader to the resource group
az role assignment create \
	--role "Reader" \
	--assignee $dnsspnappId \
	--scope $rgid

# 2. as a contributor to DNS Zone itself
az role assignment create \
	--role "Contributor" \
	--assignee $dnsspnappId \
	--scope $dnsid  

## AAD pod identity
wget https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml -O deployment-rbac.yaml
kubectl apply -f deployment-rbac.yaml
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

cat <<EOF > azure-dns-config.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions"] 
  resources: ["ingresses"] 
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.opensource.zalan.do/teapot/external-dns:latest
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=$domainsuffix # (optional) limit to only example.com domains; change to match the zone created above.
        - --provider=azure
        - --azure-resource-group=$rg # (optional) use the DNS zones from the tutorial's resource group
        volumeMounts:
        - name: azure-dns-config
          mountPath: /etc/kubernetes
          readOnly: true
      volumes:
      - name: azure-dns-config
        secret:
          secretName: azure-dns-config
EOF

kubectl apply -f azure-dns-config.yaml

## Managed Identity Role assignment (Application Gateway Contributor)
echo "Managed Identity Role assignment (Application Gateway Contributor) '$clientid, $AppGatewayID'" >> deployment.log
az role assignment create \
    --role Contributor \
    --assignee $clientid \
    --scope $AppGatewayID

## Managed Identity Role assignment (Resource Group Reader)
echo "Managed Identity Role assignment (Resource Group Reader) '$clientid, $rgid'" >> deployment.log
az role assignment create \
    --role Reader \
    --assignee $clientid  \
    --scope $rgid

## create and update aadpodidentity YAML
echo 'create and update aadpodidentity YAML'

cat <<EOF > aadpodidentity.yaml
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: <aksidentity>
spec:
  type: 0
  ResourceID: <identityresourceid>
  ClientID: <clientid>
EOF
sed -i "s|<clientid>|${clientid}|g" aadpodidentity.yaml
sed -i "s|<identityresourceid>|${identityresourceid}|g" aadpodidentity.yaml
sed -i "s|<aksidentity>|${aksidentity}|g" aadpodidentity.yaml
cat aadpodidentity.yaml >> deployment.log

kubectl apply -f aadpodidentity.yaml

## create and update azure identity binding YAML
selector="select_it"
azureidentitybinding="azure-identity-binding"

cat <<EOF > aadpodidentitybinding.yaml
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: <azureidentitybinding>
spec:
  AzureIdentity: <aksidentity>
  Selector: <selector>
EOF
sed -i "s|<azureidentitybinding>|${azureidentitybinding}|g" aadpodidentitybinding.yaml
sed -i "s|<aksidentity>|${aksidentity}|g" aadpodidentitybinding.yaml
sed -i "s|<selector>|${selector}|g" aadpodidentitybinding.yaml
cat aadpodidentitybinding.yaml

kubectl apply -f aadpodidentitybinding.yaml

## Add Helm app gateway ingress package and create helm file
## reference https://github.com/Azure/application-gateway-kubernetes-ingress/

wget https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/sample-helm-config.yaml -O helm-config.yaml

sed -i "s|<subscriptionId>|${subscriptionId}|g" helm-config.yaml
sed -i "s|<resourceGroupName>|${rg}|g" helm-config.yaml
sed -i "s|<applicationGatewayName>|${agwName}|g" helm-config.yaml
sed -i "s|<identityResourceId>|${identityresourceid}|g" helm-config.yaml
sed -i "s|<identityClientId>|${clientid}|g" helm-config.yaml
sed -i "s|enabled: false|enabled: true|g" helm-config.yaml
cat helm-config.yaml

helm install -f helm-config.yaml application-gateway-kubernetes-ingress/ingress-azure --generate-name

## Cert manager v0.13.0
# add custome resource definitions 
wget https://raw.githubusercontent.com/jetstack/cert-manager/v0.13.0/deploy/manifests/00-crds.yaml -O 00-crds.yaml
kubectl apply --validate=false -f 00-crds.yaml
# install cert manager
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager \
  --namespace cert-manager \
  --version v0.13.0 \
  jetstack/cert-manager


###### letsencrypt-staging 
cat <<EOF > letsencrypt-staging.yaml
---
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: <registeredemail>
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: letsencrypt-staging
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          class: azure/application-gateway
EOF
sed -i "s|<registeredemail>|${LetsEncryptEmail}|g" letsencrypt-staging.yaml
cat letsencrypt-staging.yaml

kubectl apply -f letsencrypt-staging.yaml

###### letsencrypt-production 
cat <<EOF > letsencrypt-production.yaml
---
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email: <registeredemail>
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: letsencrypt-prod
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          class: azure/application-gateway
EOF
sed -i "s|<registeredemail>|${LetsEncryptEmail}|g" letsencrypt-production.yaml

kubectl apply -f letsencrypt-production.yaml

## enale Live Data for AKS cluster
cat <<EOF > Live-Data-AKS-cluster.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
    name: containerHealth-log-reader
rules:
    - apiGroups: ["", "metrics.k8s.io", "extensions", "apps"]
      resources:
         - "pods/log"
         - "events"
         - "nodes"
         - "pods"
         - "deployments"
         - "replicasets"
      verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
    name: containerHealth-read-logs-global
roleRef:
    kind: ClusterRole
    name: containerHealth-log-reader
    apiGroup: rbac.authorization.k8s.io
subjects:
- kind: User
  name: clusterUser
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f Live-Data-AKS-cluster.yaml

#########################################################################################
############################## Environment Configured Here. #############################
############################ Sample Applications and Ingress  ###########################
#########################################################################################

## Guestbook (Sample Application)
wget https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/all-in-one/guestbook-all-in-one.yaml -O guestbook-all-in-one.yaml 
kubectl apply -f guestbook-all-in-one.yaml

## ASP net (Sample Application)
cat <<EOF > aspnet-app.yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: aspnetapp
  labels:
    app: aspnetapp
spec:
  containers:
  - image: "mcr.microsoft.com/dotnet/core/samples:aspnetapp"
    name: aspnetapp-image
    ports:
    - containerPort: 80
      protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: aspnetapp
spec:
  selector:
    app: aspnetapp
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF

kubectl apply -f aspnet-app.yaml


## Ingress  templates
## Guestbook Application App gateway Ingress (staging)
cat <<EOF > letsencrypt-guestbook-ing-stage.yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: guestbook-letsencrypt-stage
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/waf-policy-for-path: <wafpolicy>
spec:
  tls:
    - hosts:
      - <domainname>
      secretName: <SecretNameStage>
  rules:
  - host: <domainname>
    http:
      paths:
      - backend:
          serviceName: frontend
          servicePort: 80
EOF
sed -i "s|<domainname>|${domainname1}|g" letsencrypt-guestbook-ing-stage.yaml
sed -i "s|<SecretNameStage>|${SecretNameStage1}|g" letsencrypt-guestbook-ing-stage.yaml
sed -i "s|<wafpolicy>|${wafpolicygeomatch}|g" letsencrypt-guestbook-ing-stage.yaml
cat letsencrypt-guestbook-ing-stage.yaml
# kubectl apply -f letsencrypt-guestbook-ing-stage.yaml

## Guestbook Application App gateway Ingress (Production)
cat <<EOF > letsencrypt-guestbook-ing-prod.yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: guestbook-letsencrypt
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/waf-policy-for-path: <wafpolicy>
spec:
  tls:
    - hosts:
      - <domainname>
      secretName: <SecretName>
  rules:
  - host: <domainname>
    http:
      paths:
      - backend:
          serviceName: frontend
          servicePort: 80
EOF
sed -i "s|<domainname>|${domainname1}|g" letsencrypt-guestbook-ing-prod.yaml
sed -i "s|<SecretName>|${SecretName1}|g" letsencrypt-guestbook-ing-prod.yaml
sed -i "s|<wafpolicy>|${wafpolicygeomatch}|g" letsencrypt-guestbook-ing-prod.yaml
cat letsencrypt-guestbook-ing-prod.yaml

kubectl apply -f letsencrypt-guestbook-ing-prod.yaml

## ASPNetApp Application App gateway Ingress (Production)
cat <<EOF > letsencrypt-aspnetapp-ing-prod.yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: aspnetapp-letsencrypt
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/waf-policy-for-path: <wafpolicy>
spec:
  tls:
    - hosts:
      - <domainname>
      secretName: <SecretName>
  rules:
  - host: <domainname>
    http:
      paths:
      - backend:
          serviceName: aspnetapp
          servicePort: 80
EOF
sed -i "s|<domainname>|${domainname2}|g" letsencrypt-aspnetapp-ing-prod.yaml
sed -i "s|<SecretName>|${SecretName2}|g" letsencrypt-aspnetapp-ing-prod.yaml
sed -i "s|<wafpolicy>|${wafpolicygeomatch}|g" letsencrypt-aspnetapp-ing-prod.yaml
cat letsencrypt-aspnetapp-ing-prod.yaml

kubectl apply -f letsencrypt-aspnetapp-ing-prod.yaml


# URL Path not working https://github.com/MicrosoftDocs/azure-docs/issues/46938
## URL path / Guestbook Application / ASP Net App gateway Ingress (Production) 
cat <<EOF > letsencrypt-guestbook-ing-prod-paths.yaml
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: guestbook-letsencrypt
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/waf-policy-for-path: <wafpolicy>
spec:
  tls:
    - hosts:
      - <domainname>
      secretName: <SecretName>
  rules:
  - host: <domainname>
    http:
      paths:
      - path: <URLPath>
        backend:
          serviceName: aspnetapp
          servicePort: 80
      - backend:
          serviceName: frontend
          servicePort: 80
EOF
sed -i "s|<URLPath>|${URLPath}|g" letsencrypt-guestbook-ing-prod-paths.yaml
sed -i "s|<domainname>|${domainname}|g" letsencrypt-guestbook-ing-prod-paths.yaml
sed -i "s|<SecretName>|${SecretName}|g" letsencrypt-guestbook-ing-prod-paths.yaml
sed -i "s|<wafpolicy>|${wafpolicygeomatch}|g" letsencrypt-guestbook-ing-prod-paths.yaml
# cat letsencrypt-guestbook-ing-prod-paths
# kubectl apply -f letsencrypt-guestbook-ing-prod-paths.yaml

		  
		  
# Add Azure CLI  firewall extension
#az extension add -n azure-firewall




