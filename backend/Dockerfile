# Containerized Azure Functions (Python). The Functions runtime in this base
# image keeps all triggers working (blob, Service Bus, SignalR bindings) — the
# host establishes the listeners itself, so it runs fine on Azure Container Apps.
FROM mcr.microsoft.com/azure-functions/python:4-python3.11

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true

COPY requirements.txt /
RUN pip install --no-cache-dir -r /requirements.txt

COPY . /home/site/wwwroot
