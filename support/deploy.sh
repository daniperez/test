#! /bin/bash

######################################################################
#
# NOTE: The script looks very scaring but it's quite straightforward.
#       most of code is error control.
#
######################################################################
APP_LABEL="asr"
APP_DESCRIPTION="Amadeus Schedule Recovery"
# Version (e.g. staging, production) 
VERSION_LABEL="dev"
VERSION_DESCRIPTION="Staging environment for ASR"
ENV_LABEL="asr-env"
ENV_DESCRIPTION="Environment for ASR Development server"
REGION="ap-southeast-2"
STACK="64bit Amazon Linux 2014.03 v1.0.1 running Docker 1.0.0"
TIER="Name=WebServer,Type=Standard,Version=1.0"

function get_deploy_url {

    aws elasticbeanstalk describe-environments \
        --application-name "$APP_LABEL"        \
        --output=text                          \
        --region "$REGION" 2>&1                \
        |  grep ENVIRONMENT | grep -v "Termina" |  cut -f 3
}

function get_application_environment_bucket {

    aws elasticbeanstalk describe-application-versions \
        --version-labels "$VERSION_LABEL"              \
        --application-name "$APP_LABEL"                \
        --output=text                                  \
        --region "$REGION"                             \
        | grep -A 1 "$APP_LABEL"                       \
        | grep "SOURCEBUNDLE"                          \
        | cut -f 2
}

function upload_file {

    FILE=$1
    S3_BUCKET=$2

    # The file must be uploaded before the environment is created
    echo "Uploading $FILE to s3://$S3_BUCKET/ ..."
    OUTPUT=$(aws s3 cp --region "$REGION" $FILE "s3://$S3_BUCKET/" 2>&1)

    if [ $? -eq 0 ]; then
        echo "$1 copied to [$S3_BUCKET] bucket."
    else
        echo "Error: $OUTPUT"
        exit 1
    fi
}

# Checks if the application exists and creates
# it if it doesn't exist.
function create_application {

    aws elasticbeanstalk describe-applications \
        --application-names "$APP_LABEL"       \
        --region "$REGION"                     \
        --output text | grep -q "$APP_LABEL"

    if [ $? -eq 0 ]; then

        echo "Application [$APP_LABEL] exists."

    else
        echo "Application [$APP_LABEL] doesn't exist."

        OUTPUT=$(aws elasticbeanstalk create-application  \
            --application-name "$APP_LABEL"                \
            --description "$APP_DESCRIPTION"              \
            --region "$REGION" 2>&1)

        if [ $? -eq 0 ]; then
            echo "Application [$APP_LABEL] created."
        else
            echo "Error: $OUTPUT"
            exit 1
        fi
    fi
}

# We create a bucket to write our Dockerfile and a version
# reading from that Dockerfile. A Dockerfile.aws.json can be
# used as well, but I didn't want to add another file. If
# Dockerfile.aws.json is used, then we can mount volumes,
# which is very handy to "upload" the code to the image:
#
#     "Volumes": [
#     {
#         "HostDirectory": "/var/app/mydb",
#         "ContainerDirectory": "/etc/mysql"
#     }
#
# TODO: s3 has a very useful sync command if we were to sync an entire folder.
function create_version {

    ENVIRONMENT_OUTPUT=$(get_application_environment_bucket)

    if [ "x$ENVIRONMENT_OUTPUT" == "x" ]; then

        echo "Version [$VERSION_LABEL] doesn't exist. Creating..."

        OUTPUT=$(aws elasticbeanstalk create-storage-location \
            --region "$REGION" --output=text 2>&1)

        if [ $? -eq 0 ]; then
            S3_BUCKET="$OUTPUT"
            echo "  S3 bucket [$S3_BUCKET] created."
        else
            echo "Error: $OUTPUT"
            exit 1
        fi

        upload_file "Dockerfile" "$S3_BUCKET"

        OUTPUT=$(aws elasticbeanstalk create-application-version \
               --version-label "$VERSION_LABEL"              \
               --application-name "$APP_LABEL"               \
               --description "$VERSION_DESCRIPTION"          \
               --no-auto-create-application                  \
               --source-bundle "S3Bucket=$S3_BUCKET,S3Key=Dockerfile" \
               --region "$REGION" 2>&1 ) 

        if [ $? -eq 0 ]; then
            echo "  Version [$VERSION_LABEL] created."
        else
            echo "Error: $OUTPUT"
            exit 1
        fi

     else
        S3_BUCKET=$ENVIRONMENT_OUTPUT

        echo "Version [$VERSION_LABEL] with S3 bucket [$S3_BUCKET] exists."

        upload_file "Dockerfile" "$S3_BUCKET"

        OUTPUT=$(aws elasticbeanstalk update-application-version \
               --application-name "$APP_LABEL"                   \
               --version-label "$VERSION_LABEL"                  \
               --description "$VERSION_DESCRIPTION"              \
               --region "$REGION" 2>&1 ) 

        if [ $? -eq 0 ]; then
            echo "Version [$VERSION_LABEL] updated."
        else
            echo "Error: $OUTPUT"
            exit 1
        fi
    fi

}

# When an environment is created or update, the actual code is deployed
# to an EC2 instance. We set as well whether it's a webserver, a worker,
# if we use Docker or not, and if we use Apache an such things.
function create_environment {

    OUTPUT=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_LABEL"                 \
        --output=text                                   \
        --region "$REGION" 2>&1                         \
        |  grep ENVIRONMENT | grep -v "Termina" ) # Nor terminated nor terminating

    if [ $? -eq 0 ]; then
        echo "Environment running. Updating..."

        OUTPUT=$(aws elasticbeanstalk update-environment      \
            --environment-name "$ENV_LABEL"                   \
            --description "$ENV_DESCRIPTION"                  \
            --tier "$TIER"                                    \
            --version-label "$VERSION_LABEL"                  \
            --region "$REGION" 2>&1)

        if [ $? -eq 0 ]; then
            echo "Environment [$ENV_LABEL] updated."
        else
            echo "Error: $OUTPUT"
            exit 1
        fi
    else
        echo "No running environment. Creating one..."

        OUTPUT=$(aws elasticbeanstalk create-environment      \
            --environment-name "$ENV_LABEL"                   \
            --description "$ENV_DESCRIPTION"                  \
            --application-name "$APP_LABEL"                   \
            --tier "$TIER"                                    \
            --solution-stack-name "$STACK"                    \
            --version-label "$VERSION_LABEL"                  \
            --region "$REGION" 2>&1)

        if [ $? -eq 0 ]; then
            echo "Environment [$ENV_LABEL] created."
        else
            echo "Error: $OUTPUT"
            exit 1
        fi
    fi
}

create_application

create_version

create_environment

URL=$(get_deploy_url)

echo "$APP_LABEL:$VERSION_LABEL deployed to [$URL]!"
