from __future__ import annotations

import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app


class UpbitApiIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def test_upbit_routes_require_firebase_bearer_token(self) -> None:
        response = self.client.post(
            "/upbit/orders/test",
            json={
                "symbol": "KRW-BTC",
                "side": "BUY",
                "orderType": "LIMIT",
                "quantity": "0.0001",
                "price": "50000000",
            },
        )

        self.assertEqual(response.status_code, 401)

    def test_order_test_route_passes_authenticated_email_to_service(self) -> None:
        service_response = {
            "status": "validated",
            "orderId": "test-uuid",
            "clientOrderId": "client-test",
            "symbol": "KRW-BTC",
            "side": "BUY",
            "orderType": "LIMIT",
            "quantity": "0.0001",
            "price": "50000000",
            "timeInForce": "DAY",
            "message": "업비트 주문 테스트를 통과했습니다.",
        }

        with (
            patch(
                "app.main.verify_firebase_id_token",
                return_value={"email": "trader@example.com"},
            ),
            patch("app.main.test_upbit_order", return_value=service_response) as service,
        ):
            response = self.client.post(
                "/upbit/orders/test",
                headers={"Authorization": "Bearer firebase-token"},
                json={
                    "symbol": "KRW-BTC",
                    "side": "BUY",
                    "orderType": "LIMIT",
                    "quantity": "0.0001",
                    "price": "50000000",
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "validated")
        service.assert_called_once()
        self.assertEqual(service.call_args.kwargs["user_email"], "trader@example.com")
        self.assertEqual(service.call_args.args[0]["symbol"], "KRW-BTC")

    def test_real_order_route_passes_authenticated_email_to_service(self) -> None:
        service_response = {
            "status": "accepted",
            "orderId": "real-uuid",
            "clientOrderId": "client-real",
            "symbol": "KRW-BTC",
            "side": "SELL",
            "orderType": "LIMIT",
            "quantity": "0.0001",
            "price": "70000000",
            "timeInForce": "DAY",
            "message": "업비트 주문이 접수되었습니다.",
        }

        with (
            patch(
                "app.main.verify_firebase_id_token",
                return_value={"email": "trader@example.com"},
            ),
            patch("app.main.create_upbit_order", return_value=service_response) as service,
        ):
            response = self.client.post(
                "/upbit/orders",
                headers={"Authorization": "Bearer firebase-token"},
                json={
                    "symbol": "KRW-BTC",
                    "side": "SELL",
                    "orderType": "LIMIT",
                    "quantity": "0.0001",
                    "price": "70000000",
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "accepted")
        service.assert_called_once()
        self.assertEqual(service.call_args.kwargs["user_email"], "trader@example.com")
        self.assertEqual(service.call_args.args[0]["side"], "SELL")


if __name__ == "__main__":
    unittest.main()
