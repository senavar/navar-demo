module "naming" {
  source  = "Azure/naming/azurerm"
  version = "~> 0.4.0"
  suffix  = [var.environment, "navarlab"]
}

data "azurerm_lb" "internal_lb" {
  name                = "kubernetes-internal"
  resource_group_name = var.node_resource_group
}

data "azurerm_key_vault_secret" "appgw_tls" {
  name         = var.certificate_secret_name
  key_vault_id = var.key_vault_id
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

  identity {
    type         = "UserAssigned"
    identity_ids = [var.appgw_uami_id]
  }

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

  # HTTPS frontend port
  frontend_port {
    name = "port443"
    port = 443
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
    host                = var.frontend_hosts[0]
    port                = 80
    match {
      status_code = ["200-399"]
    }
  }

  # HTTP listener kept only for redirect purposes
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-public"
    frontend_port_name             = "port80"
    protocol                       = "Http"
  }
  ssl_certificate {
    name                = "primary-tls"
    key_vault_secret_id = data.azurerm_key_vault_secret.appgw_tls.id
  }

  http_listener {
    name                           = "listener-https"
    frontend_ip_configuration_name = "frontend-public"
    frontend_port_name             = "port443"
    protocol                       = "Https"
    ssl_certificate_name           = "primary-tls"
    host_names                     = var.frontend_hosts
  }

  # Redirect configuration for HTTP -> HTTPS
  redirect_configuration {
    name                 = "http-to-https"
    redirect_type        = "Permanent"
    include_path         = true
    include_query_string = true
    target_listener_name = "listener-https"
  }

  # Redirect rule (HTTP -> HTTPS)
  request_routing_rule {
    name                        = "rule-http-redirect"
    rule_type                   = "Basic"
    http_listener_name          = "listener-http"
    redirect_configuration_name = "http-to-https"
    priority                    = 10
  }

  # Primary HTTPS routing rule
  request_routing_rule {
    name                       = "rule-https"
    rule_type                  = "Basic"
    http_listener_name         = "listener-https"
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

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }
}

output "application_gateway_id" {
  value = azurerm_application_gateway.this.id
}
output "application_gateway_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}
