#!/bin/bash
set -eux

while [ $# -gt 0 ]; do
    case "$1" in
    --AWSRegion)
        shift
        AWSRegion="$1"
        ;;
    esac
    shift
done

# Assumed Role prompt
echo "Plese enter if you would like to use RoleArn to Launch stack, No/RoleArn"
read RoleArn

# Reading Parameters from domain_template_parameter_values.json
# ML Account Parameters
AppRemoName=$(jq -r '.MLAccountParameters.AppRemoName' template_parameter_values.json)
AppRepoBranch=$(jq -r '.MLAccountParameters.AppRepoBranch' template_parameter_values.json)
CADomain=$(jq -r '.MLAccountParameters.CADomain' template_parameter_values.json)
CADomainOwner=$(jq -r '.MLAccountParameters.CADomainOwner' template_parameter_values.json)
CARepoApp=$(jq -r '.MLAccountParameters.CARepoApp' template_parameter_values.json)
CARepoTextract=$(jq -r '.MLAccountParameters.CARepoTextract' template_parameter_values.json)
CARepoDPP=$(jq -r '.MLAccountParameters.CARepoDPP' template_parameter_values.json)
CrossAccountRoleArn=$(jq -r '.MLAccountParameters.CrossAccountRoleArn' template_parameter_values.json)
MLOpsProductsRepo=$(jq -r '.MLAccountParameters.MLOpsProductsRepo' template_parameter_values.json)
SigningProfileNameML=$(jq -r '.MLAccountParameters.SigningProfileNameML' template_parameter_values.json)
SigningProfileVersionArnML=$(jq -r '.MLAccountParameters.SigningProfileVersionArnML' template_parameter_values.json)
# WorkLoad Account Parameters
ArtifactsBucketWL=$(jq -r '.WorkLoadAccountParameters.ArtifactsBucketWL' template_parameter_values.json)
DevOpsRoleArn=$(jq -r '.WorkLoadAccountParameters.DevOpsRoleArn' template_parameter_values.json)
KMSKeyArnWL=$(jq -r '.WorkLoadAccountParameters.KMSKeyArnWL' template_parameter_values.json)
RepoNameWL=$(jq -r '.WorkLoadAccountParameters.RepoNameWL' template_parameter_values.json)
ModelLifeCycle=$(jq -r '.WorkLoadAccountParameters.ModelLifeCycle' template_parameter_values.json)
# Tenant Parameters
ApplicationName=$(jq -r '.TenantParameters.ApplicationName' template_parameter_values.json)
LifeCycle=$(jq -r '.TenantParameters.LifeCycle' template_parameter_values.json)
PrivateSubnet1SSM=$(jq -r '.TenantParameters.PrivateSubnet1SSM' template_parameter_values.json)
PrivateSubnet2SSM=$(jq -r '.TenantParameters.PrivateSubnet2SSM' template_parameter_values.json)
SecurityGroupSSM=$(jq -r '.TenantParameters.SecurityGroupSSM' template_parameter_values.json)
StackTags=$(jq -r '.TenantParameters.StackTags' template_parameter_values.json)
TenantBucket=$(jq -r '.TenantParameters.TenantBucket' template_parameter_values.json)
TenantBucketKMSKey=$(jq -r '.TenantParameters.TenantBucketKMSKey' template_parameter_values.json)
TenantID=$(jq -r '.TenantParameters.TenantID' template_parameter_values.json)
TenantName=$(jq -r '.TenantParameters.TenantName' template_parameter_values.json)

# Defining cfn deploy function
function aws_cfn_deploy {
    if [ "$RoleArn" = "No" ]; then
        aws cloudformation deploy \
        --region $AWSRegion \
        --capabilities CAPABILITY_NAMED_IAM \
        --template-file $1 \
        --stack-name $2 \
        --parameter-overrides $3 \
        --tags $StackTags
    else
        aws cloudformation deploy \
        --region $AWSRegion \
        --role-arn $RoleArn \
        --capabilities CAPABILITY_NAMED_IAM \
        --template-file $1 \
        --stack-name $2 \
        --parameter-overrides $3 \
        --tags $StackTags
    fi
}

textractTemplate=template_textract.yaml
textractStackName=${TenantName}${ApplicationName}-TextractLSP
documentPreProcessorTemplate=template_doc_pre_processor.yaml
documentPreProcessorStackName=${TenantName}${ApplicationName}-DocPreProcessor
applicationTemplate=template_app.yaml
applicationStackName=${TenantName}${ApplicationName}-Application
orcManagerTemplate=template_orchestration_manager.yaml
orcManagerStackName=${TenantName}${ApplicationName}-OrchestrationManager

ParameterOverrides="ApplicationName=${ApplicationName} \
AppRemoName=${AppRemoName} \
AppRepoBranch=${AppRepoBranch} \
ArtifactsBucketWL=${ArtifactsBucketWL} \
CADomain=${CADomain} \
CADomainOwner=${CADomainOwner} \
CARepoDPP=${CARepoDPP} \
CARepoApp=${CARepoApp} \
CARepoTextract=${CARepoTextract} \
CrossAccountRoleArn=${CrossAccountRoleArn} \
DevOpsRoleArn=${DevOpsRoleArn} \
KMSKeyArnWL=${KMSKeyArnWL} \
LifeCycle=${LifeCycle} \
MLOpsProductsRepo=${MLOpsProductsRepo} \
PrivateSubnet1SSM=${PrivateSubnet1SSM} \
PrivateSubnet2SSM=${PrivateSubnet2SSM} \
RepoNameWL=${RepoNameWL} \
SecurityGroupSSM=${SecurityGroupSSM} \
SigningProfileNameML=${SigningProfileNameML} \
SigningProfileVersionArnML=${SigningProfileVersionArnML} \
StackTags=${StackTags} \
TenantID=${TenantID} \
TenantName=${TenantName} \
TenantBucket=${TenantBucket} \
TenantBucketKMSKey=${TenantBucketKMSKey}"

# ToDo - StackTags=${StackTags} \

aws_cfn_deploy "${textractTemplate}" "${textractStackName}" "${ParameterOverrides}"

aws_cfn_deploy "${documentPreProcessorTemplate}" "${documentPreProcessorStackName}" "${ParameterOverrides}"

aws_cfn_deploy "${applicationTemplate}" "${applicationStackName}" "${ParameterOverrides}"

appPipelineName=$(aws cloudformation describe-stacks \
--region ${AWSRegion} \
--stack-name ${applicationStackName} \
--query 'Stacks[0].Outputs[?OutputKey==`AppPipelineName`].OutputValue' \
--output text)

ParameterOverrides="=${TenantName} \
ApplicationName=${ApplicationName} \
AppRemoName=${AppRemoName} \
AppPipelineName=${appPipelineName} \
ModelLifeCycle=${ModelLifeCycle} \
CrossAccountRoleArn=${CrossAccountRoleArn}"
aws_cfn_deploy "${orcManagerTemplate}" "${orcManagerStackName}" "${ParameterOverrides}"