#Requires -Version 5.1

# A small draft-07 subset validator. cmdpeek ships examples/usage-examples.schema.json
# as the contract for catalog files, but nothing read it, so the schema and the code
# drifted apart silently. This validates against the schema file itself, so the schema
# stays the one place the shape is written down.

function Get-CmdPeekSchemaNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Schema,
        [Parameter(Mandatory)]$Node
    )

    if (-not $Node) { return $null }
    if ($Node.PSObject.Properties['$ref']) {
        $ref = [string]$Node.'$ref'
        if ($ref -notmatch '^#/') {
            throw "Only local schema references are supported, got '$ref'"
        }
        $current = $Schema
        foreach ($part in @($ref.Substring(2) -split '/')) {
            if (-not $current -or -not $current.PSObject.Properties[$part]) {
                throw "Schema reference '$ref' does not resolve"
            }
            $current = $current.$part
        }
        return $current
    }
    return $Node
}

function Test-CmdPeekJsonType {
    [CmdletBinding()]
    param($Value, [string]$Type)

    switch ($Type) {
        'object' { return ($null -ne $Value) -and ($Value -is [psobject]) -and -not ($Value -is [array]) -and -not ($Value -is [string]) -and -not ($Value -is [ValueType]) }
        'array' { return $Value -is [array] }
        'string' { return $Value -is [string] }
        'boolean' { return $Value -is [bool] }
        'number' { return ($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal]) }
        'integer' { return ($Value -is [int]) -or ($Value -is [long]) }
        'null' { return $null -eq $Value }
        default { return $true }
    }
}

function Test-CmdPeekJsonSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Schema,
        $Node,
        $Value,
        [string]$Path = '$'
    )

    $problems = New-Object System.Collections.Generic.List[string]
    if (-not $Node) { $Node = $Schema }
    $node = Get-CmdPeekSchemaNode -Schema $Schema -Node $Node

    if ($node.PSObject.Properties['oneOf']) {
        $matched = 0
        foreach ($option in @($node.oneOf)) {
            if (@(Test-CmdPeekJsonSchema -Schema $Schema -Node $option -Value $Value -Path $Path).Count -eq 0) { $matched++ }
        }
        if ($matched -ne 1) {
            $problems.Add("$Path does not match exactly one of the allowed shapes")
        }
        return @($problems.ToArray())
    }

    if ($node.PSObject.Properties['type']) {
        $types = @($node.type)
        $ok = $false
        foreach ($t in $types) {
            if (Test-CmdPeekJsonType -Value $Value -Type ([string]$t)) { $ok = $true; break }
        }
        if (-not $ok) {
            $problems.Add("$Path should be $($types -join ' or ')")
            return @($problems.ToArray())
        }
    }

    if ($node.PSObject.Properties['enum'] -and $null -ne $Value) {
        $allowed = @($node.enum)
        if ($allowed -notcontains $Value) {
            $problems.Add("$Path is '$Value', which is not one of: $($allowed -join ', ')")
        }
    }

    if ($node.PSObject.Properties['minLength'] -and $Value -is [string]) {
        if ($Value.Length -lt [int]$node.minLength) {
            $problems.Add("$Path is shorter than $([int]$node.minLength) characters")
        }
    }

    if ($Value -is [array]) {
        if ($node.PSObject.Properties['minItems'] -and @($Value).Count -lt [int]$node.minItems) {
            $problems.Add("$Path has $(@($Value).Count) items, needs at least $([int]$node.minItems)")
        }
        if ($node.PSObject.Properties['items']) {
            $i = 0
            foreach ($item in @($Value)) {
                foreach ($p in @(Test-CmdPeekJsonSchema -Schema $Schema -Node $node.items -Value $item -Path "$Path[$i]")) {
                    $problems.Add($p)
                }
                $i++
            }
        }
        return @($problems.ToArray())
    }

    if ($Value -is [psobject] -and -not ($Value -is [string]) -and -not ($Value -is [ValueType])) {
        # An empty JSON object has no properties to enumerate, and member enumeration
        # over an empty collection is an error under Set-StrictMode.
        $present = @(foreach ($p in $Value.PSObject.Properties) { $p.Name })

        # JSON keys are case sensitive, and PowerShell's -contains is not, so a
        # "whentouse" typo would read as the declared "whenToUse" and pass.
        if ($node.PSObject.Properties['required']) {
            foreach ($name in @($node.required)) {
                if ($present -cnotcontains $name) {
                    $problems.Add("$Path is missing required property '$name'")
                }
            }
        }

        $declared = @()
        if ($node.PSObject.Properties['properties']) {
            $declared = @(foreach ($p in $node.properties.PSObject.Properties) { $p.Name })
            foreach ($prop in $node.properties.PSObject.Properties) {
                if ($present -cnotcontains $prop.Name) { continue }
                foreach ($p in @(Test-CmdPeekJsonSchema -Schema $Schema -Node $prop.Value -Value $Value.($prop.Name) -Path "$Path.$($prop.Name)")) {
                    $problems.Add($p)
                }
            }
        }

        $extraSchema = $null
        $allowExtra = $true
        if ($node.PSObject.Properties['additionalProperties']) {
            $ap = $node.additionalProperties
            if ($ap -is [bool]) { $allowExtra = [bool]$ap }
            else { $extraSchema = $ap }
        }

        foreach ($name in $present) {
            if ($declared -ccontains $name) { continue }
            if (-not $allowExtra) {
                $problems.Add("$Path has unknown property '$name'")
                continue
            }
            if ($extraSchema) {
                foreach ($p in @(Test-CmdPeekJsonSchema -Schema $Schema -Node $extraSchema -Value $Value.$name -Path "$Path.$name")) {
                    $problems.Add($p)
                }
            }
        }
    }

    return @($problems.ToArray())
}

function Get-CmdPeekCatalogSchemaPath {
    [CmdletBinding()]
    param()

    $root = $script:CmdPeekModuleRoot
    if (-not $root) { $root = $PSScriptRoot }
    foreach ($candidate in @(
            (Join-Path $root 'examples/usage-examples.schema.json'),
            (Join-Path (Split-Path -Parent $root) 'examples/usage-examples.schema.json')
        )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

# Fields that make a catalog entry useful to an agent rather than just runnable.
# Reported as coverage, not as errors: a brand new entry with usages is still valid.
$script:CmdPeekCatalogRichField = @(
    'whenToUse'
    'whenNotToUse'
    'gotchas'
    'substitutes'
    'related'
    'capabilities'
    'tasks'
    'os'
    'origin'
)

function Get-CmdPeekCatalogCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $names = @()
    if ($Document -and $Document.PSObject.Properties['commands'] -and $Document.commands) {
        $names = @($Document.commands.PSObject.Properties.Name)
    }
    $total = $names.Count

    foreach ($field in $script:CmdPeekCatalogRichField) {
        $have = 0
        $lacking = New-Object System.Collections.Generic.List[string]
        foreach ($name in $names) {
            $entry = $Document.commands.$name
            $value = $null
            if ($entry -and $entry.PSObject.Properties[$field]) { $value = $entry.$field }
            $filled = $false
            if ($value -is [array]) { $filled = @($value).Count -gt 0 }
            elseif ($value -is [string]) { $filled = -not [string]::IsNullOrWhiteSpace($value) }
            elseif ($null -ne $value) { $filled = $true }
            if ($filled) { $have++ } else { $lacking.Add($name) }
        }
        $percent = 0
        if ($total -gt 0) { $percent = [int][math]::Round(100 * $have / $total) }
        $rows.Add([pscustomobject]@{
                field   = $field
                have    = $have
                total   = $total
                percent = $percent
                missing = @($lacking.ToArray())
            })
    }

    return @($rows.ToArray())
}

function Get-CmdPeekCatalogFileList {
    [CmdletBinding()]
    param(
        [string[]]$Path,
        [string]$ExamplesPath
    )

    # @($null).Count is 1, so an unbound -Path has to be filtered, not just counted.
    $explicit = @(@($Path) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($explicit.Count -gt 0) { return $explicit }
    if ($ExamplesPath) { return @($ExamplesPath) }

    $root = $script:CmdPeekModuleRoot
    if (-not $root) { $root = $PSScriptRoot }
    $dirs = @((Join-Path $root 'examples'), (Join-Path (Split-Path -Parent $root) 'examples'))
    return @(
        foreach ($name in @('usage-examples.json', 'system-commands.json')) {
            foreach ($dir in $dirs) {
                $candidate = Join-Path $dir $name
                if (Test-Path -LiteralPath $candidate) { $candidate; break }
            }
        }
    )
}

function Invoke-CmdPeekCatalogLint {
    [CmdletBinding()]
    param(
        [string[]]$Path,
        [string]$ExamplesPath
    )

    $targets = @(Get-CmdPeekCatalogFileList -Path $Path -ExamplesPath $ExamplesPath)
    $results = @(foreach ($target in $targets) { Test-CmdPeekCatalogFile -Path $target -SkipCrossReference })

    # Cross-reference checks run on the union, not on each file. usage-examples.json
    # points at Select-String and system-commands.json points back at rg, and both are
    # correct because cmdpeek merges the files before anything reads them.
    $merged = @{}
    $mergedKits = @{}
    foreach ($r in $results) {
        foreach ($key in @($r.catalog.Keys)) {
            if (-not $merged.ContainsKey($key)) { $merged[$key] = $r.catalog[$key] }
        }
        foreach ($key in @($r.kitMap.Keys)) {
            if (-not $mergedKits.ContainsKey($key)) { $mergedKits[$key] = $r.kitMap[$key] }
        }
    }
    $crossReference = @(Test-CmdPeekCatalog -Catalog $merged -Kits $mergedKits)

    $errorCount = $crossReference.Count
    foreach ($r in $results) { $errorCount += @($r.errors).Count }
    return [pscustomobject]@{
        files          = $results
        crossReference = $crossReference
        commands       = $merged.Count
        kits           = $mergedKits.Count
        errorCount     = $errorCount
    }
}

function Test-CmdPeekCatalogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$SchemaPath,
        [switch]$SkipCrossReference
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $empty = [pscustomobject]@{
        path = $Path; errors = @(); coverage = @(); commands = 0; kits = 0
        catalog = @{}; kitMap = @{}
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $empty.errors = @("File not found: $Path")
        return $empty
    }

    $document = $null
    try {
        $document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $empty.errors = @("Not valid JSON: $($_.Exception.Message)")
        return $empty
    }

    if (-not $SchemaPath) { $SchemaPath = Get-CmdPeekCatalogSchemaPath }
    if ($SchemaPath -and (Test-Path -LiteralPath $SchemaPath)) {
        $schema = Get-Content -LiteralPath $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($problem in @(Test-CmdPeekJsonSchema -Schema $schema -Value $document)) {
            $errors.Add($problem)
        }
    }
    else {
        $errors.Add('Schema file not found, so only cross-reference checks ran')
    }

    $catalog = @{}
    if ($document.PSObject.Properties['commands'] -and $document.commands) {
        foreach ($prop in $document.commands.PSObject.Properties) {
            $catalog[$prop.Name] = $prop.Value
        }
    }
    $kits = @{}
    if ($document.PSObject.Properties['kits'] -and $document.kits) {
        foreach ($prop in $document.kits.PSObject.Properties) {
            $kits[$prop.Name] = @($prop.Value)
        }
    }
    if (-not $SkipCrossReference) {
        foreach ($problem in @(Test-CmdPeekCatalog -Catalog $catalog -Kits $kits)) {
            $errors.Add($problem)
        }
    }

    return [pscustomobject]@{
        path     = $Path
        errors   = @($errors.ToArray())
        coverage = @(Get-CmdPeekCatalogCoverage -Document $document)
        commands = $catalog.Count
        kits     = $kits.Count
        catalog  = $catalog
        kitMap   = $kits
    }
}

function Format-CmdPeekCatalogLint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Lint
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Lint.files)) {
        $errs = @($r.errors)
        $lines.Add("$($r.path)  $($r.commands) commands, $($r.kits) kits")
        if ($errs.Count -eq 0) {
            $lines.Add('  schema valid')
        }
        else {
            foreach ($e in $errs) { $lines.Add("  ! $e") }
        }
        $lines.Add('')
        $lines.Add('  agent-facing field coverage')
        foreach ($row in @($r.coverage)) {
            $bar = ('#' * [int][math]::Round($row.percent / 5)).PadRight(20, '.')
            $lines.Add(('    {0,-13} {1,3}%  {2}  {3}/{4}' -f $row.field, $row.percent, $bar, $row.have, $row.total))
        }
        foreach ($row in @($r.coverage | Where-Object { $_.percent -lt 100 -and @($_.missing).Count -le 12 })) {
            $lines.Add(("    {0} missing on: {1}" -f $row.field, (@($row.missing) -join ', ')))
        }
        $lines.Add('')
    }

    $xref = @($Lint.crossReference)
    $lines.Add("Merged catalog: $($Lint.commands) commands, $($Lint.kits) kits")
    if ($xref.Count -eq 0) {
        $lines.Add('  every related, substitute, and kit member resolves')
    }
    else {
        foreach ($e in $xref) { $lines.Add("  ! $e") }
    }
    $lines.Add('')

    if ([int]$Lint.errorCount -eq 0) { $lines.Add('No catalog errors.') }
    else { $lines.Add("$([int]$Lint.errorCount) catalog error(s).") }
    return ($lines -join [Environment]::NewLine)
}
