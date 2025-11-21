# ===========================================
# Application Load Balancer
# ===========================================

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-alb"
  })
}

# ===========================================
# Target Groups - Blue/Green Deployment
# ===========================================

# Backend Blue Target Group (Production)
resource "aws_lb_target_group" "backend_blue" {
  name                 = "${var.name_prefix}-backend-blue-tg"
  port                 = var.backend_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-backend-blue-tg"
    Environment = "blue"
    Purpose     = "production"
  })
}

# Backend Green Target Group (Testing/Staging)
resource "aws_lb_target_group" "backend_green" {
  name                 = "${var.name_prefix}-backend-green-tg"
  port                 = var.backend_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-backend-green-tg"
    Environment = "green"
    Purpose     = "testing"
  })
}

# Frontend Blue Target Group (Production)
resource "aws_lb_target_group" "frontend_blue" {
  name                 = "${var.name_prefix}-frontend-blue-tg"
  port                 = var.frontend_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-frontend-blue-tg"
    Environment = "blue"
    Purpose     = "production"
  })
}

# Frontend Green Target Group (Testing/Staging)
resource "aws_lb_target_group" "frontend_green" {
  name                 = "${var.name_prefix}-frontend-green-tg"
  port                 = var.frontend_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-frontend-green-tg"
    Environment = "green"
    Purpose     = "testing"
  })
}

# ===========================================
# HTTP Listener - Redirects to HTTPS
# ===========================================

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

# ===========================================
# HTTPS Listener with Host-based Routing (Production)
# ===========================================

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = var.tags
}

# Backend routing rule (HTTPS) - Points to Blue by default
resource "aws_lb_listener_rule" "backend_https" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_blue.arn
  }

  condition {
    host_header {
      values = [var.backend_domain]
    }
  }

  tags = var.tags
}

# Frontend routing rule (HTTPS) - Points to Blue by default
resource "aws_lb_listener_rule" "frontend_https" {
  count = var.certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_blue.arn
  }

  condition {
    host_header {
      values = [var.frontend_domain]
    }
  }

  tags = var.tags
}
# ===========================================
# Testing Listeners for Green Deployment (HTTPS Only)
# ===========================================

# Backend HTTPS Test Listener (Port 18443) - Points to Backend Green
resource "aws_lb_listener" "backend_https_test" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 18443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_green.arn
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-backend-https-test-listener"
    Environment = "green"
    Purpose     = "testing"
    Service     = "backend"
  })
}

# Frontend HTTPS Test Listener (Port 13443) - Points to Frontend Green
resource "aws_lb_listener" "frontend_https_test" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 13443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_green.arn
  }

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-frontend-https-test-listener"
    Environment = "green"
    Purpose     = "testing"
    Service     = "frontend"
  })
}

