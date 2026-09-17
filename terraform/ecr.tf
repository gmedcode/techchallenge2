# ECR repository — stores the Docker image for our Flask app.
# Jenkins (and, right now, us manually) will push built images here,
# and Kubernetes pulls from here when creating pods.
resource "aws_ecr_repository" "flask_app" {
  name                 = "flask-hello-world"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "ecr_repository_url" {
  value = aws_ecr_repository.flask_app.repository_url
}
