terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.6.0"
    }
  }
  required_version = "> 0.14"



provider "aws" {
  region = var.aws_region
}

resource "aws_iam_user" "circleci" {
  name = var.user
  path = "/system/"
}

resource "aws_iam_access_key" "circleci" {
  user = aws_iam_user.circleci.name
}

data "template_file" "circleci_policy" {
  template = file("circleci_s3_access.tpl.json")
  vars = {
    s3_bucket_arn = aws_s3_bucket.app.arn
  }
}

resource "local_file" "circle_credentials" {
  filename = "tmp/circleci_credentials"
  content  = "${aws_iam_access_key.circleci.id}\n${aws_iam_access_key.circleci.secret}"
}


data "aws_acm_certificate" "cert" {
  domain = "*.${var.domain}"
}


# Note: The bucket name needs to carry the same name as the domain!
# http://stackoverflow.com/a/5048129/2966951
resource "aws_s3_bucket" "site" {
  bucket = "${var.subdomain}_${var.domain}"

  tags = {
    site = "${var.subdomain}.${var.domain}"
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "PublicReadForGetBucketObjects",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource":["arn:aws:s3:::${var.subdomain}_${var.domain}/*"]
        }
    ]
}
EOF

}

resource "aws_s3_bucket_acl" "site" {
  bucket = aws_s3_bucket.site.id
  acl = "public-read"
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  index_document {
      suffix = "index.html"
  }
}


resource "aws_s3_bucket_accelerate_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  status = "Enabled"



}

data "aws_route53_zone" "main" {
  name         = "${var.domain}"
  private_zone = false
}


resource "aws_route53_record" "root_domain" {
  zone_id = "${data.aws_route53_zone.main.zone_id}"
  name = "${var.subdomain}.${var.domain}"
  type = "A"

  alias {
    name = "${aws_cloudfront_distribution.cdn.domain_name}"
    zone_id = "${aws_cloudfront_distribution.cdn.hosted_zone_id}"
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    origin_id   = "${var.subdomain}.${var.domain}"
    domain_name = "${var.subdomain}.${var.domain}.s3.amazonaws.com"
  }

  tags = {
    site = "${var.subdomain}.${var.domain}"
  }


  # If using route53 aliases for DNS we need to declare it here too, otherwise we'll get 403s.
  aliases = ["${var.subdomain}.${var.domain}"]

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${var.subdomain}.${var.domain}"

    forwarded_values {
      query_string = true
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # The cheapest priceclass
  price_class = "PriceClass_100"

  # This is required to be specified even if it's not used.
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
      acm_certificate_arn = "${data.aws_acm_certificate.cert.arn}"
      ssl_support_method ="sni-only"
  }
}

output "s3_website_endpoint" {
  value = "${aws_s3_bucket.site.website_endpoint}"
}



