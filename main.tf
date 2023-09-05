# Generate random resource group name
resource "random_pet" "rg_name" {
  prefix = var.resource_group_name_prefix
}

resource "azurerm_resource_group" "rg" {
  location = var.resource_group_location
  name     = random_pet.rg_name.id
}

resource "random_pet" "azurerm_kubernetes_cluster_name" {
  prefix = "cluster"
}

resource "random_pet" "azurerm_kubernetes_cluster_dns_prefix" {
  prefix = "dns"
}

resource "azurerm_log_analytics_workspace" "k8s" {
  name                = "k8s-workspace-${random_pet.azurerm_kubernetes_cluster_name.id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
}

resource "azurerm_log_analytics_solution" "example" {
  solution_name         = "ContainerInsights"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.k8s.id
  workspace_name        = azurerm_log_analytics_workspace.k8s.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}

resource "azurerm_kubernetes_cluster" "k8s" {
  location             = azurerm_resource_group.rg.location
  name                 = random_pet.azurerm_kubernetes_cluster_name.id
  resource_group_name  = azurerm_resource_group.rg.name
  dns_prefix           = random_pet.azurerm_kubernetes_cluster_dns_prefix.id
  azure_policy_enabled = true
  tags = {
    "env" = "production"
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.k8s.id
  }

  default_node_pool {
    name                         = "sysnodepool"
    vm_size                      = var.vm_size
    node_count                   = var.node_count
    only_critical_addons_enabled = true
  }
  linux_profile {
    admin_username = var.username

    ssh_key {
      key_data = jsondecode(azapi_resource_action.ssh_public_key_gen.output).publicKey
    }
  }
  network_profile {
    network_plugin    = "azure"     ## To use with Azure-CNI. Other option is kubenet
    load_balancer_sku = "standard"
  }
}

data "azurerm_kubernetes_cluster" "k8s" {
  name                = azurerm_kubernetes_cluster.k8s.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_kubernetes_cluster_node_pool" "usernodepool" {
  name                  = "usernodepool"
  kubernetes_cluster_id = data.azurerm_kubernetes_cluster.k8s.id
  vm_size               = var.vm_size
  node_count            = var.node_count
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 2
  mode                  = "User"

  tags = {
    env = "production"
  }
}
