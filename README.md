# Creating Dynamic Parameters (Easily)

This is the home of the PowerShell module **dynpar** which allows you to easily create dynamic parameters. The latest module version can also be found in the *PowerShell Gallery*: https://www.powershellgallery.com/packages/dynpar/

In short, with **dynpar** you can decorate any parameter in your *regular* parameter declaration and make it dynamic, so it will only appear if the condition is met that you submitted to **[Dynamic()]**:

```powershell
param
(
    # regular static parameter
    [string]
    $Normal,
        
    # show -Lunch only at 11 a.m. or later
    [Dynamic({(Get-Date).Hour -ge 11})]
    [switch]
    $Lunch,
        
    # show -Mount only when -Path refers to a local path (and not a UNC path)
    [string]
    $Path,
        
    [Dynamic({$PSBoundParameters['Path'] -match '^[a-z]:'})]
    [switch]
    $Mount
)
```

The sections below walk you through the new functionality:

## Built-In Static Parameters (Created at Design Time)

To understand advanced *dynamic* parameters, let's quickly rehearse their simple counterparts: *static* parameters. PowerShell supports *static* parameters via its declarative `param()` structure, and it is very straight-forward to define parameters. 

You can even define fairly advanced logic such as mutually exclusive parameters (which work a little bit like overloads in classic programming) by assigning different parameterset names:

```powershell
function Start-Test
{
    [CmdletBinding(DefaultParameterSetName='Text')]
    param
    (
        [Parameter(Mandatory,Position=0,ParameterSetName='Text')]
        [string]
        $Text,
        
        [Parameter(Mandatory,Position=0,ParameterSetName='Number')]
        [int]
        $Number
    )
  
  
    if ($PSCmdlet.ParameterSetName -eq 'Text')
    {
        "Your text: $Text"
    }
    else
    {
        "Your number: $Number"
    }

}
```

This example creates mutually exclusive parameters, so you can *either* submit a text *or* a number, and PowerShell even tells you the user choice so you can respond adequately:

```
PS> Start-Test 12
Your number: 12

PS> Start-Test "Hello"
Your text: Hello
```

That's pretty cool and relatively simple to implement. However implementation is *static*: you have defined parameters at design time (when you wrote the code) so the behavior of your parameters will now be always indentical.

Hm. But what if you wanted to show parameters based on what the user has already submitted to other parameters? What if a parameter should only be present when the user has Admin privileges? So what if you need more control during *runtime*?

## Dynamic Parameters (Created at Runtime)

*Dynamic* parameters are fully controllable at *runtime*, so you can (by code) choose to show parameters based on what a user already submitted to another parameter. You can show or hide dynamic parameters also based on other runtime conditions such as whether the user currently has admin privileges, or whatever else you need.

The flipside is that in order to be so flexible, *dynamic* parameters can't be declared like their *static* counterparts. They need to be programmed and fiddle with a vast number of non-intuitive types.

The module **dynpar** changes this and makes creating *dynamic* parameters just as easy as it is to create *static* parameters.

The best way to understand how that works is by following a simple tutorial:

## Test case: Turning static parameters to dynamic parameters

Let's start with the following static parameters inside a simple function:

```powershell
function Start-Test
{
    param
    (
        [ValidateSet('New','Edit','Delete')]
        [string]
        $Action,
        
        # show -Id only when editing or deleting
        # when a new customer is added, the id is calculated automatically
        [Parameter(Mandatory)]
        [Guid]
        $Id,
        
        # show -CustomerName only when editing or adding a new customer:
        [string]
        $CustomerName,
        
        # show -Test only once (any) -Action value was submitted:
        [switch]
        $Test,
        
        # show -Coffee only before 11 a.m.
        [switch]
        $Coffee,
        
        # show -Lunch only at 11 a.m. or later
        [switch]
        $Lunch,
        
        # show -Mount only when -Path refers to a local path (and not a UNC path)
        [string]
        $Path,
       
        [switch]
        $Mount 
    )
}
```

When you run this code and test the new function `Start-Test`, it exposes all the defined parameters just fine. Defining static parameters is really simple.

However, these parameters do not always make sense. Let's assume we want to show or hide some of the parameters based on the `-Action` the user supplied. Or we want to mount an image file via `-Mount` only if the user in `-Path` specified a local path, and hide `-Mount` when it is a UNC path.

All of these scenarios have in common that you don't know these things at *design time*. They depend on the values a user submits at *run time*.

By default, you would now have to remove all parameters from your `param()` definition that you want to show or hide dynamically, and reconstruct them programmatically in a `dynamicparam` scriptblock. That's so tricky that even advanced PowerShell scripters often fail.

## Declaring dynamic parameters

Why not stick to the easy declarative syntax in `param()`? After all, to support *dynamic* parameters, only two additional pieces of information are needed:

* Which parameter(s) should be dynamic?
* What is the condition that needs to be met to show the parameter?

So when you import the module *dynpar*, you get a new attribute called `[DynamicParam()]` that you can use to declare dynamic parameters. Do not import the module or do anything just yet. Hang in there and just follow me for a second. At the end, you'll see how simple and easy everything is when all comes together. 

So to declare your dynamic parameters with the new `[Dynamic()]` attribute, the `param()` block from above changes to this:

```powershell
param
    (
        [ValidateSet('New','Edit','Delete')]
        [string]
        $Action,
        
        # show -Id only when editing or deleting
        # when a new customer is added, the id is calculated automatically
        [Parameter(Mandatory)]
        [Dynamic({$PSBoundParameters['Action'] -match '(Edit|Delete)'})]
        [Guid]
        $Id,
        
        # show -CustomerName only when editing or adding a new customer:
        [Dynamic({$PSBoundParameters['Action'] -match '(Edit|New)'})]
        [string]
        $CustomerName,
        
        # show -Test only once (any) -Action value was submitted:
        [Dynamic({$PSBoundParameters.ContainsKey('Action')} )]
        [switch]
        $Test,
        
        # show -Coffee only before 11 a.m.
        [Dynamic({(Get-Date).Hour -lt 11})]
        [switch]
        $Coffee,
        
        # show -Lunch only at 11 a.m. or later
        [Dynamic({(Get-Date).Hour -ge 11})]
        [switch]
        $Lunch,
        
        # show -Mount only when -Path refers to a local path (and not a UNC path)
        [string]
        $Path,
        
        [Dynamic({$PSBoundParameters['Path'] -match '^[a-z]:'})]
        [switch]
        $Mount
        
    )
```

Take a look at the multiple instances of `[Dynamic()]` in the code: the attribute takes a scriptblock as argument, and when this scriptblock evaluates to `$true`, the parameter is visible to the user.

You can't simply copy and paste this code into your test function, though, because the attribute `[Dynamic()]` is not part of PowerShell (yet). Instead, take the `param()` definition and run it through `Get-PsoDynamicParameterDefinition`.  This function is also part of the module **dynpar** and does the heavy lifting. It takes your simple and easy declarative parameter definition and turns it into a full-blown PowerShell function with the appropriate dynamic parameters in place.

# Your Turn: Follow Me!

Now it's your turn, and we go through above step by step while you run the example code in your own PowerShell editor of choice.

## Install Extension

First, download and install the module **dynpar** from the PowerShell Gallery like so:

```powershell
Install-Module -Name dynpar -Scope CurrentUser
```

Note that this needs to be done only once, however you need to do it separately for *Windows PowerShell* and *PowerShell 7* (should you use both in parallel). If you run into issues installing modules from the *PowerShell Gallery*, make sure you update the modules *PowerShellGet* and *Packagemanagement* and use the current versions. Windows 10 unfortunately ships with completely outdated versions and doesn't update them automatically.

## Design Parameters

Next, design the parameters for your function, and make use of the new `[Dynamic()]` attribute. As a starter, use this example:

```powershell
$parameter = {
    # submit a scriptblock with just a param() block
    # the param() block defines the parameter you want
    # designate the attribute [Dynamic()] to parameters that should be turned into dynamic parameters
    # dynamic parameters are visible only when certain conditions exist
    # the condition is specified as argument to [Dynamic()]. This argument is a scriptblock.
    # when the condition evaluates to $true, the parameter is added, else removed
    
    # for example, to show a parameter only before 11 a.m., add this:
    # [Dynamic({(Get-Date).Hour -lt 11})]
    
    # you can also use $PSBoundParameters to refer to other parameters that a user has already submitted
    # for example, to show a parameter only if the parameter -Test was also specified, add this:
    # [Dynamic({$PSBoundParameters.ContainsKey('Test')} )]
    # to show a parameter only if the parameter -Path start with a letter and a colon (not UNC path), try this:
    # [Dynamic({$PSBoundParameters['Path'] -match '^[a-z]:'})]


    param
    (
        [ValidateSet('New','Edit','Delete')]
        [string]
        $Action,
        
        # show -Id only when editing or deleting
        # when a new customer is added, the id is calculated automatically
        [Parameter(Mandatory)]
        [Dynamic({$PSBoundParameters['Action'] -match '(Edit|Delete)'})]
        [Guid]
        $Id,
        
        # show -CustomerName only when editing or adding a new customer:
        [Dynamic({$PSBoundParameters['Action'] -match '(Edit|New)'})]
        [string]
        $CustomerName,
        
        # show -Test only once (any) -Action value was submitted:
        [Dynamic({$PSBoundParameters.ContainsKey('Action')} )]
        [switch]
        $Test,
        
        # show -Coffee only before 11 a.m.
        [Dynamic({(Get-Date).Hour -lt 11})]
        [switch]
        $Coffee,
        
        # show -Lunch only at 11 a.m. or later
        [Dynamic({(Get-Date).Hour -ge 11})]
        [switch]
        $Lunch,
        
        # show -Mount only when -Path refers to a local path (and not a UNC path)
        [string]
        $Path,
        
        [Dynamic({$PSBoundParameters['Path'] -match '^[a-z]:'})]
        [switch]
        $Mount
        
    )
}

# turn definition into function with dynamic parameters
$definition = $parameter | Get-PsoDynamicParameterDefinition -FunctionName Start-Test

# copy function definition to clipboard
$definition | Set-ClipBoard

# paste it into the PowerShell editor of your choice, and run it to
# test dynamic parameter behavior. 
# Then, add the script logic you need to the begin, process, and/or end blocks.
```

In short, the scriptblock with the parameter definitions in `$parameter` gets fed into `Get-PsoDynamicParameterDefinition`. This automatically triggers the import of the module **DynamicParam** so by the time your scriptblock is processed by `Get-PsoDynamicParameterDefinition`, the attribute `[Dynamic()]` is also defined.

You get back the full PowerShell function code that is then copied to your clipboard. From there, paste it to your PowerShell editor of choice, and now you fully understand why dynamic parameters are so hard to use because without the help of your friends `[Dynamic()]` and `Get-PsoDynamicParameterDefinition`, you would have had to come up with all of that sophisticated .NET coding below yourself:

```powershell
function Start-Test
{
    # MUST be an advanced function so make sure you add [CmdletBinding()] just to be sure:
    [CmdletBinding()]
    param
    (
        [ValidateSet('New','Edit','Delete')]
        [string]
        $Action,

        [string]
        $Path
    )

    dynamicparam
    {
        # create container for all dynamically created parameters:
        $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()


        #region Start Parameter -Id ####
        if ($PSBoundParameters['Action'] -match '(Edit|Delete)') {
        # create container storing all attributes for parameter -Id
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Define attribute [Parameter()]:
        $attrib = [Parameter]::new()
        $attrib.Mandatory=$true
        $attributeCollection.Add($attrib)

        # compose dynamic parameter:
        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Id',[Guid],$attributeCollection)

        # add parameter to parameter collection:
        $paramDictionary.Add('Id',$dynParam)
        }
        #endregion End Parameter -Id ####


        #region Start Parameter -CustomerName ####
        if ($PSBoundParameters['Action'] -match '(Edit|New)') {
        # create container storing all attributes for parameter -CustomerName
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Define attribute [Parameter()]:
        $attrib = [Parameter]::new()
        $attributeCollection.Add($attrib)

        # compose dynamic parameter:
        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new('CustomerName',[string],$attributeCollection)

        # add parameter to parameter collection:
        $paramDictionary.Add('CustomerName',$dynParam)
        }
        #endregion End Parameter -CustomerName ####


        #region Start Parameter -Test ####
        if ($PSBoundParameters.ContainsKey('Action')) {
        # create container storing all attributes for parameter -Test
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Define attribute [Parameter()]:
        $attrib = [Parameter]::new()
        $attributeCollection.Add($attrib)

        # compose dynamic parameter:
        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Test',[switch],$attributeCollection)

        # add parameter to parameter collection:
        $paramDictionary.Add('Test',$dynParam)
        }
        #endregion End Parameter -Test ####


        #region Start Parameter -Coffee ####
        if ((Get-Date).Hour -lt 11) {
        # create container storing all attributes for parameter -Coffee
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Define attribute [Parameter()]:
        $attrib = [Parameter]::new()
        $attributeCollection.Add($attrib)

        # compose dynamic parameter:
        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Coffee',[switch],$attributeCollection)

        # add parameter to parameter collection:
        $paramDictionary.Add('Coffee',$dynParam)
        }
        #endregion End Parameter -Coffee ####


        #region Start Parameter -Lunch ####
        if ((Get-Date).Hour -ge 11) {
        # create container storing all attributes for parameter -Lunch
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Define attribute [Parameter()]:
        $attrib = [Parameter]::new()
        $attributeCollection.Add($attrib)

        # compose dynamic parameter:
        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Lunch',[switch],$attributeCollection)

        # add parameter to parameter collection:
        $paramDictionary.Add('Lunch',$dynParam)
        }
        #endregion End Parameter -Lunch ####


        #region Start Parameter -Mount ####
        if ($PSBoundParameters['Path'] -match '^[a-z]:') {
        # create container storing all attributes for parameter -Mount
        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Define attribute [Parameter()]:
        $attrib = [Parameter]::new()
        $attributeCollection.Add($attrib)

        # compose dynamic parameter:
        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new('Mount',[switch],$attributeCollection)

        # add parameter to parameter collection:
        $paramDictionary.Add('Mount',$dynParam)
        }
        #endregion End Parameter -Mount ####


        # return dynamic parameter collection:
        $paramDictionary
    }
    
    begin
    {
        
        #region initialize variables for dynamic parameters

        if($PSBoundParameters.ContainsKey('Id')) { $Id = $PSBoundParameters['Id'] }
        else { $Id = $null}

        if($PSBoundParameters.ContainsKey('CustomerName')) { $CustomerName = $PSBoundParameters['CustomerName'] }
        else { $CustomerName = $null}

        if($PSBoundParameters.ContainsKey('Test')) { $Test = $PSBoundParameters['Test'] }
        else { $Test = $null}

        if($PSBoundParameters.ContainsKey('Coffee')) { $Coffee = $PSBoundParameters['Coffee'] }
        else { $Coffee = $null}

        if($PSBoundParameters.ContainsKey('Lunch')) { $Lunch = $PSBoundParameters['Lunch'] }
        else { $Lunch = $null}

        if($PSBoundParameters.ContainsKey('Mount')) { $Mount = $PSBoundParameters['Mount'] }
        else { $Mount = $null}
        #endregion initialize variables for dynamic parameters

        # place your own code that executes before pipeline processing starts
    }
 
    process
    {
        #region update variables for pipeline-aware parameters:
        #endregion update variables for pipeline-aware parameters
        
        #region output pipeline-aware parameters for diagnostic purposes:
        [PSCustomObject]@{
            ParameterSetName = $PSCmdlet.ParameterSetName
        } | Format-List

        #endregion output pipeline-aware parameters for diagnostic purposes

        # place your own code that executes for each incoming pipeline object
    }

    end
    {
        #region output submitted parameters for diagnostic purposes:
        [PSCustomObject]@{
            Coffee       = $Coffee
            CustomerName = $CustomerName
            Id           = $Id
            Lunch        = $Lunch
            Mount        = $Mount
            Test         = $Test
        } | Format-List

        #endregion output submitted parameters for diagnostic purposes

        # place your own code that executes after pipeline processing has finished
    }
}

```
## Test Drive Dynamic Parameters

All *you* need to do is run the function, then play with your parameters. 

As you see, the newly created function `Start-Test` at first exposes only a few parameters. Once you add more information at *design time*, the appropriate extra parameters appear because they are *dynamically* added via the code in the *dynamicparam* block.

If any of the parameters won't behave the way you need it to yet, simply go back to your declarative `param()` block and fiddle with your `[Dynamic()]` declarations, then run the `param()` block through `Get-PsoDynamicParameterDefinition` again, and continue testing.


## Technical Backgrounds

When you look at the result code, you can now better understand how PowerShell implements dynamic parameters. Here are the key facts you need to know:

* Dynamic parameters are supported only for *Advanced Functions* so always make sure you add the attribute `[CmdletBinding()]` to ensure you create an *advanced* function and not a *simple* function.
* Dynamic parameters are programmatically created in a *dynamicparam* section that must follow your static parameters in their `param()` block. This section is a scriptblock that gets executed frequently - whenever PowerShell needs to determine which parameter to show, it runs this code. So make sure you are not using resource-intense code here.
* Whenever you use a *dynamicparam* section, you **must** place your own code into one of the blocks *begin*, *process*, and/or *end*. Code now cannot just be placed directly into a function body. These three blocks are important only for pipeline support. If your function does not need to support pipeline input, simply use the *end* block and remove the other two.
* Dynamic parameter values (the arguments the user assigned to them) aren't automatically exposed as variables. They only surface in `$PSBoundParameters[]`. The generated code automatically fixes this and assigns the appropriate variables.

As a final note, the module **dynpar** simply helps you compose the PowerShell function body you need to suuport your dynamic parameters. Once this code is generated, it runs on its own and has no dependencies to my module. 

## Conclusions

It is so much easier to create dynamic parameters with `[Dynamic()]` in a declarative style. 

So I keep my fingers crossed that one day, PowerShell natively supports this attribute and automatically translates the `param()` block accordingly so using dynamic parameters would really just be a matter of adding this attribute, shielding our eyes from the ugly complexity of *dynamicparam* code.

