name             'chef_vault_pki'
maintainer       'Fraser Scott'
maintainer_email 'fraser.scott@gmail.com'
license          'MIT'
description      'Uses chef-vault to provide an easy-to-manage Public Key Infrastructure (PKI) for servers managed by Chef.'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '1.0.1'

depends 'sensu_spec', '~> 0.2'
