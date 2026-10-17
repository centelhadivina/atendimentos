"""Provisionamento administrativo opcional. Plano por padrão; nunca mostra senhas/tokens."""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

ACCOUNTS = [
    ('ccu.acentelhadivina@gmail.com', 'Cambono CCU', 'CONSULTAS_CCU_PASSWORD'),
    ('tecnologia.ccu@gmail.com', 'Tablet CCU', 'CONSULTAS_CCU_PASSWORD'),
    ('cpo.acentelhadivina@gmail.com', 'Cambono CPO', 'CONSULTAS_CPO_PASSWORD'),
    ('tecnologia.cpo@outlook.com', 'Tablet CPO', 'CONSULTAS_CPO_PASSWORD'),
    ('cinthiadutra@gmail.com', 'Cinthia Dutra', 'CONSULTAS_MASTER_PASSWORD'),
]


def run(config, env, apply=False, request=None):
    if not apply:
        for email, _, _ in ACCOUNTS:
            print('Reutilizar se existir; criar somente se ausente:', email)
        return 0
    key = env.get('SUPABASE_SECRET_KEY', '')
    if not key or key.startswith('sb_publishable_'):
        print('Defina SUPABASE_SECRET_KEY somente no ambiente administrativo local.')
        return 1
    base = config['SUPABASE_URL'].rstrip('/')

    def call(path, data=None):
        headers = {'apikey': key, 'Authorization': 'Bearer ' + key,
                   'Content-Type': 'application/json'}
        req = urllib.request.Request(base + '/auth/v1/admin/' + path,
                                     data=None if data is None else json.dumps(data).encode(),
                                     headers=headers)
        if request is not None:
            return request(req)
        with urllib.request.urlopen(req, timeout=20) as response:
            return json.load(response)

    try:
        users = {}
        page = 1
        while True:
            result = call('users?page=%s&per_page=1000' % page)
            batch = result.get('users', [])
            for user in batch:
                users[user.get('email', '').strip().lower()] = user
            if len(batch) < 1000:
                break
            page += 1
        missing_password = False
        for email, name, variable in ACCOUNTS:
            if email in users:
                print('Conta já existe; senha e cadastro Auth preservados:', email)
                if not users[email].get('email_confirmed_at'):
                    print('Confirmação de email ainda necessária:', email)
                continue
            password = env.get(variable)
            if not password or password.startswith('SUBSTITUIR'):
                print('Não criada; configure %s no ambiente ou crie pelo Dashboard: %s' % (variable, email))
                missing_password = True
                continue
            # Admin create, com confirmação explícita: não manda convite/email.
            call('users', {'email': email, 'password': password,
                           'email_confirm': True, 'user_metadata': {'name': name}})
            print('Conta criada no Auth:', email)
        return 1 if missing_password else 0
    except urllib.error.HTTPError as error:
        print('Provisionamento interrompido: HTTP', error.code)
        return 1
    except (urllib.error.URLError, TimeoutError):
        print('Provisionamento interrompido por falha de conexão.')
        return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--config', default='config/supabase.json')
    parser.add_argument('--env-file', help='Arquivo local de secrets, ignorado pelo Git')
    args = parser.parse_args()
    env = dict(os.environ)
    if args.env_file:
        with open(args.env_file, encoding='utf-8') as secrets_file:
            for line in secrets_file:
                line = line.strip()
                if line and not line.startswith('#'):
                    name, value = line.split('=', 1)
                    env.setdefault(name.strip(), value.strip())
    with open(args.config, encoding='utf-8') as config_file:
        config = json.load(config_file)
    return run(config, env, args.apply)


if __name__ == '__main__':
    sys.exit(main())
