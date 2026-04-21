#!/usr/bin/env bash
# =============================================================================
# Site-to-Site VPN Demo - Azure CLI
# =============================================================================
# Mirrors the MEA Tech Community Day PowerShell workshop topology using az CLI.
#
# Topology
# --------
#   onprem-vnet  (192.168.0.0/22 + 192.168.4.0/22)
#     onprem-hub    192.168.1.0/24   ← onprem-vm1
#     Subnet-4      192.168.4.0/24   ← onprem-vm2
#     GatewaySubnet 192.168.0.0/27
#                        |
#                   S2S IPsec VPN
#                        |
#   azure-vnet   (10.70.0.0/22)
#     azure-hub         10.70.1.0/24  ← azure-vm1
#     GatewaySubnet     10.70.0.0/27
#     AzureFirewallSubnet 10.70.3.0/26 ← Azure Firewall
#
# Prerequisites
# -------------
#   az login  (or az login --use-device-code)
#   Contributor access on the target subscription
# =============================================================================

set -euo pipefail

# ── Variables ─────────────────────────────────────────────────────────────────
LOCATION="southafricanorth"
RESOURCE_GROUP="POC-MEA-Comm-Day"

ONPREM_VNET="onprem-vnet"
AZURE_VNET="azure-vnet"

ONPREM_VNET_PREFIX="192.168.0.0/22"
ONPREM_VNET_PREFIX2="192.168.4.0/22"
ONPREM_SUBNET_PREFIX="192.168.1.0/24"
ONPREM_SUBNET4_PREFIX="192.168.4.0/24"
ONPREM_GW_SUBNET_PREFIX="192.168.0.0/27"

AZURE_VNET_PREFIX="10.70.0.0/22"
AZURE_SUBNET_PREFIX="10.70.1.0/24"
AZURE_GW_SUBNET_PREFIX="10.70.0.0/27"
AZURE_FW_SUBNET_PREFIX="10.70.3.0/26"

ONPREM_VM="onprem-vm1"
ONPREM_VM2="onprem-vm2"
AZURE_VM="azure-vm1"

VM_SIZE="Standard_B2s"
VM_IMAGE="Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
USERNAME="adminazure"
PASSWORD="P@ssw0rd123!"

SHARED_KEY="AzureSharedKey123"

FIREWALL_NAME="AzFW"
FIREWALL_PIP="AzFW-Pub-IP"
FIREWALL_POLICY="AzFW-Policy-01"

BOOT_DIAG_SA="bootdiag$RANDOM"

START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo "========================================================"
echo " Deployment Started: $START_TIME"
echo "========================================================"

# ── Resource Group ────────────────────────────────────────────────────────────
echo ""
echo ">>> Creating Resource Group: $RESOURCE_GROUP ..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output table

# ── Boot Diagnostics Storage Account ─────────────────────────────────────────
echo ""
echo ">>> Creating Boot Diagnostics Storage Account: $BOOT_DIAG_SA ..."
az storage account create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BOOT_DIAG_SA" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output table

# ── Virtual Networks & Subnets ────────────────────────────────────────────────
echo ""
echo ">>> Creating onprem-vnet ..."
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ONPREM_VNET" \
  --location "$LOCATION" \
  --address-prefixes "$ONPREM_VNET_PREFIX" "$ONPREM_VNET_PREFIX2" \
  --subnet-name "onprem-hub" \
  --subnet-prefixes "$ONPREM_SUBNET_PREFIX" \
  --output table

az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$ONPREM_VNET" \
  --name "GatewaySubnet" \
  --address-prefix "$ONPREM_GW_SUBNET_PREFIX" \
  --output table

az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$ONPREM_VNET" \
  --name "Subnet-4" \
  --address-prefix "$ONPREM_SUBNET4_PREFIX" \
  --output table

echo ""
echo ">>> Creating azure-vnet ..."
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AZURE_VNET" \
  --location "$LOCATION" \
  --address-prefixes "$AZURE_VNET_PREFIX" \
  --subnet-name "azure-hub" \
  --subnet-prefixes "$AZURE_SUBNET_PREFIX" \
  --output table

az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET" \
  --name "GatewaySubnet" \
  --address-prefix "$AZURE_GW_SUBNET_PREFIX" \
  --output table

az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET" \
  --name "AzureFirewallSubnet" \
  --address-prefix "$AZURE_FW_SUBNET_PREFIX" \
  --output table

echo "✓ Virtual Networks and Subnets created"

# ── Public IPs ────────────────────────────────────────────────────────────────
echo ""
echo ">>> Creating Public IPs ..."
az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "onprem-gateway-pip" \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static \
  --output table

az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-gateway-pip" \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static \
  --output table

az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FIREWALL_PIP" \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static \
  --output table

echo "✓ Public IPs created"

# ── Azure Firewall Policy ─────────────────────────────────────────────────────
echo ""
echo ">>> Creating Azure Firewall Policy: $FIREWALL_POLICY ..."
az network firewall policy create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FIREWALL_POLICY" \
  --location "$LOCATION" \
  --sku Standard \
  --threat-intel-mode Alert \
  --output table

echo "✓ Azure Firewall Policy created"

# ── Azure Firewall ────────────────────────────────────────────────────────────
echo ""
echo ">>> Creating Azure Firewall: $FIREWALL_NAME (this may take a few minutes) ..."
az network firewall create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FIREWALL_NAME" \
  --location "$LOCATION" \
  --sku AZFW_VNet \
  --tier Standard \
  --firewall-policy "$FIREWALL_POLICY" \
  --output table

az network firewall ip-config create \
  --resource-group "$RESOURCE_GROUP" \
  --firewall-name "$FIREWALL_NAME" \
  --name "AzFW-ipconfig" \
  --public-ip-address "$FIREWALL_PIP" \
  --vnet-name "$AZURE_VNET" \
  --output table

# Retrieve Firewall private IP for routing
FIREWALL_PRIVATE_IP=$(az network firewall show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FIREWALL_NAME" \
  --query "ipConfigurations[0].privateIPAddress" \
  --output tsv)

FIREWALL_PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$FIREWALL_PIP" \
  --query "ipAddress" \
  --output tsv)

echo "✓ Azure Firewall created"
echo "  Private IP : $FIREWALL_PRIVATE_IP"
echo "  Public IP  : $FIREWALL_PUBLIC_IP"

# ── Azure Firewall Network Rules ──────────────────────────────────────────────
echo ""
echo ">>> Configuring Azure Firewall Network Rules ..."

# Create the rule-collection group
az network firewall policy rule-collection-group create \
  --resource-group "$RESOURCE_GROUP" \
  --policy-name "$FIREWALL_POLICY" \
  --name "DefaultNetworkRuleCollectionGroup" \
  --priority 200 \
  --output table

# Add the filter collection with the first network rule
az network firewall policy rule-collection-group collection add-filter-collection \
  --resource-group "$RESOURCE_GROUP" \
  --policy-name "$FIREWALL_POLICY" \
  --rule-collection-group-name "DefaultNetworkRuleCollectionGroup" \
  --name "NetworkRuleCollection" \
  --action Allow \
  --priority 100 \
  --rule-type NetworkRule \
  --rule-name "Allow-Onprem-Hub-to-Azure" \
  --protocols TCP UDP ICMP \
  --source-addresses "192.168.1.0/24" \
  --destination-addresses "10.70.1.0/24" \
  --destination-ports "*" \
  --output table

# Add additional rules to the same collection
az network firewall policy rule-collection-group collection rule add \
  --resource-group "$RESOURCE_GROUP" \
  --policy-name "$FIREWALL_POLICY" \
  --rule-collection-group-name "DefaultNetworkRuleCollectionGroup" \
  --collection-name "NetworkRuleCollection" \
  --rule-type NetworkRule \
  --name "Allow-Onprem-Subnet4-to-Azure" \
  --protocols TCP UDP ICMP \
  --source-addresses "192.168.4.0/24" \
  --destination-addresses "10.70.1.0/24" \
  --destination-ports "*" \
  --output table

az network firewall policy rule-collection-group collection rule add \
  --resource-group "$RESOURCE_GROUP" \
  --policy-name "$FIREWALL_POLICY" \
  --rule-collection-group-name "DefaultNetworkRuleCollectionGroup" \
  --collection-name "NetworkRuleCollection" \
  --rule-type NetworkRule \
  --name "Allow-Azure-to-Onprem" \
  --protocols TCP UDP ICMP \
  --source-addresses "10.70.1.0/24" \
  --destination-addresses "192.168.1.0/24" "192.168.4.0/24" \
  --destination-ports "*" \
  --output table

echo "✓ Azure Firewall Network Rules configured"
echo "  • 192.168.1.0/24 → 10.70.1.0/24 (TCP/UDP/ICMP)"
echo "  • 192.168.4.0/24 → 10.70.1.0/24 (TCP/UDP/ICMP)"
echo "  • 10.70.1.0/24  → 192.168.0.0/22 (TCP/UDP/ICMP)"

# ── Route Tables (UDRs) ───────────────────────────────────────────────────────
echo ""
echo ">>> Creating Route Tables ..."

# Route table for azure-hub subnet (traffic to on-prem → firewall)
az network route-table create \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-subnet-rt" \
  --location "$LOCATION" \
  --disable-bgp-route-propagation true \
  --output table

az network route-table route create \
  --resource-group "$RESOURCE_GROUP" \
  --route-table-name "azure-subnet-rt" \
  --name "route-to-onprem-192-168-1-0" \
  --address-prefix "192.168.1.0/24" \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$FIREWALL_PRIVATE_IP" \
  --output table

az network route-table route create \
  --resource-group "$RESOURCE_GROUP" \
  --route-table-name "azure-subnet-rt" \
  --name "route-to-onprem-192-168-4-0" \
  --address-prefix "192.168.4.0/24" \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$FIREWALL_PRIVATE_IP" \
  --output table

# Associate azure-subnet-rt with azure-hub subnet
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET" \
  --name "azure-hub" \
  --route-table "azure-subnet-rt" \
  --output table

echo "✓ azure-hub route table associated (BGP propagation disabled)"

# Route table for GatewaySubnet (return traffic to azure-hub → firewall)
az network route-table create \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-gateway-subnet-rt" \
  --location "$LOCATION" \
  --disable-bgp-route-propagation true \
  --output table

az network route-table route create \
  --resource-group "$RESOURCE_GROUP" \
  --route-table-name "azure-gateway-subnet-rt" \
  --name "route-to-hub-subnet" \
  --address-prefix "10.70.1.0/24" \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address "$FIREWALL_PRIVATE_IP" \
  --output table

# Associate azure-gateway-subnet-rt with GatewaySubnet
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET" \
  --name "GatewaySubnet" \
  --route-table "azure-gateway-subnet-rt" \
  --output table

echo "✓ GatewaySubnet route table associated (BGP propagation disabled)"

# ── Virtual Machines ──────────────────────────────────────────────────────────
echo ""
echo ">>> Creating Virtual Machines in parallel ..."

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ONPREM_VM" \
  --location "$LOCATION" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --vnet-name "$ONPREM_VNET" \
  --subnet "onprem-hub" \
  --admin-username "$USERNAME" \
  --admin-password "$PASSWORD" \
  --authentication-type password \
  --boot-diagnostics-storage "$BOOT_DIAG_SA" \
  --public-ip-address "" \
  --no-wait \
  --output none

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AZURE_VM" \
  --location "$LOCATION" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --vnet-name "$AZURE_VNET" \
  --subnet "azure-hub" \
  --admin-username "$USERNAME" \
  --admin-password "$PASSWORD" \
  --authentication-type password \
  --boot-diagnostics-storage "$BOOT_DIAG_SA" \
  --public-ip-address "" \
  --no-wait \
  --output none

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ONPREM_VM2" \
  --location "$LOCATION" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --vnet-name "$ONPREM_VNET" \
  --subnet "Subnet-4" \
  --admin-username "$USERNAME" \
  --admin-password "$PASSWORD" \
  --authentication-type password \
  --boot-diagnostics-storage "$BOOT_DIAG_SA" \
  --public-ip-address "" \
  --no-wait \
  --output none

echo "  VM deployments initiated in parallel. Waiting ..."
az vm wait --resource-group "$RESOURCE_GROUP" --name "$ONPREM_VM"  --created --output none
az vm wait --resource-group "$RESOURCE_GROUP" --name "$AZURE_VM"   --created --output none
az vm wait --resource-group "$RESOURCE_GROUP" --name "$ONPREM_VM2" --created --output none

echo "✓ Virtual Machines created with Boot Diagnostics enabled"

# ── VPN Gateways (parallel) ───────────────────────────────────────────────────
echo ""
echo ">>> Starting VPN Gateway deployments in parallel (30-45 minutes) ..."
GW_START=$(date -u +"%H:%M:%S UTC")

az network vnet-gateway create \
  --resource-group "$RESOURCE_GROUP" \
  --name "onprem-gateway" \
  --location "$LOCATION" \
  --public-ip-address "onprem-gateway-pip" \
  --vnet "$ONPREM_VNET" \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --no-wait \
  --output none

az network vnet-gateway create \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-gateway" \
  --location "$LOCATION" \
  --public-ip-address "azure-gateway-pip" \
  --vnet "$AZURE_VNET" \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --no-wait \
  --output none

echo "  Both gateways deploying. Waiting for onprem-gateway ..."
az network vnet-gateway wait \
  --resource-group "$RESOURCE_GROUP" \
  --name "onprem-gateway" \
  --created \
  --output none

echo "  onprem-gateway ready. Waiting for azure-gateway ..."
az network vnet-gateway wait \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-gateway" \
  --created \
  --output none

GW_END=$(date -u +"%H:%M:%S UTC")
echo "✓ Both VPN Gateways deployed  (started: $GW_START, completed: $GW_END)"

# ── VPN Connections ───────────────────────────────────────────────────────────
echo ""
echo ">>> Configuring VPN Connections ..."

ONPREM_PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "onprem-gateway-pip" \
  --query "ipAddress" \
  --output tsv)

AZURE_PUBLIC_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-gateway-pip" \
  --query "ipAddress" \
  --output tsv)

echo "  On-prem gateway IP : $ONPREM_PUBLIC_IP"
echo "  Azure gateway IP   : $AZURE_PUBLIC_IP"

# Local Network Gateways (represent the remote side of each VPN connection)
az network local-gateway create \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-local-gateway" \
  --location "$LOCATION" \
  --gateway-ip-address "$AZURE_PUBLIC_IP" \
  --local-address-prefixes "$AZURE_VNET_PREFIX" \
  --output table

az network local-gateway create \
  --resource-group "$RESOURCE_GROUP" \
  --name "onprem-local-gateway" \
  --location "$LOCATION" \
  --gateway-ip-address "$ONPREM_PUBLIC_IP" \
  --local-address-prefixes "$ONPREM_VNET_PREFIX" "$ONPREM_VNET_PREFIX2" \
  --output table

# VPN Connections
az network vpn-connection create \
  --resource-group "$RESOURCE_GROUP" \
  --name "onprem-to-azure" \
  --location "$LOCATION" \
  --vnet-gateway1 "onprem-gateway" \
  --local-gateway2 "azure-local-gateway" \
  --shared-key "$SHARED_KEY" \
  --output table

az network vpn-connection create \
  --resource-group "$RESOURCE_GROUP" \
  --name "azure-to-onprem" \
  --location "$LOCATION" \
  --vnet-gateway1 "azure-gateway" \
  --local-gateway2 "onprem-local-gateway" \
  --shared-key "$SHARED_KEY" \
  --output table

echo "✓ VPN connections established"

# ── Deployment Summary ────────────────────────────────────────────────────────
END_TIME=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

echo ""
echo "========================================================"
echo " DEPLOYMENT SUMMARY"
echo "========================================================"
echo ""
echo " Resource Group : $RESOURCE_GROUP"
echo " Location       : $LOCATION"
echo ""
echo " Networks"
echo "   onprem-vnet  : $ONPREM_VNET_PREFIX, $ONPREM_VNET_PREFIX2"
echo "     onprem-hub : $ONPREM_SUBNET_PREFIX"
echo "     Subnet-4   : $ONPREM_SUBNET4_PREFIX"
echo "     GatewaySubnet: $ONPREM_GW_SUBNET_PREFIX"
echo "   azure-vnet   : $AZURE_VNET_PREFIX"
echo "     azure-hub  : $AZURE_SUBNET_PREFIX"
echo "     GatewaySubnet: $AZURE_GW_SUBNET_PREFIX"
echo "     AzureFirewallSubnet: $AZURE_FW_SUBNET_PREFIX"
echo ""
echo " Virtual Machines (Ubuntu 22.04 LTS, $VM_SIZE)"
echo "   $ONPREM_VM  → onprem-hub ($ONPREM_SUBNET_PREFIX)"
echo "   $ONPREM_VM2 → Subnet-4 ($ONPREM_SUBNET4_PREFIX)"
echo "   $AZURE_VM   → azure-hub ($AZURE_SUBNET_PREFIX)"
echo ""
echo " Azure Firewall"
echo "   Name       : $FIREWALL_NAME"
echo "   Policy     : $FIREWALL_POLICY"
echo "   Private IP : $FIREWALL_PRIVATE_IP"
echo "   Public IP  : $FIREWALL_PUBLIC_IP"
echo "   Rules      : 192.168.1.0/24 → 10.70.1.0/24"
echo "                192.168.4.0/24 → 10.70.1.0/24"
echo "                10.70.1.0/24  → on-prem"
echo ""
echo " VPN Gateways (VpnGw1, RouteBased)"
echo "   onprem-gateway : $ONPREM_PUBLIC_IP"
echo "   azure-gateway  : $AZURE_PUBLIC_IP"
echo ""
echo " VPN Connections (IPsec)"
echo "   onprem-to-azure  (onprem-gateway ↔ azure-local-gateway)"
echo "   azure-to-onprem  (azure-gateway  ↔ onprem-local-gateway)"
echo ""
echo " Route Tables (BGP propagation disabled)"
echo "   azure-subnet-rt         → azure-hub"
echo "   azure-gateway-subnet-rt → GatewaySubnet"
echo "   Next-hop: $FIREWALL_PRIVATE_IP (Azure Firewall)"
echo ""
echo " Boot Diagnostics SA: $BOOT_DIAG_SA"
echo "========================================================"
echo " Started : $START_TIME"
echo " Finished: $END_TIME"
echo "========================================================"
echo ""
echo " Next Steps"
echo "  1. Test ping from onprem-vm1 (192.168.1.x) to azure-vm1 (10.70.1.x)"
echo "  2. Test ping from onprem-vm2 (192.168.4.x) to azure-vm1 (10.70.1.x)"
echo "  3. Use Bastion or Serial Console to access VMs (no public IPs)"
echo "  4. Monitor Azure Firewall logs in Azure Portal"
echo "  5. Capture VPN packet traces with the packet-capture script"
echo "========================================================"
