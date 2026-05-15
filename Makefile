.PHONY: init plan apply destroy fmt validate ssh logs

ENV ?= production
TFVARS := environments/$(ENV).tfvars

init:
	tofu init

fmt:
	tofu fmt -recursive

validate: fmt
	tofu validate

plan: validate
	tofu plan -var-file=$(TFVARS) -out=tfplan

apply: validate
	tofu apply -var-file=$(TFVARS) -auto-approve

destroy:
	@echo "WARNING: This will destroy all Sentry infrastructure for ENV=$(ENV)"
	@read -p "Type 'yes' to confirm: " confirm; [ "$$confirm" = "yes" ] || exit 1
	tofu destroy -var-file=$(TFVARS)

# SSH into the server (key auto-detected from outputs)
ssh:
	$(eval IP := $(shell tofu output -raw public_ip))
	$(eval KEY := $(shell tofu output -raw private_key_path 2>/dev/null || echo "~/.ssh/id_rsa"))
	ssh -i "$(KEY)" ubuntu@$(IP)

# Tail bootstrap logs on the remote server
logs:
	$(eval IP := $(shell tofu output -raw public_ip))
	$(eval KEY := $(shell tofu output -raw private_key_path 2>/dev/null || echo "~/.ssh/id_rsa"))
	ssh -i "$(KEY)" ubuntu@$(IP) "sudo journalctl -u sentry -f"
