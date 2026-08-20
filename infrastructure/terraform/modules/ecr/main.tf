# ECR module: one repository per service. Two policy decisions worth
# calling out explicitly:
#   - image_tag_mutability = IMMUTABLE: once a tag like the git SHA is
#     pushed, it can never be overwritten. This is the infra-level
#     enforcement of "never deploy :latest" from Phase 3/10 - it's not just
#     a convention now, a second push to the same tag is rejected outright.
#   - scan_on_push: every image gets a Trivy-equivalent vulnerability scan
#     the moment it lands in ECR, in addition to the Trivy step already
#     running in CI (Phase 7) - defense in depth, not redundancy.

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Keeps storage cost bounded: untagged images (left behind by IMMUTABLE tag
# pushes that got superseded) expire quickly; only the most recent N tagged
# images are kept per repo.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${var.max_tagged_images_per_repo} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPatternList = ["*"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_tagged_images_per_repo
        }
        action = { type = "expire" }
      }
    ]
  })
}
