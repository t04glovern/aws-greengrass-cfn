#!/bin/bash

mkdir certs
mkdir config

AWS_ACCOUNT_ID=$(aws sts get-caller-identity |  jq -r '.Account')
AWS_REGION="us-east-1"

certificateId=$(aws cloudformation describe-stacks --stack-name "devopstar-rpi-gg-core" \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificateId`].OutputValue' \
    --output text)

certificatePem=$(aws cloudformation describe-stacks --stack-name "devopstar-rpi-gg-core" \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificatePem`].OutputValue' \
    --output text)

certificatePrivateKey=$(aws cloudformation describe-stacks --stack-name "devopstar-rpi-gg-core" \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificatePrivateKey`].OutputValue' \
    --output text)

iotEndpoint=$(aws cloudformation describe-stacks --stack-name "devopstar-rpi-gg-core" \
    --query 'Stacks[0].Outputs[?OutputKey==`IoTEndpoint`].OutputValue' \
    --output text)

echo -n "${certificatePem}" > certs/${certificateId}.pem
echo -n "${certificatePrivateKey}" > certs/${certificateId}.key

cat <<EOT > config/config.json          
{
    "coreThing" : {
        "caPath" : "root.ca.pem",
        "certPath" : "${certificateId}.pem",
        "keyPath" : "${certificateId}.key",
        "thingArn" : "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/gg_cfn_Core",
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