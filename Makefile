.PHONY: build-protobufs build-docker cert upload-cert run-client setup teardown

build-protobufs:
	python -m grpc_tools.protoc -I . --python_out=route_guide --grpc_python_out=route_guide ./route_guide.proto

# Builds and push image to ECR
build-docker:
	docker build -t route_guide:latest -f Dockerfile.aws .

	aws --profile $(AWS_PROFILE) ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(ECR_REPO)

	docker tag route_guide:latest $(ECR_REPO)/route_guide:latest

	docker push $(ECR_REPO)/route_guide:latest


## Create certificates to encrypt the gRPC connection
cert:
	openssl genrsa -out server.key 2048

	openssl req -nodes -new -x509 -sha256 -days 1825 -config certificate.conf -extensions 'req_ext' -key server.key -out server.crt

upload-cert:
	aws --profile $(AWS_PROFILE) acm import-certificate --certificate fileb://server.crt --private-key fileb://server.key


run-client:
	PYTHONPATH="${PWD}/route_guide" python route_guide_client.py --secure

setup:
	terraform -chdir=terraform init
	terraform -chdir=terraform fmt
	terraform -chdir=terraform validate
	terraform -chdir=terraform plan -var-file=config.tfvars -out myplan
	terraform -chdir=terraform apply myplan

teardown:
	terraform -chdir=terraform destroy -var-file=config.tfvars