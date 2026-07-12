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

    @staticmethod
    def _order_chance(
        market: str = "KRW-BTC",
        *,
        side: str = "bid",
        balance: str = "100000000",
        min_total: str = "5000",
    ) -> dict:
        quote_currency, base_currency = market.split("-", 1)
        return {
            "bid_account": {
                "currency": quote_currency,
                "balance": balance if side == "bid" else "100000000",
            },
            "ask_account": {
                "currency": base_currency,
                "balance": balance if side == "ask" else "100000000",
            },
            "market": {
                "id": market,
                "order_sides": ["ask", "bid"],
                "bid_types": ["limit", "price"],
                "ask_types": ["limit", "market"],
                "bid": {"currency": quote_currency, "min_total": min_total},
                "ask": {"currency": base_currency, "min_total": min_total},
            },
        }

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
                "_private_get",
                return_value=self._order_chance("KRW-BTC"),
            ) as private_get,
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

        private_get.assert_called_once_with(
            "/v1/orders/chance",
            params={"market": "KRW-BTC"},
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
                "_private_get",
                return_value=self._order_chance("KRW-BTC", side="ask"),
            ) as private_get,
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
        private_get.assert_called_once_with(
            "/v1/orders/chance",
            params={"market": "KRW-BTC"},
        )
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

    def test_tether_symbol_uses_krw_usdt_order_chance_and_test_endpoint(self) -> None:
        self._enable_trading()

        with (
            patch.object(service, "_client_order_id", return_value="client-usdt-id"),
            patch.object(
                service,
                "_private_get",
                return_value=self._order_chance("KRW-USDT", balance="20000"),
            ) as private_get,
            patch.object(
                service,
                "_private_post",
                return_value={
                    "uuid": "test-usdt-uuid",
                    "identifier": "client-usdt-id",
                    "market": "KRW-USDT",
                    "side": "bid",
                    "volume": "4",
                    "price": "1500",
                },
            ) as private_post,
        ):
            result = service.test_upbit_order(
                {
                    "symbol": "USDT",
                    "side": "BUY",
                    "orderType": "LIMIT",
                    "quantity": "4",
                    "price": "1500",
                },
                user_email="trader@example.com",
            )

        expected_payload = {
            "market": "KRW-USDT",
            "side": "bid",
            "volume": "4",
            "price": "1500",
            "ord_type": "limit",
            "identifier": "client-usdt-id",
        }
        private_get.assert_called_once_with(
            "/v1/orders/chance",
            params={"market": "KRW-USDT"},
        )
        private_post.assert_called_once_with("/v1/orders/test", payload=expected_payload)
        self.assertEqual(result["status"], "validated")
        self.assertEqual(result["symbol"], "KRW-USDT")

    def test_order_chance_rejects_under_min_total_before_order_test(self) -> None:
        self._enable_trading()

        with (
            patch.object(service, "_client_order_id", return_value="client-small-id"),
            patch.object(
                service,
                "_private_get",
                return_value=self._order_chance("KRW-USDT", min_total="5000"),
            ),
            patch.object(service, "_private_post") as private_post,
        ):
            with self.assertRaises(ValueError):
                service.test_upbit_order(
                    {
                        "symbol": "USDT",
                        "side": "BUY",
                        "orderType": "LIMIT",
                        "quantity": "1",
                        "price": "1500",
                    },
                    user_email="trader@example.com",
                )

        private_post.assert_not_called()

    def test_holdings_separate_available_and_locked_quantity(self) -> None:
        with patch.object(
            service,
            "_public_get",
            return_value=[{"market": "KRW-USDT", "trade_price": "1500"}],
        ):
            holdings = service._holdings(
                [
                    {
                        "currency": "USDT",
                        "unit_currency": "KRW",
                        "balance": "4.5",
                        "locked": "1.25",
                        "avg_buy_price": "1490",
                    }
                ],
                {"KRW-USDT": {"koreanName": "테더", "englishName": "Tether"}},
            )

        self.assertEqual(len(holdings), 1)
        self.assertEqual(holdings[0]["symbol"], "KRW-USDT")
        self.assertEqual(holdings[0]["quantity"], "5.75")
        self.assertEqual(holdings[0]["availableQuantity"], "4.5")
        self.assertEqual(holdings[0]["lockedQuantity"], "1.25")

    def test_private_dashboard_is_not_cached_between_balance_reads(self) -> None:
        self._enable_trading()
        service._clear_dashboard_cache()
        self.addCleanup(service._clear_dashboard_cache)
        account_balances = iter(["10000", "25000"])

        def public_get(path: str, *, params=None):
            if path == "/v1/ticker":
                return [
                    {
                        "market": "KRW-BTC",
                        "trade_price": 50000000,
                        "prev_closing_price": 49000000,
                        "signed_change_price": 1000000,
                        "signed_change_rate": 0.02,
                        "timestamp": 1700000000000,
                    }
                ]
            if path == "/v1/orderbook":
                return [{"market": "KRW-BTC", "orderbook_units": []}]
            return []

        def private_get(path: str, *, params=None):
            if path == "/v1/accounts":
                return [{"currency": "KRW", "balance": next(account_balances)}]
            return []

        with (
            patch.object(service, "_public_get", side_effect=public_get),
            patch.object(service, "_private_get", side_effect=private_get) as private,
            patch.object(service, "_load_candles", return_value=[]),
            patch.object(
                service,
                "_market_names",
                return_value={"KRW-BTC": {"koreanName": "비트코인"}},
            ),
        ):
            first = service.load_upbit_crypto_dashboard(
                symbol="KRW-BTC",
                symbols="KRW-BTC",
                user_email="trader@example.com",
            )
            second = service.load_upbit_crypto_dashboard(
                symbol="KRW-BTC",
                symbols="KRW-BTC",
                user_email="trader@example.com",
            )

        self.assertFalse(first["cached"])
        self.assertFalse(second["cached"])
        self.assertEqual(second["summary"]["buyingPowerKrw"], "25000")
        self.assertGreaterEqual(private.call_count, 2)


if __name__ == "__main__":
    unittest.main()
