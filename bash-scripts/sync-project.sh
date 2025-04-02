#!/bin/bash

## Sync files from GitHub repo jlr2k8/aws-cicd to current privately hosted server, which generates the artifact zip
## files needed to upload to s3 bucket. This triggers CodeBuild if run manually and/or the projects'
## file sizes change.
##
## Params:
##  -p Project repository directory (this repo)
##  -s AWS S3 Bucket URL
##  -u AWS S3 User profile
##  -f remove "--size-only" flag from the "s3 sync" command to force the sync of files to s3
##  -h help
##

PROJECT_REPO_DIR=
AWS_S3_BUCKET_URL=
AWS_S3_PROFILE=
S3_SYNC_SIZE_ONLY="--size-only"
TMP_DIR="/tmp/aws-cicd-$(date +%Y%m%d%H%M%S)"

function showHelp() {
  echo 'Parameters
---------------------------------------------------------
  -p project repo directory (e.g. /usr/local/aws-cicd/)
  -s AWS S3 Bucket URL
  -u AWS Account ID
  -f remove "--size-only" flag from the "s3 sync" command to force the sync of files to s3
  -h help (show this help)
';

  return 0
}

while getopts ":p:s:u:fh" OPT; do
    case "${OPT}" in
        p)
            echo "Project repo directory: ${OPTARG}"
            PROJECT_REPO_DIR="${OPTARG}"
            ;;
        s)
            echo "AWS S3 bucket URL: ${OPTARG}"
            AWS_S3_BUCKET_URL="${OPTARG}"
            ;;
        u)
            echo "AWS S3 profile: ${OPTARG}"
            AWS_S3_PROFILE=${OPTARG}
            ;;
        f)
            echo "Forcing sync without '--size-only' flag"
            S3_SYNC_SIZE_ONLY=
            ;;
        h|*)
            showHelp
            ;;
    esac
done

which dos2unix > /dev/null

if [[ $? != 0 ]]; then
  echo "$(date) :: FATAL - dos2unix is not installed..."
  echo

  exit 1
fi

echo "$(date) :: copying the aws-cicd project to ${TMP_DIR} and running dos2unix on all files..."
echo

mkdir -p ${TMP_DIR} \
  && cd ${TMP_DIR} \
  && cp -rf ${PROJECT_REPO_DIR}/ ${TMP_DIR} \
  && find . -type f -exec dos2unix {} \;

cd ${PROJECT_REPO_DIR}/projects

for f in *.yaml *.yml; do
  if [[ -f "${f}" ]]; then
    echo "$(date) :: Zipping project yaml files, ${f}, to ${f}.zip..."
    echo

    zip "${f}.zip" "${f}"
  fi
done

echo "$(date) :: Syncing ${AWS_S3_BUCKET_URL} with profile ${AWS_S3_PROFILE}..."
echo

aws s3 sync ${TMP_DIR}/aws-cicd ${AWS_S3_BUCKET_URL} --profile ${AWS_S3_PROFILE} ${S3_SYNC_SIZE_ONLY} --exclude ".*" --exclude ".*/*"