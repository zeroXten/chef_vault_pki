# chef\_vault\_pki cookbook

Uses chef\_vault to provide an easy to manage PKI for Chef managed servers.

Instead of having to manage and secure a CA, chef\vault\_pki lets you create a CA cert and key using the provided script which is then stored using chef\_vault. Authorised clients can then obtain the CA cert and key, and automatically generate their certificates.

# Requirements

* check\_vault

# Usage

## Creating a CA

Install the chef\_vault\_pki on your workstation.

    $ gem install chef_vault_pki

Running the `chef_vault_pki` will generate a CA certificate and key and will output the PEMs as JSON by default. We pass this directly to chef-vault to create an encrypted data bag.

    $ chef_vault_pki | knife vault create chef_vault_pki chef_vault_pki_ca -J /dev/stdin --search 'role:base' --admins zeroxten-lazy-pki

We can see chef-vault created the data bag as required.

    $ ls data_bags/chef_vault_pki/
    chef_vault_pki_ca.json    chef_vault_pki_ca_keys.json

## Using chef\_vault\_pki in a recipe

Add this to your cookbook's metadata.rb

    depends 'chef_vault_pki'

Basic usage will use defaults set in attributes:

    chef_vault_pki node.name

Or you can make it a little more specifc:

    chef_vault_pki "sensu_#{node.name}"

Or even override the default attributes:

    chef_vault_pki "sensu_#{node.name}" do
      ca 'sensu_ca'
      path '/opt/ssl'
      owner 'sensu'
      group 'sensu'
      public_mode 0644
      private_mode 0600
    end

This final example will create three files in `/opt/ssl`:

* `sensu_NODENAME.crt` (uses public\_mode)
* `sensu_NODENAME.key` (uses private\_mode)
* `sensu_ca.crt` (uses public\_mode)

These files can then be used by applications requiring a TLS PKI.

You can get the certificates of other nodes using a search. E.g. for the above sensu\_ca client we might have:

    certs = search(:node, "name:*").first['chef_vault_pki']['certs']['sensu_ca']

# Security

This approach to managing a PKI isn't suitable for all cases. The generate CA private key is basically treated as a shared key or password between all authorised (through chef-vault) clients.

It is assumes you trust all clients and the workstation that created the CA. It also assumes you trust chef-vault.

Because it treats the CA key as a shared key, you cannot revoke a certificate in the tradiitonal sense. In the same way that a shared password compromise requires the password to be changed everywhere, so it is with chef\_vault\_pki. However, updating the CA key is as simple as re-creating the databag using the `chef_vault_pki` and chef-vault commands as above. All nodes will automatically detect the CA has changed and will generate new certificates during the next run.

# Attributes

See `attributes/default.rb` for defaults.

* `node['chef_vault_pki']['data_bag']` - name of the chef\_vault data bag
* `node['chef_vault_pki']['ca_name']` - name of CA
* `node['chef_vault_pki']['path']` - where the generated certs etc go
* `node['chef_vault_pki']['user']` - cert and key file user
* `node['chef_vault_pki']['group']` - cert and key file group

Generated client certs are added to the node attributes:

* `node['chef_vault_pki']['certs'][CA_NAME][CERT_NAME] = CERT`

# Recipes

* `chef_vault_pki::default`

# Author

