# DeployR Custom Step Definitions

These are step definitions I've created in my lab, feel free to import them.
These steps require a content item created with the contents located in the StepDefinitions folder on GitHub: https://github.com/gwblok/2PintLabs/tree/main/DeployR/TSScripts/StepDefinitions

The step defintion(s), once imported, you'll want to go into them then update the content item to the one you created.

## Instructions to Import

### Download and Import Step Definition

- Download the Associated JSON file from this folder
- Use PowerShell 7 on the DeployR Server to load module and connect to DeployR service: [Docs](https://documentation.2pintsoftware.com/deployr/powershell-modules/scripting-for-deployr-server)
- Run the Import Command to import the json file you downloaded

```PowerShell
Import-DeployRStepDefinition -SourceFile "C:\Users\gary.blok\Downloads\753771ea-0a3b-4e34-9931-301e0971c3c3.json"
```

### Download and Create Content Item

Grab all the scripts (or the ones needed for the steps you're wanting to import) and create a DeployR content item.  

![Image01](.\media\stepdef01.png)

### Update Step to use the Content Item

Once you have the the step definition imported and createed the content item, you can set the content item with the scripts in the step definition.

![Image02](.\media\stepdef02.png)


You can read more on my blog: https://garytown.com/deployr-importing-custom-step-definitions

