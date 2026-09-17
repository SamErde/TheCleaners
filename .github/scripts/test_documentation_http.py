import unittest
from unittest import mock

import documentation_http


class DocumentationHttpTests(unittest.TestCase):
    def test_non_http_and_remote_http_schemes_are_rejected_before_transport(self):
        with mock.patch.object(documentation_http.http.client, "HTTPConnection") as http:
            with mock.patch.object(
                documentation_http.http.client, "HTTPSConnection"
            ) as https:
                for url in (
                    "file://localhost/",
                    "ftp://localhost/",
                    "http://example.com/",
                ):
                    with self.subTest(url=url):
                        with self.assertRaisesRegex(
                            documentation_http.HttpTransportError,
                            "URL must use HTTPS",
                        ):
                            documentation_http.read_http_response(url, 0, 1)
                http.assert_not_called()
                https.assert_not_called()


if __name__ == "__main__":
    unittest.main()
