아import json
import urllib.request
import urllib.error
import ssl
import os
import time

def lambda_handler(event, context):
    """
    ECS Blue/Green POST_TEST_TRAFFIC_SHIFT 검증 Lambda

    Backend /api/health 엔드포인트를 검증합니다.
    검증 실패 시 Exception을 발생시켜 ECS 롤백을 트리거합니다.
    """
    print(f"Event: {json.dumps(event)}")

    # 환경변수 또는 기본값
    backend_url = os.environ.get('BACKEND_URL', 'https://api-board.go-to-learn.net')
    test_port = os.environ.get('TEST_PORT', '18443')

    # URL 정리 (trailing slash 제거)
    backend_url = backend_url.rstrip('/')

    # 테스트 URL
    health_url = f"{backend_url}:{test_port}/api/health"

    print(f"Checking health at: {health_url}")

    results = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'url': health_url,
        'status': 'PASS'
    }

    # SSL 검증 무시 (테스트 환경)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(
            health_url,
            headers={'User-Agent': 'ECS-BlueGreen-Validator/1.0'}
        )

        with urllib.request.urlopen(req, timeout=10, context=ctx) as response:
            status_code = response.getcode()
            body = response.read().decode('utf-8')

            results['response_status'] = status_code
            results['response_body'] = body[:500]  # 최대 500자

            # Health Check 검증
            if status_code != 200:
                results['status'] = 'FAIL'
                results['error'] = f'Expected 200, got {status_code}'
                print(f"VALIDATION FAILED: {json.dumps(results)}")
                raise Exception(f"Health check failed: HTTP {status_code}")

            # "UP" 상태 확인
            if 'UP' not in body:
                results['status'] = 'FAIL'
                results['error'] = 'Health status is not UP'
                print(f"VALIDATION FAILED: {json.dumps(results)}")
                raise Exception("Health check failed: Status is not UP")

            results['message'] = 'Health check passed'
            print(f"VALIDATION PASSED: {json.dumps(results)}")

            return {
                'statusCode': 200,
                'body': json.dumps(results)
            }

    except urllib.error.HTTPError as e:
        results['status'] = 'FAIL'
        results['error'] = f'HTTP Error: {e.code}'
        print(f"VALIDATION FAILED: {json.dumps(results)}")
        raise Exception(f"Health check failed: HTTP {e.code}")

    except urllib.error.URLError as e:
        results['status'] = 'FAIL'
        results['error'] = f'Connection Error: {e.reason}'
        print(f"VALIDATION FAILED: {json.dumps(results)}")
        raise Exception(f"Health check failed: {e.reason}")

    except Exception as e:
        if 'Health check failed' in str(e):
            raise
        results['status'] = 'FAIL'
        results['error'] = str(e)
        print(f"VALIDATION FAILED: {json.dumps(results)}")
        raise Exception(f"Health check failed: {str(e)}")
