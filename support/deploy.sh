#! /bin/bash

SHA1=$1

# Deploy image to Docker Hub
docker push circleci/hello:$SHA1

# Create new Elastic Beanstalk version
EB_BUCKET=hello-bucket
DOCKERRUN_FILE=$SHA1-Dockerrun.aws.json
sed "s/<TAG>/$SHA1/" < Dockerrun.aws.json.template > $DOCKERRUN_FILE
aws s3 cp $DOCKERRUN_FILE s3://$EB_BUCKET/$DOCKERRUN_FILE
aws elasticbeanstalk create-application-version --application-name hello \
  --version-label $SHA1 --source-bundle S3Bucket=$EB_BUCKET,S3Key=$DOCKERRUN_FILE

# Update Elastic Beanstalk environment to new version
aws elasticbeanstalk update-environment --environment-name hello-env \
    --version-label $SHA1



#############################

AWS_ACCESS_KEY_ID=foo
AWS_SECRET_ACCESS_KEY=bar
APP_NAME=asr
ENV_NAME=asr-env
VERSION_LABEL=dev
ENV_DESCRIPTION=Environment for ASR Development server
REGION=ap-southeast-2

# TODO: check if it exists
aws elasticbeanstalk create-application --application-name "asr"  --description "ASR Staging" --region "ap-southeast-2"

# TODO: create version

# TODO: check if it exists
aws elasticbeanstalk create-environment \
    --application-name "$APP_NAME" --environment-name "$ENV_NAME" \
    --description "$ENV_DESCRIPTION" \
    --tier "Name=WebServer,Type=Standard,Version=1.0" \
    --solution-stack-name "64bit Amazon Linux 2014.03 v1.0.1 running Docker 1.0.0" \
    --version-label "$VERSION_LABEL"


          [--version-label <value>]
          [--template-name <value>]
          [--solution-stack-name <value>]
          [--option-settings <value>]
          [--options-to-remove <value>]

