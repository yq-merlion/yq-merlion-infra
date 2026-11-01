# Phase 1: leave this commented out and apply with local state. The state bucket doesn't exist yet.
# Phase 2: uncomment, then run `terraform init -migrate-state` to move state into the bucket.
# Backend blocks can't use variables, so the values are written out in full.

# terraform {
#   backend "s3" {
#     bucket       = "yq-merlion-bootstrap-tfstate-255945442255"
#     key          = "terraform.tfstate"
#     region       = "us-east-1"
#     profile      = "personal"
#     encrypt      = true
#     kms_key_id   = "alias/yq-merlion-bootstrap" # without this the backend uploads with AES256, not our key
#     use_lockfile = true
#   }
# }
