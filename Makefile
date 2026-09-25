.PHONY: tf-init tf-apply crossplane image eks sagemaker ui destroy

tf-init:
	terraform -chdir=infra/terraform init

tf-apply:
	terraform -chdir=infra/terraform apply -auto-approve -var="worker_count=2"
	aws eks update-kubeconfig --region eu-central-1 --name vision-scale-bench

crossplane:
	bash scripts/install-crossplane.sh

image:
	bash scripts/build-push-image.sh

eks:
	bash scripts/run-eks-benchmark.sh

sagemaker:
	python scripts/run_sagemaker_benchmark.py --all

ui:
	bash scripts/start-ui.sh

destroy:
	bash scripts/destroy.sh
