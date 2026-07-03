from __future__ import annotations

from dataclasses import replace
import hashlib
import unittest
from unittest.mock import call, patch

import jwt

from app import upbit_service as service


class UpbitOrderServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        self._original_settings = service.settings
        self.addCleanup(self._restore_settings)

    def _restore_settings(self) -> None:
        service.settings = self._original_settings

    def _enable_trading(self) -> None:
        service.settings = replace(
            service.settings,
            upbit_access_key="test-access-key",
            upbit_secret_key="s" * 64,
            upbit_trading_enabled=True,
            upbit_trading_allowed_emails=["trader@example.com"],
        )

    def test_limit_buy_payload_normalizes_symbol_and_side(self) -> None:
        with patch.object(service, "_client_order_id", return_value="kang-upbit-test"):
            payload = service._order_create_payload(
                {
                    "symbol": "btc",
                    "side": "BUY",
                    "orderType": "LIMIT",
                    "quantity": "0.0001",
                    "price": "50000000",
                }
            )

        self.assertEqual(
            payload,
            {
                "market": "KRW-BTC",
                "side": "bid",
                "volume": "0.0001",
                "price": "50000000",
                "ord_type": "limit",
                "identifier": "kang-upbit-test",
            },
        )

    def test_jwt_query_hash_uses_unquoted_query_string(self) -> None:
        self._enable_trading()
        expected_query = "market=KRW-BTC&states[]=wait&states[]=watch"

        token = service._jwt_token(
            {"market": "KRW-BTC", "states[]": ["wait", "watch"]}
        )
        decoded = jwt.decode(
            token,
            service.settings.upbit_secret_key,
            algorithms=["HS512"],
        )

        self.assertEqual(
            decoded["query_hash"],
            hashlib.sha512(expected_query.encode("utf-8")).hexdigest(),
        )
        self.assertEqual(decoded["query_hash_alg"], "SHA512")

    def test_trading_gate_requires_enabled_allowed_email_and_keys(self) -> None:
        service.settings = replace(
            service.settings,
            upbit_access_key="test-access-key",
            upbit_secret_key="s" * 64,
            upbit_trading_enabled=False,
            upbit_trading_allowed_emails=["trader@example.com"],
        )

        with self.assertRaises(PermissionError):
            service._ensure_trading_allowed("trader@example.com")

        self._enable_trading()
        service._ensure_trading_allowed("TRADER@example.com")

        with self.assertRaises(PermissionError):
            service._ensure_trading_allowed("other@example.com")

    def test_test_order_uses_upbit_order_test_endpoint(self) -> None:
        self._enable_trading()

        with (
            patch.object(service, "_client_order_id", return_value="client-test-id"),
            patch.object(
                service,
                "_private_post",
                return_value={
                    "uuid": "test-uuid",
                    "identifier": "client-test-id",
                    "market": "KRW-BTC",
                    "side": "bid",
                    "volume": "0.0001",
                    "price": "50000000",
                },
            ) as private_post,
        ):
            result = service.test_upbit_order(
                {
                    "symbol": "KRW-BTC",
                    "side": "BUY",
                    "orderType": "LIMIT",
                    "quantity": "0.0001",
                    "price": "50000000",
                },
                user_email="trader@example.com",
            )

        private_post.assert_called_once_with(
            "/v1/orders/test",
            payload={
                "market": "KRW-BTC",
                "side": "bid",
                "volume": "0.0001",
                "price": "50000000",
                "ord_type": "limit",
                "identifier": "client-test-id",
            },
        )
        self.assertEqual(result["status"], "validated")
        self.assertEqual(result["symbol"], "KRW-BTC")
        self.assertEqual(result["side"], "BUY")

    def test_create_order_uses_real_upbit_order_endpoint(self) -> None:
        self._enable_trading()

        with (
            patch.object(service, "_client_order_id", return_value="client-real-id"),
            patch.object(
                service,
                "_private_post",
                side_effect=[
                    {
                        "uuid": "preflight-uuid",
                        "identifier": "client-real-id",
                        "market": "KRW-BTC",
                        "side": "ask",
                        "volume": "0.0001",
                        "price": "70000000",
                    },
                    {
                        "uuid": "real-uuid",
                        "identifier": "client-real-id",
                        "market": "KRW-BTC",
                        "side": "ask",
                        "volume": "0.0001",
                        "price": "70000000",
                    },
                ],
            ) as private_post,
            patch.object(service, "_clear_dashboard_cache") as clear_cache,
        ):
            result = service.create_upbit_order(
                {
                    "symbol": "BTC",
                    "side": "SELL",
                    "orderType": "LIMIT",
                    "quantity": "0.0001",
                    "price": "70000000",
                },
                user_email="trader@example.com",
            )

        expected_payload = {
            "market": "KRW-BTC",
            "side": "ask",
            "volume": "0.0001",
            "price": "70000000",
            "ord_type": "limit",
            "identifier": "client-real-id",
        }
        private_post.assert_has_calls(
            [
                call("/v1/orders/test", payload=expected_payload),
                call("/v1/orders", payload=expected_payload),
            ]
        )
        self.assertEqual(result["status"], "accepted")
        self.assertEqual(result["orderId"], "real-uuid")
        self.assertEqual(result["side"], "SELL")
        clear_cache.assert_called_once()


if __name__ == "__main__":
    unittest.main()
