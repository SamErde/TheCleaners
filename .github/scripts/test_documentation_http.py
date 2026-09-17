import unittest
from unittest import mock

import documentation_http


class DocumentationHttpTests(unittest.TestCase):
    def test_non_http_and_remote_http_schemes_are_rejected_before_transport(self):
        with mock.patch.object(documentation_http.http.client, "HTTPConnection") as http:
            with mock.patch.object(
                documentation_http.http.client, "HTTPSConnection"
            ) as https:
                for url, maximum_body_bytes, expected_error in (
                    ("file://localhost/", 0, "URL must use HTTPS"),
                    ("ftp://localhost/", 0, "URL must use HTTPS"),
                    ("http://example.com/", 0, "URL must use HTTPS"),
                    ("http://localhost/", -1, "non-negative integer"),
                    ("http://localhost/", "1", "non-negative integer"),
                ):
                    with self.subTest(url=url, maximum_body_bytes=maximum_body_bytes):
                        with self.assertRaisesRegex(
                            documentation_http.HttpTransportError,
                            expected_error,
                        ):
                            documentation_http.read_http_response(
                                url,
                                maximum_body_bytes,
                                1,
                            )
                http.assert_not_called()
                https.assert_not_called()

    def test_response_read_is_bounded_and_resources_are_closed(self):
        with mock.patch.object(
            documentation_http.http.client, "HTTPConnection"
        ) as connection_type:
            connection = connection_type.return_value
            response = connection.getresponse.return_value
            response.status = 200
            response.read.return_value = b"ab"

            status, body = documentation_http.read_http_response(
                "http://localhost/content",
                1,
                2,
            )

            self.assertEqual((status, body), (200, b"ab"))
            response.read.assert_called_once_with(2)
            response.close.assert_called_once_with()
            connection.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
