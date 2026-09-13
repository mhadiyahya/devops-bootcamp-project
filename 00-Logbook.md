# Project Name: DevOps Boootcamp Project

# Objektif
- Membina AWS infrastruktur menggunakan kemahiran DevOps
- Mempraktikkan dua belas keluarga dalam satu sistem

# Senarai 12 Keluarga
1. DevOps
2. Linux
3. Git
4. GitHub
5. AWS
6. Cloudflare
7. Docker
8. CI/CD
9. Terraform
10. Ansible
11. Prometheus
12. Grafana

# Pemeriksaan Kesediaan Persekitaran Kerja

## Host
wsl --version
WSL version: 2.6.1.0
Kernel version: 6.6.87.2-1
WSLg version: 1.0.66
MSRDC version: 1.2.6353
Direct3D version: 1.611.1-81528511
DXCore version: 10.0.26100.1-240331-1435.ge-release
Windows version: 10.0.26200.9445

docker --version
Docker version 29.6.1, build 8900f1d

docker compose version
Docker Compose version v5.3.0

## WSL
aws --version
aws-cli/2.34.64 Python/3.14.5 Linux/6.6.87.2-microsoft-standard-WSL2 exe/x86_64.ubuntu.24

git --version
git version 2.43.0

terraform --version
Terraform v1.15.8 on linux_amd64

Your version of Terraform is out of date! The latest version is 1.16.2.

Remark:
After upgrade Terraform version

terraform --version
Terraform v1.16.2 on linux_amd64

ansible --version
ansible [core 2.21.2]
  config file = /etc/ansible/ansible.cfg
  configured module search path = ['/home/hadi/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python3/dist-packages/ansible
  ansible collection location = /home/hadi/.ansible/collections:/usr/share/ansible/collections
  executable location = /usr/bin/ansible
  python version = 3.12.3 (main, Aug 31 2026, 10:18:26) [GCC 13.3.0] (/usr/bin/python3)
  jinja version = 3.1.2
  pyyaml version = 6.0.1 (with libyaml v0.2.5)

## Pengujian komunikasi Docker Desktop dengan WSL
docker run --rm hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
4f55086f7dd0: Pull complete
d5e71e642bf5: Download complete
Digest: sha256:5e23090353324d887c48ad5e5c56d294eab81588df9605b07d1afe895f9cc8f8
Status: Downloaded newer image for hello-world:latest

## Periksa AWS Sumber

### Pengguna IAM
aws iam get-user
{
    "User": {
        "Path": "/",
        "UserName": "iam-xxxx",
        "UserId": "AIDA2MF5YZJFIAJxxxxxx",
        "Arn": "arn:aws:iam::713362xxxxxx:user/iam-hadi",
        "CreateDate": "2026-09-13T03:32:30+00:00"
    }
}

### Kumpulan Pengguna
aws iam list-groups-for-user \
  --user-name iam-xxx

{
    "Groups": []
}

### Semak Polisi
aws iam list-attached-user-policies \
  --user-name iam-xxxx

{
    "AttachedPolicies": [
        {
            "PolicyName": "AdministratorAccess",
            "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
        }
    ]
}

### Konfigurasi Akses
aws sts get-caller-identity
{
    "UserId": "AIDA2MF5YZJFIAJ7xxxxx",
    "Account": "713362xxxxx",
    "Arn": "arn:aws:iam::713362xxxxxx:user/iam-xxxx"
}

### Lokasi
aws configure get region
ap-southeast-1

### VPC
aws ec2 describe-vpcs \
  --region ap-southeast-1 \
  --query 'Vpcs[*].[VpcId,CidrBlock,Tags]' \
  --output table

Remark:
- Tiada VPC konfigurasi

### Subnets
aws ec2 describe-subnets \
  --region ap-southeast-1 \
  --query 'Subnets[*].[SubnetId,VpcId,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table

Remark:
- Tiada Subnet konfigurasi

### Instances
aws ec2 describe-instances \
  --region ap-southeast-1 \
  --query 'Reservations[*].Instances[*].[InstanceId,PrivateIpAddress,PublicIpAddress,State.Name,Tags]' \
  --output table

Remark:
- Tiada Instance konfigurasi

---