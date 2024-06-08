#!/bin/bash
import boto3
import json
import subprocess
import sys

def get_aws_region(args):
    if '--AWSRegion' in args:
        idx = args.index('--AWSRegion')
        if idx + 1 < len(args):
            return args[idx + 1]
    return None

def read_json(file_path):
    with open(file_path, 'r') as file:
        return json.load(file)

def get_parameters(data, keys):
    return {key: data[key] for key in keys}

def aws_cfn_deploy(region, template_file, stack_name, parameters, tags, role_arn=None):
    client = boto3.client('cloudformation', region_name=region)
    parameters_list = [{'ParameterKey': k, 'ParameterValue': v} for k, v in parameters.items()]
    
    deploy_args = {
        'StackName': stack_name,
        'TemplateBody': open(template_file, 'r').read(),
        'Parameters': parameters_list,
        'Capabilities': ['CAPABILITY_NAMED_IAM'],
        'Tags': [{'Key': k, 'Value': v} for k, v in tags.items()]
    }
    
    if role_arn:
        deploy_args['RoleARN'] = role_arn

    response = client.create_stack(**deploy_args)
    print(response)

def main():
    args = sys.argv[1:]
    aws_region = get_aws_region(args)

    if not aws_region:
        print("AWS Region not provided. Use --AWSRegion to specify the region.")
        return

    role_arn = input("Please enter if you would like to use RoleArn to Launch stack, No/RoleArn: ")

    # Load parameters from JSON
    params = read_json('template_parameter_values.json')

    ml_account_params = get_parameters(params['MLAccountParameters'], [
        'AppRemoName', 'AppRepoBranch', 'CADomain', 'CADomainOwner', 'CARepoApp',
        'CARepoTextract', 'CARepoDPP', 'CrossAccountRoleArn', 'MLOpsProductsRepo',
        'SigningProfileNameML', 'SigningProfileVersionArnML'
    ])
    
    workload_account_params = get_parameters(params['WorkLoadAccountParameters'], [
        'ArtifactsBucketWL', 'DevOpsRoleArn', 'KMSKeyArnWL', 'RepoNameWL', 'ModelLifeCycle'
    ])
    
    tenant_params = get_parameters(params['TenantParameters'], [
        'ApplicationName', 'LifeCycle', 'PrivateSubnet1SSM', 'PrivateSubnet2SSM', 
        'SecurityGroupSSM', 'StackTags', 'TenantBucket', 'TenantBucketKMSKey',
        'TenantID', 'TenantName'
    ])

    stack_tags = tenant_params.pop('StackTags')

    parameter_overrides = {**ml_account_params, **workload_account_params, **tenant_params}

    # Deploy stacks
    templates_and_names = [
        ('template_textract.yaml', f"{tenant_params['TenantName']}{tenant_params['ApplicationName']}-TextractLSP"),
        ('template_doc_pre_processor.yaml', f"{tenant_params['TenantName']}{tenant_params['ApplicationName']}-DocPreProcessor"),
        ('template_app.yaml', f"{tenant_params['TenantName']}{tenant_params['ApplicationName']}-Application"),
    ]

    for template, stack_name in templates_and_names:
        aws_cfn_deploy(aws_region, template, stack_name, parameter_overrides, stack_tags, None if role_arn == 'No' else role_arn)

    # Get the output of the deployed application stack
    client = boto3.client('cloudformation', region_name=aws_region)
    response = client.describe_stacks(StackName=templates_and_names[2][1])
    app_pipeline_name = next(
        (output['OutputValue'] for output in response['Stacks'][0]['Outputs'] if output['OutputKey'] == 'AppPipelineName'), None
    )

    if app_pipeline_name:
        parameter_overrides.update({
            'AppPipelineName': app_pipeline_name,
            'ModelLifeCycle': workload_account_params['ModelLifeCycle'],
        })

        aws_cfn_deploy(
            aws_region,
            'template_orchestration_manager.yaml',
            f"{tenant_params['TenantName']}{tenant_params['ApplicationName']}-OrchestrationManager",
            parameter_overrides,
            stack_tags,
            None if role_arn == 'No' else role_arn
        )
    else:
        print("AppPipelineName not found in stack outputs.")

if __name__ == '__main__':
    main()
