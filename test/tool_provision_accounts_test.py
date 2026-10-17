import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('provision', Path(__file__).parents[1] / 'tool/provision_consultation_accounts.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProvisionTest(unittest.TestCase):
    def test_plan_does_not_send_requests(self):
        def never(_):
            self.fail('network should not be called')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(module.run({'SUPABASE_URL': 'https://example.test'}, {}, request=never), 0)

    def test_preserves_existing_accounts_and_creates_only_approved_missing(self):
        sent = []
        def request(req):
            sent.append(req)
            if req.data is None:
                return {'users': [{'email': 'cinthiadutra@gmail.com', 'email_confirmed_at': 'confirmed'}, {'email': 'claudia@example.com'}]}
            return {'id': 'created'}
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = module.run({'SUPABASE_URL': 'https://example.test'}, {'SUPABASE_SECRET_KEY': 'server-test-secret', 'CONSULTAS_CCU_PASSWORD': 'transient-ccu', 'CONSULTAS_CPO_PASSWORD': 'transient-cpo'}, True, request)
        self.assertEqual(code, 0)
        posts = [json.loads(req.data) for req in sent if req.data is not None]
        self.assertEqual(len(posts), 4)
        self.assertEqual({p['email'] for p in posts}, {a[0] for a in module.ACCOUNTS[:-1]})
        self.assertTrue(all(p['email_confirm'] for p in posts))
        self.assertFalse(any('role' in p['user_metadata'] for p in posts))
        for secret in ['transient-ccu', 'transient-cpo', 'server-test-secret']:
            self.assertNotIn(secret, output.getvalue())

    def test_publishable_key_cannot_provision(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(module.run({'SUPABASE_URL': 'https://example.test'}, {'SUPABASE_SECRET_KEY': 'sb_publishable_public'}, True), 1)


if __name__ == '__main__':
    unittest.main()
