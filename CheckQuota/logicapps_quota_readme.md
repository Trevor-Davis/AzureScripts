# Logic Apps Standard quota check

This script checks Azure CLI access, Microsoft.Web quota, Microsoft.Web regional usage, and Workflow Standard SKU availability for Logic Apps Standard deployments.

## File

```powershell
logicapps_quota.ps1
```

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Azure CLI installed
- Permission to read the target Azure subscription
- Internet access to Azure management endpoints

The script checks for the Azure CLI `quota` extension and installs it automatically if it is missing.

## How to run

Open PowerShell and run:

```powershell
cd "<path-to-repo>\AzureScripts\CheckQuota"
.\logicapps_quota.ps1
```

When prompted, enter:

- Azure subscription ID, for example `00000000-0000-0000-0000-000000000000`
- Azure region, for example `eastus` or `East US`

If you are not already signed in to Azure CLI, the script will prompt you to sign in with `az login`.

## What the script checks

1. Azure CLI is installed.
2. Azure CLI `quota` extension is installed.
3. Azure CLI is signed in.
4. The signed-in account can access the target subscription.
5. Microsoft.Web quota entries for the target region.
6. Microsoft.Web regional usage entries for the target region.
7. Workflow Standard availability for `WS1`, `WS2`, and `WS3`, grouped by region.

## How to interpret the output

- If `Current` is lower than `Limit`, visible Microsoft.Web quota is available.
- If `Current` equals `Limit`, request additional Microsoft.Web quota for that region.
- If the target region is not listed for `WS1`, `WS2`, or `WS3`, choose a supported region or confirm regional support.
- If quota is available and the target region is listed but deployment still fails, the issue may be live regional SKU capacity for Logic Apps Standard rather than visible subscription quota.

## Notes

Logic Apps Standard uses Workflow Standard App Service plan SKUs:

| SKU | Meaning |
| --- | --- |
| WS1 | Workflow Standard 1 |
| WS2 | Workflow Standard 2 |
| WS3 | Workflow Standard 3 |

The region availability list shows where each SKU is generally offered. It does not guarantee live capacity for a specific deployment at a specific moment.
