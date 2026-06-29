VENV    := serverless/.venv
PYTHON  := $(VENV)/bin/python
REGION  ?= eu-west-1

.PHONY: help requirements terraform-init terraform-apply serverless-deploy publish publish-ok publish-fail fail-publish fail-publish-status purge-dlqs fix-npm-perms poll destroy

help:
	@echo "Usage: make <target> [REGION=<aws-region>]"
	@echo ""
	@echo "  REGION  AWS region to deploy to (default: us-east-1)"
	@echo ""
	@echo "Targets:"
	@echo "  requirements       Install all local dependencies (npm + pip + serverless)"
	@echo "  terraform-init     Initialize Terraform providers"
	@echo "  terraform-apply    Deploy infrastructure (SNS, SQS, IAM, CloudWatch)"
	@echo "  serverless-deploy  Deploy Lambda functions via Serverless Framework"
	@echo "  publish            Publish a normal test message to SNS"
	@echo "  publish-ok         Same as publish: stop forcing failures"
	@echo "  publish-fail       Simulate a publish failure before SNS"
	@echo "  fail-publish       Publish a message that forces consumers to fail (force_fail=true)"
	@echo "  fail-publish-status  Show queue and DLQ status for failed publishes"
	@echo "  purge-dlqs         Purge all DLQs to clear failed messages"
	@echo "  poll               Peek at messages in all SQS queues (non-destructive)"
	@echo "  destroy            Remove ALL resources (Serverless + Terraform)"
	@echo ""
	@echo "Examples:"
	@echo "  make terraform-apply REGION=eu-west-1"
	@echo "  make serverless-deploy REGION=ap-southeast-1"

requirements:
	@echo ">>> Install Python virtual environment and NPM"
	sudo apt install -y python3.14-venv npm
	@echo ">>> Creating Python virtual environment..."
	python3 -m venv $(VENV)
	@echo ">>> Installing Python dependencies into venv..."
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -r serverless/requirements.txt
	@echo ">>> Installing Serverless Framework v3 globally..."
	sudo npm install -g serverless@3
	@echo ">>> Installing Serverless plugins (serverless-python-requirements)..."
	cd serverless && npm install
	@echo ">>> All requirements installed."

terraform-init:
	cd terraform && terraform init

terraform-apply:
	cd terraform && terraform apply -var "queue_count=3" -var "aws_region=$(REGION)"

serverless-deploy:
	cd serverless && npm install && sls deploy --region $(REGION)

fix-npm-perms:
	@echo "Fixing ownership of serverless/node_modules to current user (may ask for sudo)"
	sudo chown -R $$(id -u):$$(id -g) serverless/node_modules || true
	@echo "If node_modules is corrupted, remove it and run 'cd serverless && npm install' as your user."

publish:
	AWS_DEFAULT_REGION=$(REGION) $(PYTHON) serverless/publish.py --structured

fail-publish:
	AWS_DEFAULT_REGION=$(REGION) $(PYTHON) serverless/publish.py '{"force_fail": true}'

purge-dlqs:
	@echo ">>> Purging all DLQs (warning: this deletes failed messages)"
	@python3 scripts/purge_dlqs.py --region $(REGION)

fail-publish-status:
	@echo ">>> Mostrar estado de colas principales y DLQs"
	@for type in queues dlqs; do \
		URLS=$$(python3 -c "import json,sys; data=json.load(open('terraform/outputs.json')); urls=data['queues'] if sys.argv[1]=='queues' else data['dlqs']; print(' '.join(item['url'] for item in urls))" $$type); \
		if [ -z "$${URLS}" ]; then \
			echo "No URLs found for $${type}."; \
			continue; \
		fi; \
		echo "--- $${type} ---"; \
		for URL in $${URLS}; do \
			echo "URL=$$URL"; \
			aws sqs get-queue-attributes --region $(REGION) --queue-url "$$URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --output json | python3 -c 'import json,sys; d=json.load(sys.stdin); print("Retrasado=", d.get("ApproximateNumberOfMessagesDelayed","?"), "EnProceso=", d.get("ApproximateNumberOfMessagesNotVisible","?"), "Disponible=", d.get("ApproximateNumberOfMessages","?"))'; \
			echo; \
		done; \
	done

poll:
	@echo ">>> Watching SQS queues every 1s (Ctrl+C to stop)..."
	@echo ">>> Leyenda: Retrasado=esperando 60s | En proceso=procesando por Lambda | Disponible=listo para consumir"
	@echo ""
	@while true; do \
		echo "─────────────────────────────────────────────────── $$(date '+%H:%M:%S')"; \
		for i in 1 2 3; do \
			URL=$$(python3 -c "import json; d=json.load(open('terraform/outputs.json')); print(d['queues'][$$i-1]['url'])"); \
			ATTRS=$$(aws sqs get-queue-attributes \
				--region $(REGION) \
				--queue-url "$$URL" \
				--attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed \
				--query "Attributes" \
				--output json 2>/dev/null); \
			VISIBLE=$$(echo $$ATTRS | python3 -c "import sys,json; print(json.load(sys.stdin).get('ApproximateNumberOfMessages','?'))"); \
			INFLIGHT=$$(echo $$ATTRS | python3 -c "import sys,json; print(json.load(sys.stdin).get('ApproximateNumberOfMessagesNotVisible','?'))"); \
			DELAYED=$$(echo $$ATTRS | python3 -c "import sys,json; print(json.load(sys.stdin).get('ApproximateNumberOfMessagesDelayed','?'))"); \
			echo "  Cola $$i → Retrasado: $$DELAYED  |  En proceso: $$INFLIGHT  |  Disponible: $$VISIBLE"; \
		done; \
		echo ""; \
		sleep 10; \
	done

destroy:
	@echo ">>> [1/2] Removing Serverless stack (Lambdas, API Gateway)..."
	cd serverless && sls remove --region $(REGION)
	@echo ">>> [2/2] Destroying Terraform infrastructure (SNS, SQS, DLQ, DynamoDB, IAM)..."
	cd terraform && terraform destroy -var "queue_count=3" -var "aws_region=$(REGION)" -auto-approve
	@echo ">>> All resources destroyed."
