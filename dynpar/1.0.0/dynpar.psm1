$code = @'
using System;
using System.Collections.Generic;
using System.Management.Automation;

    public class DynamicAttribute : System.Attribute
    {
        private ScriptBlock sb;

        public DynamicAttribute(ScriptBlock condition) 
        {
            sb = condition;
        }
    }
'@

$null = Add-Type -TypeDefinition $code *>&1

function Get-PsoDynamicParameterDefinition
{
    <#
            .SYNOPSIS
            takes a scriptblock with a static param() parameter definition and returns a PowerShell function where designated parameters are turned into dynamic parameters.

            .DESCRIPTION
            Module adds a new attribute named [Dynamic()] that can be used to turn static parameters into dynamic parameters.
            For this to work, submit a scriptblock to the attribute. When the scriptblock evaluates to $true, the parameter is visible, else it is not available.

            .EXAMPLE
            Get-PsoDynamicParameterDefinition -ScriptBlock Value -FunctionName Value
            Takes the parameter definition from $parameters, turns all parameters designated with the attribute [Dynamic()] into dynamic parameters and emits the new function body 

            .EXAMPLE
            Get-PsoDynamicParameterDefinition -FunctionInfo Value
            Describe what this call does

            .LINK
            https://github.com/TobiasPSP/Modules.dynamicparam
    #>

    [CmdletBinding()]
    param
    (
        # A scriptblock with a param() block. Assign the attribute [Dynamic()] to all parameters that you want to convert to a dynamic parameter.
        [Parameter(Mandatory,ValueFromPipeline)]
        [ScriptBlock]
        $ScriptBlock,

        # Name of the function to be created. Can be anything, should adhere to common Verb-Noun syntax.
        [string]
        $FunctionName = 'Get-Something'
    )

    begin
    {
        # common parameters
        $commonParameters = 'Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable'
    }

    process
    {
        $beginBlock = "# place your own code that executes before pipeline processing starts"
        $processBlock = '# place your own code that executes for each incoming pipeline object'
        $endBlock = '# place your own code that executes after pipeline processing has finished'

        # collect generated code:
        [System.Text.StringBuilder]$result = ''

        # store parameter default values:
        $defaultValues = @{}

        # store list of dynamic parameters:
        $dynParamList = [System.Collections.ObjectModel.Collection[string]]::new()

        # store list of static parameters:
        $paramList = [System.Collections.ObjectModel.Collection[string]]::new()

        # store list of pipeline-aware parameters:
        $pipelineAttribs = 'ValueFromPipeline', 'ValueFromPipelineByPropertyName'
        $pipelineParamList = [System.Collections.ObjectModel.Collection[string]]::new()

        $null = $result.AppendLine("function $FunctionName")
        $null = $result.AppendLine('{')

        # extract the content of the param() block from the submitted scriptblock:
        $pb = $ScriptBlock.Ast.FindAll({$args[0] -is [System.Management.Automation.Language.ParamBlockAst]}, $false)

        $param = $pb[0]

        # add attributes
        foreach($_ in $param.Attributes)
        {
            $null = $result.AppendLine('    ' + $_.Extent.Text)
        }

        $null = $result.AppendLine(@'
    # MUST be an advanced function so make sure you add [CmdletBinding()] just to be sure:
    [CmdletBinding()]
    param
    (
        ##StaticParams##
    )

    dynamicparam
    {
        # create container for all dynamically created parameters:
        $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

'@)

    
        $param.Parameters | ForEach-Object {
            $parameter = $_

            # check to see if this parameter was decorated with a [Dynamic()] attribute:
            $dynamicAttribute = $parameter.Attributes.Where{ $_.TypeName.FullName -eq 'Dynamic' } | Select-Object -First 1

            # if so, add to dynamic parameters:
            if ($dynamicAttribute)
            {
                $condition = $dynamicAttribute.PositionalArguments[0].Extent.Text -replace '^{' -replace '}$'
            
                $name = $parameter.Name.VariablePath.UserPath
                $dynParamList.Add($name)
                $null = $result.AppendLine('')
                $null = $result.AppendLine("        #region Start Parameter -${name} ####")
                if ($condition)
                {
                    $null = $result.AppendLine("        if ($condition) {")
                }
                $null = $result.AppendLine("        # create container storing all attributes for parameter -$name")
                $null = $result.AppendLine('        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()')
                $null = $result.AppendLine('')
            
                $conflicts = $commonParameters -like "$name*"
                if ($conflicts.Count -gt 0)
                {
                    Write-Warning ('Parameter -{0} conflicts with built-in parameters {1}. Rename -{0}.' -f $name, ('-' + ($conflicts -join ', -')))
                }

                $defaultValue = $parameter.DefaultValue.Extent.Text
            
                $theType = 'Object'

                $hasParameterAttribute = $false
        
                $parameter.Attributes | ForEach-Object {
                    $attribute = $_
                    switch ($attribute.GetType().FullName)
                    {
                        'System.Management.Automation.Language.TypeConstraintAst'  { 
                            $theType = $attribute.TypeName.FullName
                        }
                        'System.Management.Automation.Language.AttributeAst' {
                            $typeName = $attribute.TypeName.FullName
                            if ($typename -ne 'Dynamic')
                            {
                                if (!$hasParameterAttribute -and $typename -eq 'Parameter') { $hasParameterAttribute = $true }
                                [string]$positionals = $attribute.PositionalArguments.Extent.Text -join ','
                                $null = $result.AppendLine(('        # Define attribute [{0}()]:' -f $attribute.TypeName.FullName))
                                $null = $result.AppendLine(('        $attrib = [{0}]::new({1})' -f $attribute.TypeName.FullName, $positionals))
                                $attribute.NamedArguments | ForEach-Object {
                                    $namedAttributeExpression = $_.ToString()
                                    if ($_.ExpressionOmitted)
                                    { $namedAttributeExpression += '=$true'}
                            
                                    $null = $result.AppendLine(('        $attrib.{0}' -f $namedAttributeExpression))

                                    # if parameter is pipeline-aware, remember it:
                                    if ($_.ArgumentName -in $pipelineAttribs -and $pipelineParamList.Contains($Name) -eq $false) 
                                    { $pipelineParamList.Add($name) }
                                }
                                $null = $result.AppendLine('        $attributeCollection.Add($attrib)')
                                $null = $result.AppendLine('')
                            }
                        }
                        default {
                            Write-Warning "Unexpected Type: $_"
                        }
                    }            
            
                }
                if (!$hasParameterAttribute)
                {
                    $null = $result.AppendLine('        # Define attribute [Parameter()]:')
                    $null = $result.AppendLine('        $attrib = [Parameter]::new()')
                    $null = $result.AppendLine('        $attributeCollection.Add($attrib)')
                    $null = $result.AppendLine('')
                }
                $null = $result.AppendLine('        # compose dynamic parameter:')
                $null = $result.AppendLine(('        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new({0},{1},$attributeCollection)' -f "'$Name'", "[$theType]"))
                if ($theType -eq 'Object')
                { Write-Warning ('Parameter -{0} currently is of type [Object]. Using an appropriate type constraint like [string], [int], [datetime] etc in your parameter definition is recommended.' -f $Name) }

                # store parameter default value:
                if ($defaultValue -ne $null)
                {
                    $defaultValues[$name] = $defaultValue
                }
                $null = $result.AppendLine('')
                $null = $result.AppendLine('        # add parameter to parameter collection:')
                $null = $result.AppendLine(('        $paramDictionary.Add({0},$dynParam)' -f "'$Name'"))
                if ($condition)
                {
                    $null = $result.AppendLine("        }")
                }
                $null = $result.AppendLine("        #endregion End Parameter -${name} ####")
                $null = $result.AppendLine('')
            }
            # else, add to static parameters
            else
            {
                $paramList.Add($parameter.Extent.Text)
            }
        }

    
        # determine the maximum parameter name length for formatting purposes:
        $longest = 0
        foreach($_ in $dynParamList)
        {
            $longest = [Math]::Max($longest, $_.Length)
        }

        $null = $result.AppendLine(@'

        # return dynamic parameter collection:
        $paramDictionary
    }
    
    begin
    {
        
'@)
    
        $null = $result.AppendLine('        #region initialize variables for dynamic parameters')
        foreach($varName in $dynParamList)
        {
            $null = $result.AppendLine('')
            $null = $result.AppendLine(('        if($PSBoundParameters.ContainsKey(''{0}'')) {{ ${0} = $PSBoundParameters[''{0}''] }}' -f $varName))
            if ($defaultValues.ContainsKey($varName))
            {
                $null = $result.AppendLine(('        else {{ ${0} = {1} }}' -f $varName, $defaultValues[$varName]))        
            }
            else
            {
                $null = $result.AppendLine(('        else {{ ${0} = $null}}' -f $varName))
            }
        }
        $null = $result.AppendLine('        #endregion initialize variables for dynamic parameters')
        $null = $result.AppendLine(@"

        $beginBlock
    }
 
    process
    {
"@)
        if ($pipelineAttribs.Count -gt 0)
        {
            $null = $result.AppendLine('        #region update variables for pipeline-aware parameters:')
            foreach($varName in $pipelineParamList)
            {
                $null = $result.AppendLine(('        if ($PSBoundParameters.ContainsKey(''{0}'')) {{ ${0} = $PSBoundParameters[''{0}''] }}' -f $varName))
            }
            $null = $result.AppendLine('        #endregion update variables for pipeline-aware parameters')
            $null = $result.AppendLine(@'
        
        #region output pipeline-aware parameters for diagnostic purposes:
        [PSCustomObject]@{
            ParameterSetName = $PSCmdlet.ParameterSetName
'@)
            foreach($varName in $pipelineParamList)
            {
                # pad the parameter name so the assignments are aligned:
                $null = $result.AppendLine(('            {0} = ${1}' -f $varName.PadRight($longest), $varName))
            }
            $null = $result.AppendLine(@'
        } | Format-List

        #endregion output pipeline-aware parameters for diagnostic purposes
'@)
        }
        $null = $result.AppendLine(@"

        $processBlock
    }

    end
    {
        #region output submitted parameters for diagnostic purposes:
        [PSCustomObject]@{
"@)
    
        $dynParamList | Sort-Object | ForEach-Object {
            # pad the parameter name so the assignments are aligned:
            $null = $result.AppendLine(('            {0} = ${1}' -f $_.PadRight($longest), $_))
        }
        $null = $result.AppendLine(@"
        } | Format-List

        #endregion output submitted parameters for diagnostic purposes

        $endBlock
    }
}
"@)

        # insert list of static parameters (if any present)
        # into param() inside the composed code:
        # turn array of parameters in comma-separated list:
        $staticParams = $paramList -join ",`r`n`r`n        "
        # replace placeholder in the result with the static parameter list:
        $null = $result.Replace('##StaticParams##', $staticParams)

        # return composed script code:
        return [ScriptBlock]::Create($result)
    }
}

Set-Alias -Name Get-DynamicParameterDefinition -Value Get-PsoDynamicParameterDefinition
Set-Alias -Name Get-DynamicParameterDefinition -Value gdp