### GRPC on AWS Application Load Balancer

This is an example GRPC application that runs as an ECS service on a custom ECS cluster with traffic routed via the internet through an Application Load Balancer. 

This is my attempt at re-creating the demo [from the following blog post](https://aws.amazon.com/blogs/aws/new-application-load-balancer-support-for-end-to-end-http-2-and-grpc/)

Like the post, I adopted the route guide grpc example [from the official grpc repo](https://github.com/grpc/grpc/tree/master/examples/python/route_guide) and adapted it as follows:

* Added an option to the route_guide_client.py file to allow for secure channel communication. Default is False

* Added an option to the route_guide_server.py to allow for mutual TLS with the client. Default is False.

When running locally, use the Makefile to generate the libs from the protobuf and to generate the certs and build the docker container:

```
# create a .env file with an aws profile name and ecr repo link

source .env

make build-protobufs

make cert

make build-docker
```

To run locally:
```
# to use TLS auth
python route_guide_client.py --secure


python route_guide_server.py --secure
```

### Deploying to AWS

The terraform scripts provision the following resources:

* ECS Cluster
* Application Load Balancer
* Fargate ECS Service
* Custom VPC with 2 public subnets and 2 private subnets ( ALB need at least 2 subnets )

To provision:
```
terraform -chdir=terraform init

terraform -chdir=terraform plan -var-file=config.tfvars -out myplan

terraform -chdir=terraform apply myplan

terraform -chdir=terraform output

```

Get the `load_balancer` output and export it as `HOST` env var which will be read by the client.

If all goes well with running against AWS, one should see the following output:
```
export HOST=<DNS A record of ALB from terraform output>

python route_guide_client.py --secure


REMOTE HOST >  route-guide-1954688975.us-east-1.elb.amazonaws.com

-------------- GetFeature --------------
Feature called Berkshire Valley Management Area Trail, Jefferson, NJ, USA at latitude: 409146138
longitude: -746188906

Found no feature at 
-------------- ListFeatures --------------
Looking for features between 40, -75 and 42, -73
Feature called Patriots Path, Mendham, NJ 07945, USA at latitude: 407838351
longitude: -746143763

Feature called 101 New Jersey 10, Whippany, NJ 07981, USA at latitude: 408122808
longitude: -743999179

Feature called U.S. 6, Shohola, PA 18458, USA at latitude: 413628156
longitude: -749015468

Feature called 5 Conners Road, Kingston, NY 12401, USA at latitude: 419999544
longitude: -740371136
```

To remove all AWS resources:
```
terraform -chdir=terraform destroy -var-file=config.tfvars

```

### gRPC TLS Notes

* To use a self signed cert on ALB, we need to sign the cert with `subjectAltName` set to both `localhost` and `*.us-east-1.elb.amazonaws.com`. This can be adjusted to suit...

	Note that this is by no means a secure way of running a production service. The server keys are unencrypted and really should use a KMS service to provision the certificates dynamically at run time...

* Also the certificate should be issued to a domain, and we can create an Route 53 Alias record that points to the DNS A record of the ALB ...

* If running with mutual client / server TLS on, we need to enable HTTPS for healthcheck else ALB fails...


* To inspect the generated TLS certs we can use openssl:
```
openssl x509 -in server.crt --text
```

### References

[GRPC Guide](https://developers.google.com/protocol-buffers/docs/overview)

[Source](https://github.com/protocolbuffers/protobuf/blob/master/python/google/protobuf/internal/well_known_types_test.py)

[Running on ECS](https://aws.amazon.com/blogs/aws/new-application-load-balancer-support-for-end-to-end-http-2-and-grpc/)

[Generate Certificate for ACM](https://medium.com/@chamilad/adding-a-self-signed-ssl-certificate-to-aws-acm-88a123a04301)

[SSL WITH GRPC](https://itnext.io/practical-guide-to-securing-grpc-connections-with-go-and-tls-part-1-f63058e9d6d1)

[Section on TLS](https://realpython.com/python-microservices-grpc/#asyncio-and-grpc)

[TFX Serving on EKS example](https://towardsdatascience.com/exposing-tensorflow-servings-grpc-endpoints-on-amazon-eks-e6877d3a51bd)

[Using TLS with GRPC](http://www.inanzzz.com/index.php/post/jo4y/using-tls-ssl-certificates-for-grpc-client-and-server-communications-in-golang-updated)

[Article on GRPC over REST](https://towardsdatascience.com/reasons-to-choose-grpc-over-rest-and-how-to-adopt-it-into-your-python-apis-197ac28e22b4)

[ALB example using Terraform](https://github.com/terraform-aws-modules/terraform-aws-alb/blob/v6.3.0/examples/complete-alb/main.tf)

[Example of ECS Fargate service on private subnet with ALB](https://engineering.finleap.com/posts/2020-02-20-ecs-fargate-terraform/)

[Example code for above](https://github.com/finleap/tf-ecs-fargate-tmpl/)


### Replace listeners for elb using cli

https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-update-certificates.html


https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-listener.html

```
aws --profile <myprofile> elbv2 modify-listener --listener-arn <listener_arn> --certificates CertificateArn=<certificate_arn>
```