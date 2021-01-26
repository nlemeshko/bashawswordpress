#!/bin/bash

echo "Create AWS Instance"
instanceid=$(aws ec2 run-instances --image-id ami-009b16df9fcaac611 --count 1  --instance-type t2.micro --key-name itea --instance-type t2.micro --security-group-ids sg-028b25df28ffef202 | jq -r '.Instances | .[] | {InstanceId: .InstanceId} | .[]')
sleep 10
echo "Instance created with id $instanceid"

echo "Add tags to our Instance"
aws ec2 create-tags --resources $instanceid --tags Key=Name,Value=wordpress
sleep 5
echo "Tag wordpress successfully added"

echo "Write PublicDNS and IP"
publicdns=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wordpress" | jq -r '.Reservations | .[] | .Instances | .[] | .PublicDnsName')
ip=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=wordpress" | jq -r '.Reservations | .[] | .Instances | .[] | .PublicIpAddress')
sleep 5

echo "Create RDS DB instance"
RDS=$(aws rds create-db-instance --db-name wordpress --db-instance-identifier database-1 --engine mysql --db-instance-class db.t2.micro --master-username admin --master-user-password q1q1q1q1 --vpc-security-group-ids sg-028b25df28ffef202 --allocated-storage 10)
echo "RDS DB successfully created"

until [ $(aws rds describe-db-instances --db-instance-identifier database-1 | jq -r '.DBInstances | .[] | .DBInstanceStatus ') == "available" ]
do
    echo "RDS staring. Curent status is $(aws rds describe-db-instances --db-instance-identifier database-1 | jq -r '.DBInstances | .[] | .DBInstanceStatus ')"
    sleep 180
done

db=$(aws rds describe-db-instances --db-instance-identifier database-1 | jq -r '.DBInstances | .[] | .Endpoint | .Address ')

echo "Creating Bucket"
bucket=$(aws s3api create-bucket --bucket wordpress3 --acl public-read --create-bucket-configuration LocationConstraint=eu-central-1)
echo "S3 bucket successfully created"

echo "Create S3 user"
user=$(aws iam create-user --user-name s3 && aws iam attach-user-policy --user-name s3 --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess)
echo "Successfully created"

echo "Create Access keys"
s3access=$(aws iam create-access-key --user-name s3)
s3accesskey=$(echo $s3access | jq -r ".AccessKey | .AccessKeyId")
s3secretkey=$(echo $s3access | jq -r ".AccessKey | .SecretAccessKey")

echo "Create SES user"
ses=$(aws iam create-user --user-name ses && aws iam attach-user-policy --user-name ses --policy-arn arn:aws:iam::904112984347:policy/sesmail)
echo "SES user created"

echo "Create SES Access keys"
sesaccess=$(aws iam create-access-key --user-name ses)
sesaccesskey=$(echo $sesaccess | jq -r ".AccessKey | .AccessKeyId")
sessecretkey=$(echo $sesaccess | jq -r ".AccessKey | .SecretAccessKey")
basesecret=$(python3 ses.py $sessecretkey eu-central-1)

amazon="ssh -oStrictHostKeyChecking=no -i ~/.ssh/itea.pem ec2-user@$publicdns"

echo "Connect to Instance"
$amazon sudo yum -y install iptables
$amazon sudo yum -y install -y yum-utils
$amazon sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
$amazon sudo yum -y install docker-ce docker-ce-cli containerd.io
$amazon sudo systemctl start docker
$amazon sudo docker run --rm --name wordpress -it -d -p80:80 wordpress
$amazon sudo docker exec wordpress apt -y update
$amazon sudo docker exec wordpress apt -y install wget unzip
$amazon sudo docker exec wordpress wget https://downloads.wordpress.org/plugin/amazon-s3-and-cloudfront.2.5.2.zip
$amazon sudo docker exec wordpress unzip amazon-s3-and-cloudfront.2.5.2.zip -d /var/www/html/wp-content/plugins/
$amazon sudo docker exec wordpress wget https://downloads.wordpress.org/plugin/wp-mail-smtp.2.5.1.zip
$amazon sudo docker exec wordpress unzip wp-mail-smtp.2.5.1.zip -d /var/www/html/wp-content/plugins/





echo -e "\e[97mYour \e[32mInstance\e[97m Domain is \e[93m$publicdns\e[97m\nYour \e[32mIP\e[97m is \e[93m$ip\e[97m"
echo -e "\e[32mRDS\e[97m domain adress is: \e[93m$db\e[97m"
echo -e "Your \e[32mS3\e[97m accesskey is \e[93m$s3accesskey\e[97m\nYour \e[32mS3\e[97m secretkey is \e[93m$s3secretkey\e[97m"
echo -e "\e[32mSMTP\e[97m ServerName is \e[93memail-smtp.eu-central-1.amazonaws.com\e[97m"
echo -e "Your \e[32mSMTP\e[97m username is \e[93m$sesaccesskey\e[97m\nYour \e[32mSMTP\e[97m password is \e[93m$basesecret\e[97m"