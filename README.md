# README


```sh
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 850515802126.dkr.ecr.us-west-2.amazonaws.com
terraform apply -auto-approve -target=aws_ecr_repository.instance
terraform output ecr_repository_name
# "ecr-repository"
terraform output ecr_repository_url
# "850515802126.dkr.ecr.us-west-2.amazonaws.com/ecr-repository"
cd app
docker build -t 850515802126.dkr.ecr.us-west-2.amazonaws.com/ecr-repository:init .
docker push 850515802126.dkr.ecr.us-west-2.amazonaws.com/ecr-repository:init
cd ..
AWS_PROFILE=admin terraform plan
AWS_PROFILE=admin terraform apply
terraform output alb_dns
# "alb-1825075231.us-west-2.elb.amazonaws.com"

curl alb-1825075231.us-west-2.elb.amazonaws.com
```

```
AWS_PROFILE=admin terraform destroy
aws ecr list-images --repository-name "ecr-repository"
aws ecr batch-delete-image --repository-name "ecr-repository" --image-ids imageTag=init
```
