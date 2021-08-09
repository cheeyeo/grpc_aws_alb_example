.PHONY: build-protobufs build-docker cert upload-cert

build-protobufs:
	python -m grpc_tools.protoc -I . --python_out=. --grpc_python_out=. ./route_guide.proto

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
