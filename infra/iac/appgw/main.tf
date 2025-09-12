module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.0"
  suffix  = [var.environment, "navarlab"]
}

data "azurerm_lb" "internal_lb" {
  name                = "kubernetes-internal"
  resource_group_name = var.node_resource_group
}

resource "azurerm_public_ip" "appgw" {
  name                = module.naming.public_ip.name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {

  name                = module.naming.application_gateway.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 2
    max_capacity = 5
  }

  gateway_ip_configuration {
    name      = "gateway-ipcfg"
    subnet_id = var.appgw_subnet_id
  }

  frontend_port {
    name = "port80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-public"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name         = "aks-ingress-pool"
    ip_addresses = [data.azurerm_lb.internal_lb.frontend_ip_configuration[0].private_ip_address]
  }

  backend_http_settings {
    name                                = "http-settings"
    port                                = 80
    protocol                            = "Http"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = false
    probe_name                          = "http-probe-aks-ingress"
  }

  probe {
    name                = "http-probe-aks-ingress"
    protocol            = "Http"
    path                = var.probe_path
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    host                = var.frontend_host
    port                = 80
    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-public"
    frontend_port_name             = "port80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule-http"
    rule_type                  = "Basic"
    http_listener_name         = "listener-http"
    backend_address_pool_name  = "aks-ingress-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 1
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }
}

output "application_gateway_id" {
  value = azurerm_application_gateway.this.id
}
output "application_gateway_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}
