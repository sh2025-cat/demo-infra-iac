# ECS Native Blue/Green 배포 가이드

ECS의 Native Blue/Green 배포 전략을 사용한 무중단 배포 가이드입니다.

> **Note**: 이 기능은 2024년 7월에 추가된 ECS 신기능으로, CodeDeploy 없이 ECS만으로 Blue/Green 배포가 가능합니다.

## 개요

### Blue/Green 배포란?

두 개의 동일한 프로덕션 환경(Blue, Green)을 유지하면서, 새 버전을 Green 환경에 먼저 배포하고 테스트한 후 트래픽을 전환하는 배포 전략입니다.

```
┌─────────────────────────────────────────────────────────────┐
│                        ALB                                   │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │   Production (443)  │    │   Test (13443)      │         │
│  │   실제 사용자 트래픽   │    │   개발자 테스트용    │         │
│  └──────────┬──────────┘    └──────────┬──────────┘         │
│             │                          │                     │
│             ▼                          ▼                     │
│  ┌─────────────────────┐    ┌─────────────────────┐         │
│  │  Blue Target Group  │    │ Green Target Group  │         │
│  │    (현재 버전)       │    │    (새 버전)        │         │
│  │    v1.0.0           │    │    v1.1.0           │         │
│  └─────────────────────┘    └─────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## 현재 인프라 구성

### 리스너 포트 구성

| 포트 | 프로토콜 | 용도 | Target Group |
|------|----------|------|--------------|
| 443 | HTTPS | Production 트래픽 | Blue (기본) |
| 13443 | HTTPS | Frontend Green 테스트 | Frontend Green |
| 18443 | HTTPS | Backend Green 테스트 | Backend Green |

### Target Group 구성

| 서비스 | Blue Target Group | Green Target Group |
|--------|-------------------|-------------------|
| Frontend | `cat-demo-frontend-blue-tg` | `cat-demo-frontend-green-tg` |
| Backend | `cat-demo-backend-blue-tg` | `cat-demo-backend-green-tg` |

## 배포 프로세스

### 1단계: 새 Task Definition 등록

```bash
# 새 이미지 태그로 Task Definition 등록
aws ecs register-task-definition \
  --cli-input-json file://frontend-task-definition.json
```

### 2단계: 서비스 업데이트 (Blue/Green 배포 시작)

```bash
aws ecs update-service \
  --cluster cat-demo-cluster \
  --service cat-demo-frontend-service \
  --task-definition cat-demo-frontend:NEW_REVISION \
  --force-new-deployment \
  --load-balancers '[{
    "targetGroupArn": "arn:aws:elasticloadbalancing:ap-northeast-2:277679348386:targetgroup/cat-demo-frontend-blue-tg/79f926479c3a0186",
    "containerName": "frontend",
    "containerPort": 3000,
    "advancedConfiguration": {
      "alternateTargetGroupArn": "arn:aws:elasticloadbalancing:ap-northeast-2:277679348386:targetgroup/cat-demo-frontend-green-tg/99c8a922530d6af0",
      "productionListenerRule": "arn:aws:elasticloadbalancing:ap-northeast-2:277679348386:listener-rule/app/cat-demo-alb/9d92f958ad5f6db9/00f482150be68d6c/121a8e6d10b0ab5c",
      "testListenerRule": "arn:aws:elasticloadbalancing:ap-northeast-2:277679348386:listener-rule/app/cat-demo-alb/9d92f958ad5f6db9/e9129bebebc2ac6b/0fc99dd96ef78198",
      "roleArn": "arn:aws:iam::277679348386:role/cat-demo-cluster-service-role"
    }
  }]'
```

### 3단계: Green 환경 테스트

새 버전이 Green Target Group에 배포되면 테스트 포트로 접근하여 검증합니다.

```bash
# Frontend Green 테스트
curl -k https://board.go-to-learn.net:13443/

# Backend Green 테스트
curl -k https://api-board.go-to-learn.net:18443/
```

### 4단계: Bake Time 및 자동 전환

- 테스트 통과 후 **Bake Time (10분)** 동안 모니터링
- 문제가 없으면 자동으로 Production(443) 트래픽이 Green으로 전환
- 기존 Blue 태스크는 정리됨

### 5단계: 롤백 (필요시)

문제 발생 시 즉시 롤백 가능:

```bash
# 이전 Task Definition으로 롤백
aws ecs update-service \
  --cluster cat-demo-cluster \
  --service cat-demo-frontend-service \
  --task-definition cat-demo-frontend:PREVIOUS_REVISION \
  --force-new-deployment
```

## 배포 상태 확인

### 서비스 상태 확인

```bash
aws ecs describe-services \
  --cluster cat-demo-cluster \
  --services cat-demo-frontend-service \
  --query 'services[0].{
    ServiceName:serviceName,
    TaskDefinition:taskDefinition,
    RunningCount:runningCount,
    DesiredCount:desiredCount,
    Deployments:deployments[*].{
      Status:status,
      RolloutState:rolloutState,
      TaskDef:taskDefinition
    }
  }'
```

### Target Group 헬스 체크

```bash
# Blue Target Group
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-2:277679348386:targetgroup/cat-demo-frontend-blue-tg/79f926479c3a0186

# Green Target Group
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-2:277679348386:targetgroup/cat-demo-frontend-green-tg/99c8a922530d6af0
```

### 최근 이벤트 확인

```bash
aws ecs describe-services \
  --cluster cat-demo-cluster \
  --services cat-demo-frontend-service \
  --query 'services[0].events[0:5]'
```

## 서비스 설정 (deploymentConfiguration)

```json
{
  "deploymentConfiguration": {
    "deploymentCircuitBreaker": {
      "enable": true,
      "rollback": true
    },
    "maximumPercent": 200,
    "minimumHealthyPercent": 100,
    "strategy": "BLUE_GREEN",
    "bakeTimeInMinutes": 10
  }
}
```

| 설정 | 값 | 설명 |
|------|-----|------|
| `strategy` | `BLUE_GREEN` | Blue/Green 배포 전략 사용 |
| `bakeTimeInMinutes` | `10` | 트래픽 전환 전 대기 시간 |
| `deploymentCircuitBreaker.enable` | `true` | 실패 시 자동 롤백 |
| `deploymentCircuitBreaker.rollback` | `true` | 롤백 활성화 |

## 필요한 IAM 권한

ECS Service Role에 다음 권한이 필요합니다:

```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:DeregisterTargets",
    "elasticloadbalancing:Describe*",
    "elasticloadbalancing:RegisterTargets",
    "elasticloadbalancing:ModifyListener",
    "elasticloadbalancing:ModifyRule",
    "elasticloadbalancing:ModifyTargetGroup",
    "elasticloadbalancing:ModifyTargetGroupAttributes",
    "elasticloadbalancing:SetRulePriorities"
  ],
  "Resource": "*"
}
```

## 다른 배포 전략과 비교

| 전략 | 장점 | 단점 | 사용 케이스 |
|------|------|------|------------|
| **ECS Native Blue/Green** | CodeDeploy 불필요, 테스트 포트 제공 | 트래픽 비율 조절 불가 | 사전 테스트가 중요한 경우 |
| **CodeDeploy Blue/Green** | 트래픽 비율 조절, Canary 배포 | 설정 복잡 | 점진적 트래픽 전환 필요 시 |
| **Rolling Update** | 간단, 빠름 | 롤백 느림, 혼합 버전 | 간단한 업데이트 |

## 트러블슈팅

### 배포 실패: ModifyListener 권한 없음

```
User is not authorized to perform: elasticloadbalancing:ModifyListener
```

**해결**: ECS Service Role에 `elasticloadbalancing:ModifyListener` 권한 추가

### 배포 실패: advancedConfiguration 필수

```
advancedConfiguration field is required for all loadBalancers when using Blue/green deployment strategy
```

**해결**: `update-service` 호출 시 `advancedConfiguration` 포함

### Health Check 실패

```bash
# Target Group 헬스 상태 확인
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
```

**확인 사항**:
- 컨테이너 포트가 맞는지
- Health check 경로가 200을 반환하는지
- Security Group에서 포트가 열려있는지

## 참고 자료

- [AWS ECS Blue/Green Deployments](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html)
- [ECS Deployment Configuration](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DeploymentConfiguration.html)
