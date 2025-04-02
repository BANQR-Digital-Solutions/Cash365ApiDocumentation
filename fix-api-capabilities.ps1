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
    Write-Host "Parsing EDMX capabilities..."
    
    # Load EDMX as XML
    $xml = [xml]$edmxContent
    
    # Create XML namespace manager
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsManager.AddNamespace("edmx", "http://docs.oasis-open.org/odata/ns/edmx")
    $nsManager.AddNamespace("edm", "http://docs.oasis-open.org/odata/ns/edm")
    
    # Find all EntitySet elements using namespace manager
    $entitySets = $xml.SelectNodes("//edm:EntitySet", $nsManager)
    
    foreach ($entitySet in $entitySets) {
        $entityName = $entitySet.Name
        
        # Find capability annotations with correct paths
        $deletable = $entitySet.SelectSingleNode(".//edm:Annotation[@Term='Org.OData.Capabilities.V1.DeleteRestrictions']//edm:PropertyValue[@Property='Deletable']", $nsManager)?.Bool -eq 'true'
        $insertable = $entitySet.SelectSingleNode(".//edm:Annotation[@Term='Org.OData.Capabilities.V1.InsertRestrictions']//edm:PropertyValue[@Property='Insertable']", $nsManager)?.Bool -eq 'true'
        $updatable = $entitySet.SelectSingleNode(".//edm:Annotation[@Term='Org.OData.Capabilities.V1.UpdateRestrictions']//edm:PropertyValue[@Property='Updatable']", $nsManager)?.Bool -eq 'true'
        
        $capabilities[$entityName] = @{
            Deletable = $deletable
            Insertable = $insertable
            Updatable = $updatable
        }
        Write-Host "Found entity '$entityName': Deletable=$deletable, Insertable=$insertable, Updatable=$updatable"
    }
    
    if ($capabilities.Count -eq 0) {
        Write-Warning "No entity capabilities found in EDMX file!"
    } else {
        Write-Host "Found capabilities for $($capabilities.Count) entities"
    }
    
    return $capabilities
}

# Function to update YAML paths based on capabilities
function Update-YamlPaths {
    param($yaml, $capabilities)
    
    $modified = $false
    Write-Host "Updating YAML paths..."
    
    foreach ($path in $yaml.paths.PSObject.Properties.Name) {
        # Skip $count endpoints
        if ($path -match '\$count$') {
            continue
        }

        # Determine which entity this path belongs to
        $entityName = $null
        foreach ($entity in $capabilities.Keys) {
            # Match both direct paths (/entity) and parameterized paths (/entity(param))
            if ($path -match "^/$entity(?:\(|$)") {
                $entityName = $entity
                break
            }
        }

        if ($entityName -and $capabilities.ContainsKey($entityName)) {
            $entityCaps = $capabilities[$entityName]
            $pathObj = $yaml.paths.$path
            
            Write-Host "Processing path '$path' for entity '$entityName'"
            Write-Host "Capabilities: Insertable=$($entityCaps.Insertable), Updatable=$($entityCaps.Updatable), Deletable=$($entityCaps.Deletable)"

            # Root collection endpoint - check POST
            if ($path -eq "/$entityName") {
                if (-not $entityCaps.Insertable -and $pathObj.PSObject.Properties['post']) {
                    $pathObj.PSObject.Properties.Remove('post')
                    Write-Host "Removed POST operation from $path"
                    $modified = $true
                }
            }
            
            # Individual item endpoint - check PATCH/DELETE
            if ($path -match '\([^)]+\)$') {
                if (-not $entityCaps.Updatable -and $pathObj.PSObject.Properties['patch']) {
                    $pathObj.PSObject.Properties.Remove('patch')
                    Write-Host "Removed PATCH operation from $path"
                    $modified = $true
                }
                if (-not $entityCaps.Deletable -and $pathObj.PSObject.Properties['delete']) {
                    $pathObj.PSObject.Properties.Remove('delete')
                    Write-Host "Removed DELETE operation from $path"
                    $modified = $true
                }
            }
        }
    }
    
    if (-not $modified) {
        Write-Host "No changes were necessary in the YAML file"
    }
    
    return $yaml
}

try {
    # Read input files
    Write-Host "Reading EDMX from: $EdmxPath"
    $edmxContent = Get-Content $EdmxPath -Raw
    
    Write-Host "Reading YAML from: $YamlPath"
    $yamlContent = Get-Content $YamlPath -Raw
    
    # Parse YAML
    $yaml = ConvertFrom-Json $yamlContent
    
    # Get entity capabilities from EDMX
    $capabilities = Get-EntityCapabilities $edmxContent
    
    # Update YAML paths
    $updatedYaml = Update-YamlPaths $yaml $capabilities
    
    # Save changes back to original file
    $updatedYaml | ConvertTo-Json -Depth 100 | Set-Content $YamlPath
    Write-Host "Successfully updated $YamlPath"
}
catch {
    Write-Error "Error processing files: $_"
    exit 1
}