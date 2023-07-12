#!/bin/bash

# set -e
# set -o pipefail

####################################################
# Variables                                        #
####################################################
now=$(date +"%Y%m%d-%H%M%S")
PERMISSIONSETS_AWS_CSV="AWSAccounts-PermissionSets-Group"
USERS_GROUPS_CSV="Users-Groups"
PERMISSIONSETS_DETAILS_CSV="PermissionSets-Details"
REPORT="$now"-Report
INLINE_POLICIES="$REPORT"/"$now"-InlinePolicies
S3BUCKET="<YOUR S# BUCKET NAME HERE>"

####################################################
# Pre-Execution checks                             #
####################################################

if [ $# -lt 1 ]; then
    echo "Usage: $0 sso-instance-arn"
    exit 1
fi

if [ $# -lt 2 ]; then
    echo "You didn't specify a bucket in S3, the output will be saved in the pre-defined bucket" "$S3BUCKET" ", checking if you can write to it..."
    touch s3writetest
    aws s3 cp s3writetest s3://"$S3BUCKET"/s3writetest
    if [ "$?" -eq 0 ]; then
      echo "You can write to the pre-defined bucket" "$S3BUCKET" ", continuing..."
      rm s3writetest
      aws s3 rm s3://"$S3BUCKET"/s3writetest
    else
      echo "You cannot write to the pre-defined bucket" "$S3BUCKET" ", your content will be saved only in your working directory."
      rm s3writetest
      S3BUCKET="Not Available."
      echo "Continuing..."
      sleep 5
    fi
else
    echo "You specified a non-predefined bucket, your output will be saved in the" "$2" "S3 bucket, if it exists and if you can access it, checking...."
    touch s3writetest
    aws s3 cp s3writetest s3://"$2"/s3writetest
    if [ "$?" -eq 0 ]; then
      echo "The bucket" "$2" "does exist and you have write access to it, your content will be saved also in there."
      aws s3 rm s3://"$2"/s3writetest
      rm s3writetest
      S3BUCKET="$2"
    else
        echo "The specified bucket" "$2" "does not exist or you cannot access it, your content will be saved only in your working directory."
        rm s3writetest
        S3BUCKET="Not Available."
        echo "Continuing..."
        sleep 5
    fi
fi

SSO_INSTANCE_ARN="$1"
export SSO_INSTANCE_ARN

IDENTITY_STORE_ID="$(\
    aws sso-admin list-instances --output json \
    | jq -rc '.Instances | map(select(.InstanceArn==env["SSO_INSTANCE_ARN"])) | .[0].IdentityStoreId' \
)"
export IDENTITY_STORE_ID

mkdir -p "$INLINE_POLICIES"

####################################################
# AWS accounts - Permission Sets - Groups/Users    #
####################################################
echo "Generating a list of AWS accounts - Groups/Users - Permission Sets..."

echo "AccountName,AccountID,PermissionSetArn,PermissionSetName,User/Group Id,PrincipalType,User/Group Name" > "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".csv

IFS=$'\n' read -r -d '' -a PERMISSION_SETS < <( aws sso-admin list-permission-sets --instance-arn "$SSO_INSTANCE_ARN" --output json | jq -rc '.PermissionSets[]' && printf '\0' )

RESULTS=()
for PERMISSION_SET_ARN in "${PERMISSION_SETS[@]}"; do
    export PERMISSION_SET_ARN
    ACCOUNTS_JSON="$(\
        aws sso-admin list-accounts-for-provisioned-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json \
    )"
    IFS=$'\n' read -r -d '' -a ACCOUNT_IDS < <( echo "$ACCOUNTS_JSON" | jq -rc '.AccountIds[]' )

    PERMISSION_SET_NAME="$(aws sso-admin describe-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json \
        | jq -rc '.PermissionSet.Name'
    )"
    export PERMISSION_SET_NAME

    for ACCOUNT_ID in "${ACCOUNT_IDS[@]}"; do
        ACCOUNT_NAME="$(aws organizations describe-account --account-id "$ACCOUNT_ID" --output json | jq -rc '.Account.Name')"
        export ACCOUNT_ID
        export ACCOUNT_NAME

        ASSIGNMENTS_JSON="$(
            aws sso-admin list-account-assignments \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --permission-set-arn "$PERMISSION_SET_ARN" \
            --account-id "$ACCOUNT_ID" \
            --output json \
        )"

        IFS=$'\n' read -r -d '' -a ASSIGNMENT_OBJS < <( echo "$ASSIGNMENTS_JSON" | jq -rc '.AccountAssignments[]' )
        for ASSIGNMENT_OBJ in "${ASSIGNMENT_OBJS[@]}"; do
            PRINCIPAL_ID="$(echo "$ASSIGNMENT_OBJ" | jq -rc '.PrincipalId')"
            PRINCIPAL_TYPE="$(echo "$ASSIGNMENT_OBJ" | jq -rc '.PrincipalType')"
            GROUP_OBJ='{}'
            USER_OBJ='{}'
            export PRINCIPAL_ID PRINCIPAL_TYPE GROUP_OBJ USER_OBJ
            if [ "$PRINCIPAL_TYPE" == "GROUP" ]; then
                GROUP_OBJ="$(\
                    aws identitystore describe-group \
                        --identity-store-id "$IDENTITY_STORE_ID" \
                        --group-id "$PRINCIPAL_ID" \
                        --output json \
                    | jq -rc '{GroupName: .DisplayName}' \
                )"
            elif [ "$PRINCIPAL_TYPE" == "USER" ]; then
                USER_OBJ="$(\
                    aws identitystore describe-user \
                        --identity-store-id "$IDENTITY_STORE_ID" \
                        --user-id "$PRINCIPAL_ID" \
                        --output json \
                    | jq -rc '{UserName: .UserName}' \
                )"
            fi
            RESULT="$(jq -nrc \
                --argjson user "$USER_OBJ" \
                --argjson group "$GROUP_OBJ" \
            '{
                AccountName: env["ACCOUNT_NAME"],
                AccountID: env["ACCOUNT_ID"],
                PermissionSetArn: env["PERMISSION_SET_ARN"],
                PermissionSetName: env["PERMISSION_SET_NAME"],
                PrincipalID: env["PRINCIPAL_ID"],
                PrincipalType: env["PRINCIPAL_TYPE"],
#                TargetType: "AWS_ACCOUNT",
#                SSOInstanceArn: env["SSO_INSTANCE_ARN"],
            } * $user * $group')"
            RESULTS+=( "$RESULT" )
            echo "$RESULT" >> "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json
        done
    done
done
# Delete empty lines
cat "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json | grep "\S" > "$REPORT"/temp && mv "$REPORT"/temp "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json
# Add comma at the end of each line but the last one
sed '$!s/$/,/' "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json > "$REPORT"/temp && mv "$REPORT"/temp "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json
# Add [ before the first line
echo '[' | cat - "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json > "$REPORT"/temp && mv "$REPORT"/temp "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json
# Add ] at the end of the file
echo "]" >> "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json
# Convert the file and prepare csv
cat "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json | jq -r '.[]| join(",")' >> "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".csv && rm "$REPORT"/"$now"-"$PERMISSIONSETS_AWS_CSV".json

echo "The AWS accounts - Groups/Users - Permission Sets report is ready."

####################################################
# Groups - Users per group                         #
####################################################
echo "Generating a list of Groups - Users per group..."

echo "GroupId,GroupDisplayName,GroupDescription,UserId,UserName,UserDisplayName" > "$REPORT"/"$now"-"$USERS_GROUPS_CSV".csv

IFS=$'\n' read -r -d '' -a GROUP_IDS < <( aws identitystore list-groups --identity-store-id "$IDENTITY_STORE_ID" --query 'Groups[*].[GroupId]' --output text )

# Get Group display name and group description from group id
for GROUP_ID in "${GROUP_IDS[@]}"; do
    export GROUP_ID
    GROUPS_JSON="$(\
        aws identitystore describe-group \
        --identity-store-id "$IDENTITY_STORE_ID" \
        --group-id "$GROUP_ID" \
        --output json \
    )"
    IFS=$'\n' read -r -d '' -a GROUP_DISPLAY_NAME < <( echo "$GROUPS_JSON" | jq -r '.DisplayName' )
    export GROUP_DISPLAY_NAME
    IFS=$'\n' read -r -d '' -a GROUP_DESCRIPTION < <( echo "$GROUPS_JSON" | jq -r '.Description' )
    export GROUP_DESCRIPTION

    IFS=$'\n' read -r -d '' -a MEMBER_IDS < <( aws identitystore list-group-memberships --identity-store-id "$IDENTITY_STORE_ID" --group-id "$GROUP_ID" --query 'GroupMemberships[*].[MemberId]' --output text )

    # Get UserId, UserName, DisplayName
    for MEMBER_ID in "${MEMBER_IDS[@]}"; do
        export MEMBER_ID
        MEMBER_JSON="$(\
        aws identitystore describe-user \
        --identity-store-id "$IDENTITY_STORE_ID" \
        --user-id "$MEMBER_ID" \
        --output json \
    )"
    IFS=$'\n' read -r -d '' -a USER_USER_NAME < <( echo "$MEMBER_JSON" | jq -r '.UserName' )
    export USER_USER_NAME

    IFS=$'\n' read -r -d '' -a USER_DISPLAY_NAME < <( echo "$MEMBER_JSON" | jq -r '.DisplayName' )
    export USER_DISPLAY_NAME

    RESULT=$GROUP_ID,$GROUP_DISPLAY_NAME,$GROUP_DESCRIPTION,$MEMBER_ID,$USER_USER_NAME,$USER_DISPLAY_NAME
    echo "$RESULT" >> "$REPORT"/"$now"-"$USERS_GROUPS_CSV".csv
    done
done

echo "The users/groups report is ready."

####################################################
# Permission Sets - All policies                   #
####################################################
echo "Generating a list of Permission Sets - All policies..."

echo "PermissionSetArn,PermissionSetName,PermissionSetManagedPolicies,PermissionSetCustomerManagedPolicies,PermissionSetInlinePolicy" > "$REPORT"/"$now"-"$PERMISSIONSETS_DETAILS_CSV".csv

IFS=$'\n' read -r -d '' -a PERMISSION_SETS < <( aws sso-admin list-permission-sets --instance-arn "$SSO_INSTANCE_ARN" --output json | jq -rc '.PermissionSets[]' && printf '\0' )

RESULTS=()
for PERMISSION_SET_ARN in "${PERMISSION_SETS[@]}"; do
    export PERMISSION_SET_ARN
    ACCOUNTS_JSON="$(\
        aws sso-admin list-accounts-for-provisioned-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json \
    )"

    PERMISSION_SET_NAME="$(aws sso-admin describe-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json \
        | jq -rc '.PermissionSet.Name'
    )"
    export PERMISSION_SET_NAME

    PERMISSION_SET_MANAGED_POLICIES="$(aws sso-admin list-managed-policies-in-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json | jq -rc '[.AttachedManagedPolicies | .[] | .Name]' | sed 's/,/;/g'
    )"
    export PERMISSION_SET_MANAGED_POLICIES

    PERMISSION_SET_CUSTOMER_MANAGED_POLICIES="$(aws sso-admin list-customer-managed-policy-references-in-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json | jq -rc '[.CustomerManagedPolicyReferences | .[] | .Name]' | sed 's/,/;/g'
    )"
    export PERMISSION_SET_CUSTOMER_MANAGED_POLICIES

    PERMISSION_SET_INLINE_POLICY="$(aws sso-admin get-inline-policy-for-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --permission-set-arn "$PERMISSION_SET_ARN" \
        --output json | jq -rc .[]
    )"
    export PERMISSION_SET_INLINE_POLICY
    if [ -z "$PERMISSION_SET_INLINE_POLICY" ]
    then 
        PERMISSION_SET_INLINE_POLICY_SET="Not Set"
    else
        PERMISSION_SET_INLINE_POLICY_SET="Set"
        echo "$PERMISSION_SET_INLINE_POLICY" > "$INLINE_POLICIES"/"$now"-"$PERMISSION_SET_NAME".json
    fi 

    RESULT=$PERMISSION_SET_ARN,$PERMISSION_SET_NAME,$PERMISSION_SET_MANAGED_POLICIES,$PERMISSION_SET_CUSTOMER_MANAGED_POLICIES,$PERMISSION_SET_INLINE_POLICY_SET
    echo "$RESULT" >> "$REPORT"/"$now"-"$PERMISSIONSETS_DETAILS_CSV".csv
done

echo "The Permission Sets - All policies report is ready."

if [ "$S3BUCKET" == "Not Available." ]; then
  echo "The output file has been created in your local working folder."
  echo "The process is now complete."
else
  echo "Uploading the output files into the" "$S3BUCKET" "bucket..."
  aws s3 cp "$REPORT" s3://"$S3BUCKET"/"$REPORT" --recursive
  echo "The output file has been created in your local working folder and also uploaded into the" "$S3BUCKET" "bucket."
  echo "The process is now complete."
fi