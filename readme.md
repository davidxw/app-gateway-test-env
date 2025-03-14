# App Gateway Test Environment

This repo sets up a test environment for Azure Application Gateway. It creates the following resources:
* Azure Virtual Network with subnets for the Application Gateway and a Container App Environment
* Azure Container App Environment with two sample apps. Public ingress is enabled for the Container App Environment.
* Azure Application Gateway with a public IP address and two backend pools, one for each sample app
* A basic Application Gateway routing rule sending all traffic to the first sample app
* An Azure Log Analytics workspace for both App Gateway and Container App Environment logs

The sample app deployed is https://github.com/davidxw/webHttpTest. After the deployment is complete, you can test the sample app at the following URL:
```
http://<app-gateway-public-ip>/api/envronment
```
You can see from the response which container app the request was routed to. 

## Setup

### Azure Developer CLI

#### Set up the environment:
* If you have cloned this repo, run `azd init`
* if you have not cloned this repo, run `azd init -t davidxw/app-gateway-test-env` 

#### Deploy the environment:
* Run `azd auth login` to authenticate with Azure
* Run `azd up` and ansewr the prompts

### Bicep CLI

From the `infra` folder, run the following command to deploy the resources:
```bash
RG=<your-resource-group>
NAME=<base name for your resources>
az group create --name $RG$ --location <your-location>
az deployment group create --resource-group $RG --template-file ./resources.bicep --parameters name=$NAME
```