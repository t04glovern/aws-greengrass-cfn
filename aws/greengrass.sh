#!/bin/bash

while getopts p: option
do
 case "${option}"
 in
 p) PROFILE=${OPTARG};;
 esac
done

PROFILE=${PROFILE:-default}
echo "Using AWS Profile:"$PROFILE
echo "Use -p profileName to switch between your AWS profiles."

mkdir certs
mkdir config

AWS_ACCOUNT_ID=$(aws sts --profile ${PROFILE} get-caller-identity |  jq -r '.Account')
AWS_REGION="us-east-1"
CORE_NAME="gg_cfn"
CFN_STACK_NAME="devopstar-rpi-gg-core"

certificateId=$(aws cloudformation describe-stacks --stack-name ${CFN_STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificateId`].OutputValue' \
    --region ${AWS_REGION} \
    --profile ${PROFILE} \
    --output text)

certificatePem=$(aws cloudformation describe-stacks --stack-name ${CFN_STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificatePem`].OutputValue' \
    --region ${AWS_REGION} \
    --profile ${PROFILE} \
    --output text)

certificatePrivateKey=$(aws cloudformation describe-stacks --stack-name ${CFN_STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificatePrivateKey`].OutputValue' \
    --region ${AWS_REGION} \
    --profile ${PROFILE} \
    --output text)

iotEndpoint=$(aws cloudformation describe-stacks --stack-name ${CFN_STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`IoTEndpoint`].OutputValue' \
    --region ${AWS_REGION} \
    --profile ${PROFILE} \
    --output text)

echo -n "${certificatePem}" > certs/${certificateId}.pem
echo -n "${certificatePrivateKey}" > certs/${certificateId}.key

cat <<EOT > config/config.json          
{
    "coreThing" : {
        "caPath" : "root.ca.pem",
        "certPath" : "${certificateId}.pem",
        "keyPath" : "${certificateId}.key",
        "thingArn" : "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/${CORE_NAME}_Core",
        "iotHost" : "${iotEndpoint}",
        "ggHost" : "greengrass-ats.iot.${AWS_REGION}.amazonaws.com"
    },
    "runtime" : {
        "cgroup" : {
        "useSystemd" : "yes"
        }
    },
    "managedRespawn" : false,
    "crypto" : {
        "principals" : {
        "SecretsManager" : {
            "privateKeyPath" : "file:///greengrass/certs/${certificateId}.key"
        },
        "IoTCertificate" : {
            "privateKeyPath" : "file:///greengrass/certs/${certificateId}.key",
            "certificatePath" : "file:///greengrass/certs/${certificateId}.pem"
        }
        },
        "caPath" : "file:///greengrass/certs/root.ca.pem"
    }
}
EOT

tar -czvf ${certificateId}-setup.tar.gz certs/ config/