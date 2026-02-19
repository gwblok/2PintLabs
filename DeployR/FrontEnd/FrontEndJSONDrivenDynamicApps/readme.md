# JSON Driven Dynamic Apps FrontEnd

> [!IMPORTANT]
> This is my personal GitHub, while I work for 2Pint Software, this is not a supported frontend, anything you find here you can borrow, but it's use at your own risk, and self-supported.

## Files

- Frontend PowerShell Script
- JSON Config File
- Logo File (png)

All files need to be in the same folder so they can reference each other when running.

## JSON File

The JSON file has several sections, you'll want to update each for your environment.  If you don't plan to use specific parts of the Frontend, just clear out the options for it in the JSON, but don't delete the main section.  

## Frontend

OK, you can look at the docs in the FrontEndJSONDriven folder to learn most things, I'm just going to cover the part that makes this different.

This one was purposely adjusted for DeployR environments.  I didn't remove the ConfigMgr Code, which I will probably do in the future, I just updated to allow the Software page to dynamically pull a list of software from the DeployR server based on a Tag you set on the application.

In the JSON File, you'll need to set these to items:
  "SoftwareFromDeployR": "True",
  "SoftwareFromDeployRTag": "FrontEnd",

The SoftwareFromDeployRTag will be whatever Tag you set on the apps in DeployR Dashboard
![DFE01](./media/DFE01.png)

Those are some of the apps I have in DeployR that are tagged with "FrontEnd" so when the Front End is run in the Task Sequence, it will query DeployR and return those apps.

![DFE02](./media/DFE02.png)

Once you make a selection, it will create the variables when the Frontend closes:

![DFE03](./media/DFE03.png)

The Magic is that variable: TSENVLIST:APPLICATIONS, that will be the variable that gets pulled into the "Install Multiple Apps" step later.

![DFE04](./media/DFE04.png)

The Frontend you just call the PowerShell script: (After you made a content item with the PowerShell Script, Logo & JSON file)
![DFE05](./media/DFE05.png)

Then later in the Task Sequence you call the step to install the apps:

![DFE06](./media/DFE06.png)

There you have it.
Now in the Task Sequence:

![DFE07](./media/DFE07.png)



If you have questions, post them on Reddit in the 2Pint DeployR area, or find me on Discord WinAdmins
