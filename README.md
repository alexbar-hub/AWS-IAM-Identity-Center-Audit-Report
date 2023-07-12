# AWS IAM Identity Center Audit Report

## Table of Contents
- [AWS IAM Identity Center Audit Report](#aws-iam-identity-center-audit-report)
  - [Table of Contents](#table-of-contents)
  - [Intro](#intro)
  - [What it does](#what-it-does)
  - [How it works](#how-it-works)
  - [Usage](#usage)
  - [Credits](#credits)

## Intro
Welcome to the AWS-IAM-Identity-Center-Audit-Report project! Have you been wondering how you could get a detailed view of all users, groups, AWS accounts, permission sets and all the associations among them in IAM Identity Center? Well, this is it! This bash script will scan your configuration and generate a perfectly readable output in csv format. 

This helps a lot with audits and to keep the situation under control, especially if you're managing large environments.

## What it does
This bash script creates a full reports of all users, groups, permission sets, and AWS accounts in AWS Identity Center and all their association.

The output is always saved locally in the working directory. If possible it will be also uploaded into a pre-defined bucket, or into a custom bucket.

IAM users are not covered.

## How it works
This bash script is split in 3 main blocks:
* **AWS accounts - Permission Sets - Groups/Users**: this block contains the following fields: 
  * AccountName
  * AccountID
  * PermissionSetArn
  * PermissionSetName
  * User/Group Id
  * PrincipalType
  * User/Group Name
* **Groups - Users per group**: this block contains the following fields: 
  * GroupId
  * GroupDisplayName
  * GroupDescription
  * UserId
  * UserName
  * UserDisplayName
* **Permission Sets - All policies**: this block contains the following fields:
  * PermissionSetArn
  * PermissionSetName
  * PermissionSetManagedPolicies
  * PermissionSetCustomerManagedPolicies
  * PermissionSetInlinePolicy

Each group generates a dedicated csv file. The third block also checks if a permission set has inline policy configured and, if it does, it downloads it in the InlinePolicies folder in json format for better readablity.

**Note**: in order to get a proper output in the csv files, avoid the usage of commas in the `GroupDescription` field. 

## Usage
Prerequisite: an aws cli active session.

The script needs the SSO Instance arn as input parameter, and it can be executed as it follows::
* `./AWS-IAM-Identity-Center-Audit-Report.sh arn:aws:sso:::instance/ssoins-xxxxxxxxxxxxx`: this will create a local output and also upload the output in the predefined S3 bucket specified in the `S3BUCKET` variable if you can write to it (a write check is performed). Shell output example:

```bash
mybox:~ alex$ ./AWS-IAM-Identity-Center-Audit-Report.sh arn:aws:sso:::instance/ssoins-xxxxxxxxx
You did not specify a bucket in S3, the output will be saved in the pre-defined bucket MY-PREDEFINED-BUCKET , continuing...
Generating a list of AWS accounts - Groups/Users - Permission Sets...
The AWS accounts - Groups/Users - Permission Sets report is ready.
Generating a list of Groups - Users per group...
The users/groups report is ready.
Generating a list of Permission Sets - All policies...
The Permission Sets - All policies report is ready.
Uploading the output files into the MY-PREDEFINED-BUCKET bucket...
[...]
The output file has been created in your local working folder and also uploaded into the MY-PREDEFINED-BUCKET bucket.
The process is now complete.
```

*  `./AWS-IAM-Identity-Center-Audit-Report.sh arn:aws:sso:::instance/ssoins-xxxxxxxxxxxxx A-Bucket_Name`: this will create a local output and also upload the output in a custoe S3 bucket, the one specified in the `S3BUCKET` variable will be ignored, if you can write to it (a write check is performed). Shell output example:

```bash
mybox:~ alex$ ./AWS-IAM-Identity-Center-Audit-Report.sh arn:aws:sso:::instance/ssoins-xxxxxxxxx A-CUSTOM-BUCKET
You specified a non-predefined bucket, your output will be saved in the A-CUSTOM-BUCKET S3 bucket, if it exists and if you can access it, checking....
upload: ./s3writetest to s3://A-CUSTOM-BUCKET/s3writetest
The bucket A-CUSTOM-BUCKET does exist and you have write access to it, your content will be saved also in there.
delete: s3://A-CUSTOM-BUCKET/s3writetest
Generating a list of AWS accounts - Groups/Users - Permission Sets...
The AWS accounts - Groups/Users - Permission Sets report is ready.
Generating a list of Groups - Users per group...
The users/groups report is ready.
Generating a list of Permission Sets - All policies...
The Permission Sets - All policies report is ready.
Uploading the output files into the A-CUSTOM-BUCKET bucket...
[...]
The output file has been created in your local working folder and also uploaded into the A-CUSTOM-BUCKET bucket.
The process is now complete.
```

## Credits

[Chance Zibolski](https://gist.github.com/chancez) - Original author of the first block, available [here](https://gist.github.com/chancez/ddf9ba826d7a48d121eec0fbf409b62d#file-permission-sets-export-sh).