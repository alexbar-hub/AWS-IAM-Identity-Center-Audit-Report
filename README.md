# AWS-IAM-Identity-Center-Audit-Report

## Table of Contents
- [What it does](#what-it-does)
- [How it works](#how-it-works)
- [Usage](#usage)
- [Credits](#credits)

## What it does
This script creates a full reports of all users, groups, permission sets, and AWS accounts in AWS Identity Center and all their correlations.

IAM users are not covered.

## How it works
This bash script is split in 3 main blocks:
* AWS accounts - Groups/Users - Permission Sets
    * it contains the following fields: 
        * AccountName
        * AccountID
        * PermissionSetArn
        * PermissionSetName
        * User/Group Id
        * PrincipalType
        * User/Group Name
* Groups - Users per group
    * it contains the following fields: 
        * GroupId
        * GroupDisplayName
        * GroupDescription
        * UserId
        * UserName
        * UserDisplayName
* Permission Sets - All policies
    * it contains the following fields: 
        * PermissionSetArn
        * PermissionSetName
        * PermissionSetManagedPolicies
        * PermissionSetCustomerManagedPolicies
        * PermissionSetInlinePolicy

Each group generates a dedicated csv file. The third block also checks if a permission set has inline policy set, if it does it downloads it in the InlinePolicies folder in json for better readablity.

**Note**: in order to get a proper output in the csv files, avoid the usage of commas in the `GroupDescription` field. 

## Usage
Prerequisite: and aws cli active session.

The script needs the SSO Instance arn as input parameter:

`./AWS-IAM-Identity-Center-Audit-Report.sh arn:aws:sso:::instance/ssoins-xxxxxxxxxxxxx` 


## Credits

[Chance Zibolski](https://gist.github.com/chancez) - Original author of the first block, available [here](https://gist.github.com/chancez/ddf9ba826d7a48d121eec0fbf409b62d#file-permission-sets-export-sh).