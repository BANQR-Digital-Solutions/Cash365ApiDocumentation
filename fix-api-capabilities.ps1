param(
    [Parameter(Mandatory=$true)]
    [string]$EdmxPath,
    
    [Parameter(Mandatory=$true)]
    [string]$YamlPath
)

# Function to parse EDMX capabilities
function Get-EntityCapabilities {
    param($edmxContent)
    
    $capabilities = @{}
    
    # Load EDMX as XML
    $xml = [xml]$edmxContent
    $entitySets = $xml.SelectNodes("//EntitySet")
    
    foreach ($entitySet in $entitySets) {
        $entityName = $entitySet.Name
        $deletable = $entitySet.SelectSingleNode(".//PropertyValue[@Property='Deletable']")?.Bool -eq 'true'
        $insertable = $entitySet.SelectSingleNode(".//PropertyValue[@Property='Insertable']")?.Bool -eq 'true'
        $updatable = $entitySet.SelectSingleNode(".//PropertyValue[@Property='Updatable']")?.Bool -eq 'true'
        
        $capabilities[$entityName] = @{
            Deletable = $deletable
            Insertable = $insertable
            Updatable = $updatable
        }
    }
    
    return $capabilities
}

# Function to update YAML paths based on capabilities
function Update-YamlPaths {
    param($yaml, $capabilities)
    
    foreach ($entityName in $capabilities.Keys) {
        $entityCaps = $capabilities[$entityName]
        
        # Collection endpoint paths
        $collectionPath = "/$entityName"
        if ($yaml.paths.$collectionPath -and -not $entityCaps.Insertable) {
            if ($yaml.paths.$collectionPath.post) {
                $yaml.paths.$collectionPath.PSObject.Properties.Remove('post')
            }
        }
        
        # Individual item endpoint paths
        $itemPaths = $yaml.paths.PSObject.Properties.Name | Where-Object { 
            $_ -like "/$entityName(*)" -and -not $_ -like "*/*" 
        }
        
        foreach ($path in $itemPaths) {
            if (-not $entityCaps.Updatable) {
                if ($yaml.paths.$path.patch) {
                    $yaml.paths.$path.PSObject.Properties.Remove('patch')
                }
            }
            if (-not $entityCaps.Deletable) {
                if ($yaml.paths.$path.delete) {
                    $yaml.paths.$path.PSObject.Properties.Remove('delete')
                }
            }
        }
    }
    
    return $yaml
}

try {
    # Read input files
    $edmxContent = Get-Content $EdmxPath -Raw
    $yamlContent = Get-Content $YamlPath -Raw
    
    # Parse YAML
    $yaml = ConvertFrom-Json $yamlContent -AsHashtable
    
    # Get entity capabilities from EDMX
    $capabilities = Get-EntityCapabilities $edmxContent
    
    # Update YAML paths
    $updatedYaml = Update-YamlPaths $yaml $capabilities
    
    # Save updated YAML
    $updatedYaml | ConvertTo-Json -Depth 100 | Set-Content $YamlPath
    
    Write-Host "Successfully updated API capabilities in: $YamlPath"
}
catch {
    Write-Error "Error processing files: $_"
    exit 1
}