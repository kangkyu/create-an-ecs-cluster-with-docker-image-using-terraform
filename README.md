# README


```sh
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-west-2.amazonaws.com
terraform apply -auto-approve -target=aws_ecr_repository.instance
terraform output ecr_repository_name
# "ecr-repository"
terraform output ecr_repository_url
# "123456789012.dkr.ecr.us-west-2.amazonaws.com/ecr-repository"
cd app
docker build -t 123456789012.dkr.ecr.us-west-2.amazonaws.com/ecr-repository:init .
docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/ecr-repository:init
cd ..
AWS_PROFILE=admin terraform plan
AWS_PROFILE=admin terraform apply
terraform output alb_dns
# "alb-95076848.us-west-2.elb.amazonaws.com"

curl alb-95076848.us-west-2.elb.amazonaws.com
# Hello, world!
```

```sh
AWS_PROFILE=admin terraform destroy

aws ecr list-images --repository-name "ecr-repository"
# {
#     "imageIds": [
#         {
#             "imageDigest": "sha256:c44afb6963c82c4ead49e3aff357b1ceb19a338a0a6029764039464addeb6116",
#             "imageTag": "init"
#         }
#     ]
# }
aws ecr batch-delete-image --repository-name "ecr-repository" --image-ids imageTag=init
```

* Errors
```
ResourceInitializationError: unable to pull secrets or registry auth: execution resource retrieval failed: unable to retrieve ecr registry auth: service call has been retried 3 time(s): RequestError: send request failed caused by: Post "https://api.ecr.us-west-2.amazonaws.com/": dial tcp 52.94.184.143:443: i/o timeout
```
(changed private -> public subnet)

```
Task failed ELB health checks in (target-group arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/alb-target-group/856238e446c9a134)
```
(increase timeout seconds; loosen security group cidr_block)
