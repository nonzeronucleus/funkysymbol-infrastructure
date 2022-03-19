provider "aws" {
  region = var.aws_region
}

data "aws_acm_certificate" "cert" {
  domain = "*.${var.domain}"
}


# Note: The bucket name needs to carry the same name as the domain!
# http://stackoverflow.com/a/5048129/2966951
resource "aws_s3_bucket" "site" {
  bucket = "${var.subdomain}.${var.domain}"
  acl = "public-read"
  tags = {
    site = "${var.subdomain}.${var.domain}"
  }


  policy = <<EOF
{
    "Version": "2008-10-17",
    "Statement": [
        {
            "Sid": "PublicReadForGetBucketObjects",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource":["arn:aws:s3:::${var.subdomain}.${var.domain}/*"]
        }
    ]
}
EOF

  website {
      index_document = "index.html"
  }
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



