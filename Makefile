.PHONY: up down setup eks sagemaker destroy

up:
	docker compose up --build

down:
	docker compose down
setup:
	bash scripts/setup.sh

eks:
	bash scripts/run-eks-benchmark.sh

sagemaker:
	python scripts/run_sagemaker_benchmark.py --all

destroy:
	bash scripts/destroy.sh
