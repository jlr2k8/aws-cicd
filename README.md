# [DRAFT] aws-cicd
Collection of AWS resources for CICD pipeline deployment and automation.

* Under the `cfn-templates` directory, the CloudFormation template `create-cicd-pipeline.yaml` takes a project name parameter, which matches and references the project directory within the `projects/` directory.
  * Example to create the pipeline for `web-stack-dev`:
    * `aws cloudformation create-stack --stack-name web-stack-dev-infra --template-url https://${AWS_S3_BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/cfn-templates/create-cicd-pipeline.yaml --parameters ParameterKey=PipelineName,ParameterValue=web-stack-dev ParameterKey=S3RootBucket,ParameterValue=${AWS_S3_BUCKET_NAME} --profile {AWS_S3_PROFILE} --region ${AWS_REGION} --capabilities CAPABILITY_NAMED_IAM`.
* The directory `projects/` contains the project that create the downstream pipelines.
    * Using the example above, that would be: `projects/web-stack-dev`.
* General CloudFormation templates are stored in other subdirectories. These are designed to be modular, re-used, and nested in multiple projects:
  * `cfn-templates/ec2/`
  * `cfn-templates/s3/`

* Bash scripts, for testing pipelines in development & cleanup for projects, are stored in `bash-scripts/`.
  * Pipeline cleanup script. Deleting a CloudFormation stack doesn't always clean up the whole project and the resources it created! The main bash script to help with that is:
    * `bash-scripts/cleanup-cicd-pipeline.sh` cleans up a project by passing in these parameters:
      * `-p` Project Name
      * `-s` Parent CloudFormation stack name
      * `-a` AWS Account ID
      * `-r` AWS S3 bucket region
      * Example: `./bash-scripts/cleanup-cicd-pipeline.sh  -p 'web-stack-dev' -s 'web-stack-dev-infra' -a "${ACCOUNT_ID}" -r "${REGION}"`
    * For each project, the `bash-scripts/` subdirectory `cleanup-cicd-pipeline.d/` contains scripts named after the project.
    * In the above example, that would be a bash file in `cleanup-cicd-pipeline.d/web-stack-dev.sh`.
    * If a specific project and its resources need to be wiped out, this sub-script is sourced from the `cleanup-cicd-pipeline.sh` script to cleanup the specific downstream pipelines and resources.
  * S3 project sync script. This is run on a cronjob (but can be run manually). Since CodeCommit is [deprecated](https://aws.amazon.com/blogs/devops/how-to-migrate-your-aws-codecommit-repository-to-another-git-provider/), and some of my projects are on a privately hosted git server, this bash script syncs all of the CloudFormation files to an S3 bucket. When updated files in the S3 bucket are polled by CodeBuild, the downstream pipelines are updated. If polling is disabled in the CloudFormation script, the `s3 sync` `--size-only` flag can be used to trigger CodeBuild.
    * Example of sync (bash): `aws s3 sync aws-cicd/ ${S3_BUCKET_URL} --profile ${S3_USER_PROFILE} --size-only`
    * These projects should be zipped to create artifacts.
      * Example (but see `bash-scripts/sync-projects.sh`): 
      ```
      cd ${PROJECT_REPO_DIR}/
      
      for d in ${PROJECT_REPO_DIR}/*; do
        if [[ -d "${d}" ]]; then
          echo "$(date) :: Zipping project directory, ${d}, to ${d}.zip..."
          echo
      
          zip "${d}.zip" "${d}"
        fi
      done
              
      aws s3 sync aws-cicd/ ${S3_BUCKET_URL} --profile ${S3_USER_PROFILE} --size-only
      ```