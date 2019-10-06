# AWS Greengrass Cloudformation - Raspberry Pi

## Setting up a Raspberry Pi

Download [Rasbian lite image](https://www.raspberrypi.org/downloads/raspbian/)

```bash
wget https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-09-30/2019-09-26-raspbian-buster-lite.zip
```

### Burn Image

Burn the image with [Etcher](https://www.balena.io/etcher/)

![Etcher Burn Raspbian](img/etcher-raspbian-burn.png)

### Setup WiFi

This might be different based on your OS, the general idea is that you will need to create:

* An empty file called `ssh` in the `/boot/` partition
* A file called `wpa_supplicant.conf` in the same partition

```bash
touch /Volumes/boot/ssh
touch /Volumes/boot/wpa_supplicant.conf
nano /Volumes/boot/wpa_supplicant.conf

# Add the following config
country=AU
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="NETWORK-NAME"
    psk="NETWORK-PASSWORD"
}
```

### Connect to Pi

```bash
ssh-keygen -R raspberrypi.local
ssh pi@raspberrypi.local
# password: rasbperry
```

Next we'll update the system with the latest packages

```bash
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install python-pip -y
```

### Prepare for Greengrass

Now we need to perform a set of steps that are best described in the [offical AWS setup guide for the Raspberry Pi](https://docs.aws.amazon.com/greengrass/latest/developerguide/setup-filter.rpi.html)

```bash
# Create user and group
sudo adduser --system ggc_user
sudo addgroup --system ggc_group

# enable hardlink and softlink (symlink) protection
sudo nano /etc/sysctl.d/98-rpi.conf
```

Add the following lines to `98-rpi.conf`

```bash
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
```

Reboot the pi, and when logged back in confirm the settings were set

```bash
sudo reboot
sudo sysctl -a 2> /dev/null | grep fs.protected
```

Edit your command line `/boot/cmdline.txt` file to enable and mount memory cgroups. Append the following to the single line

```bash
cgroup_enable=memory cgroup_memory=1
```

The file should look like the following (with some changes to partition for example)

```bash
console=serial0,115200 console=tty1 root=PARTUUID=6c586e13-02 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait cgroup_enable=memory cgroup_memory=1
```

Reboot the Pi again

```bash
sudo reboot
```

### Greengrass Dependency Checker

To confirm that all prerequisites are furfilled we'll use the [Greengrass Dependency Checker](https://github.com/aws-samples/aws-greengrass-samples)

```bash
mkdir /home/pi/Downloads && cd /home/pi/Downloads
mkdir greengrass-dependency-checker-GGCv1.9.x && cd greengrass-dependency-checker-GGCv1.9.x
wget https://github.com/aws-samples/aws-greengrass-samples/raw/master/greengrass-dependency-checker-GGCv1.9.x.zip
unzip greengrass-dependency-checker-GGCv1.9.x.zip && cd greengrass-dependency-checker-GGCv1.9.x
sudo modprobe configs
sudo ./check_ggc_dependencies | more
```

There wil likely be a couple warnings:

* It looks like the kernel uses 'systemd' as the init process.
* Could not find the binary 'nodejs8.10'.
* Could not find the binary 'java8'.

These are safe to ignore for now, the first warning should be kept in mind however.

## Greengrass Setup

The deployment of the greengrass group can be done by the GUI or by CloudFormation. If you have an interest in how to do it by the UI, please check the [AWS guide on this](https://docs.aws.amazon.com/greengrass/latest/developerguide/gg-config.html).

Personally I much prefer deploying it by CloudFormation as it gives us more flexability for configuration as code later on and helps encourage repeatability in our deployments.

### CloudFormation Greengrass Deploy

To deploy using CloudFormation, ensure you have the AWS CLI configured on your local system and proceed to run the command below

```bash
aws cloudformation update-stack \
    --stack-name "devopstar-rpi-gg-core" \
    --template-body file://aws/greengrass.yaml \
    --region "us-east-1" \
    --capabilities CAPABILITY_IAM
```

Next we're going to build the `tar.gz` bundle with our certificates and greengrass configuration

**NOTE**: *This script assumes that you deployed to `us-east-1` and left the stackname as `devopstar-rpi-gg-core`. If you changed that portion, replace references to `devopstar-rpi-gg-core` with your own stack name.*

```bash
cd aws
./greengrass.sh
```

### Deployment Files to Raspberry Pi

In this step we'll download AWS IoT Greengrass Core then copy it to our Raspberry Pi. We will also copy our previously packages certificates and configuration at the same time.

#### Download Greengrass Core

Depending on what version your raspberry pi is will determine what version we'll need. Run the following command to get your architecture.

```bash
uname -a
# Linux raspberrypi 4.19.75+ #1270 Tue Sep 24 18:38:54 BST 2019 armv6l GNU/Linux
```

In this case my architecture is `armv6l` so from the [Greengrass download page download](https://docs.aws.amazon.com/greengrass/latest/developerguide/what-is-gg.html#gg-core-download-tab) the distribution for rasbian that matches this

```bash
# Download the `armv6l` tar
wget https://d1onfpft10uf5o.cloudfront.net/greengrass-core/downloads/1.9.3/greengrass-linux-armv6l-1.9.3.tar.gz
```

Now that we have the files we need, copy them all to the Raspberry Pi

```bash
scp greengrass-linux-armv6l-1.9.3.tar.gz pi@raspberrypi.local:/home/pi
scp aws/*-setup.tar.gz pi@raspberrypi.local:/home/pi
scp aws/greengrass-service.sh pi@raspberrypi.local:/home/pi
```

#### Extract Greengrass Files

SSH back onto the Raspberry Pi and extract the two file bundles we just downloaded by running the following

```bash
sudo tar -xzvf greengrass-<ARCHITECTURE>-1.9.3.tar.gz -C /
sudo tar -xzvf <hash>-setup.tar.gz -C /greengrass
```

Confirm everything copied across correctly by running the following

```bash
ls -al /greengrass
# drwxr-xr-x  6 root root 4096 Aug 31 04:40 .
# drwxr-xr-x 22 root root 4096 Aug 31 04:40 ..
# drwxrwxr-x  2 pi   pi   4096 Oct  6 18:01 certs
# drwxrwxr-x  2 pi   pi   4096 Oct  6 18:01 config
# drwxr-xr-x  3 root root 4096 Aug 31 04:40 ggc
# drwxr-xr-x  3 root root 4096 Aug 31 04:40 ota
```

Next we also need to download the ATS root CA

```bash
cd /greengrass/certs/
sudo wget -O root.ca.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

### Greengrass Start

With all the files in the right places on the device, it's now time to try to start the service

```bash
cd /greengrass/ggc/core/
sudo ./greengrassd start
```

You should see a Greengrass successfully started message. Take note of the PID of the process so we can view the status of the daemon

```bash
ps aux | grep PID_NUMBER
# root       761  2.4  3.0 854472 13508 pts/0    Sl   18:18   0:01 /greengrass/ggc/packages/1.9.3/bin/daemon -core-dir /greengrass/ggc/packages/1.9.3 -greengrassdPid 757
```

To setup Greengrass on startup, run the following

```bash
sudo ./greengrass-service.sh
```

#### Greengrass SDK

If you don't want to bundle the greengrasssdk in with your application, you can install it globally

```bash
sudo pip install greengrasssdk
```

#### Greengrass Deploy [CLI]

To create our first deployment we first need to retrive our Greengrass Group ID

```bash
aws greengrass list-groups
# {
#     "Groups": [
#         {
#             "Arn": "arn:aws:greengrass:us-east-1:123456789012:/greengrass/groups/41752ff2-54e5-49e9-8751-d489e3e6fa1f",
#             "CreationTimestamp": "2019-10-06T10:31:53.950Z",
#             "Id": "41752ff2-54e5-49e9-8751-d489e3e6fa1f",
#             "LastUpdatedTimestamp": "2019-10-06T10:31:53.950Z",
#             "LatestVersion": "1c578332-44f7-411b-9ebb-1139fa1e453a",
#             "LatestVersionArn": "arn:aws:greengrass:us-east-1:123456789012:/greengrass/groups/41752ff2-54e5-49e9-8751-d489e3e6fa1f/versions/1c578332-44f7-411b-9ebb-1139fa1e453a",
#             "Name": "gg_cfn"
#         }
#     ]
# }
```

In my case the group ID can be seen above, simply substitue it into the following command to kick off your first deployment

```bash
aws greengrass create-deployment \
    --deployment-type NewDeployment \
    --group-id "41752ff2-54e5-49e9-8751-d489e3e6fa1f"
```

#### Greengrass Deployment [GUI]

To deploy through the GUI, navigate to the [AWS IoT Greengrass portal](https://us-east-1.console.aws.amazon.com/iot/home?region=us-east-1#/greengrass/groups) and kick off a new deployment under the Greegrass group we just created

![Greengrass Deployment](img/greengrass-deployment-01.png)

### Greengrass Test

To test greengrass, navigate to the Test portal under AWS IoT and subscribe to the `gg_cfn/telem` topic

![Greengrass Test](img/greengrass-test-01.png)

## Greengrass Cleanup

Once you're finished worknig with Greengrass it's really easy to cleanup the AWS resources we used. Run the following command to destory the CloudFormation stack

```bash
aws cloudformation delete-stack \
    --stack-name "devopstar-rpi-gg-core" \
    --region "us-east-1"
```

## Attribution

* [Setting Up a Raspberry Pi](https://docs.aws.amazon.com/greengrass/latest/developerguide/setup-filter.rpi.html)
