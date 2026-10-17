"""Sonda somente leitura; nunca imprime chaves ou tokens."""
import json
import sys
import urllib.error
import urllib.request

with open(sys.argv[1] if len(sys.argv) > 1 else 'config/supabase.json') as config_file:
    config = json.load(config_file)
for path in ['/auth/v1/settings', '/rest/v1/phalanxes?select=id&limit=1']:
    request = urllib.request.Request(config['SUPABASE_URL'] + path,
                                    headers={'apikey': config['SUPABASE_PUBLISHABLE_KEY']})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            print(path, 'HTTP', response.status)
    except urllib.error.HTTPError as error:
        result = json.load(error)
        print(path, 'HTTP', error.code, result.get('code', ''), result.get('message', result.get('msg', '')))
    except urllib.error.URLError:
        print(path, 'Servidor inacessível (rede ou DNS).')
        sys.exit(1)
