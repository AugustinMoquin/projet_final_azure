variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "project_name" {
  description = "Short project slug used to prefix resource names (lowercase, no spaces)."
  type        = string
  default     = "docpipe"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.project_name))
    error_message = "project_name must be 3-12 chars, lowercase letters and digits only."
  }
}

variable "location" {
  description = "Azure region for most resources."
  type        = string
  default     = "francecentral"
}

variable "openai_location" {
  description = "Region for Azure OpenAI. Not every region has capacity; swedencentral / eastus are safe."
  type        = string
  default     = "swedencentral"
}

variable "enable_openai" {
  description = "Set false if your subscription is not yet approved for Azure OpenAI. The Functions will fall back to rule-based tagging."
  type        = bool
  default     = true
}

variable "openai_model" {
  description = "Azure OpenAI model name to deploy."
  type        = string
  default     = "gpt-4o-mini"
}

variable "openai_model_version" {
  description = "Model version for the deployment."
  type        = string
  default     = "2024-07-18"
}

variable "enable_language" {
  description = "Use Azure AI Language (key-phrase extraction) for tagging. No quota gate, free F0 tier. Brief-approved alternative to Azure OpenAI."
  type        = bool
  default     = true
}

variable "language_location" {
  description = "Region for Azure AI Language. Widely available; France Central works."
  type        = string
  default     = "francecentral"
}

variable "language_sku" {
  description = "SKU for Azure AI Language. F0 = free (one per region/subscription), S = pay-as-you-go."
  type        = string
  default     = "F0"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project   = "projet-azure-pipeline"
    managedBy = "terraform"
    course    = "m2-iot-cloud"
  }
}
