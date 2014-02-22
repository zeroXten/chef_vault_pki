# chef\_vault\_pki cookbook

Uses chef-vault to provide an easy-to-manage Public Key Infrastructure (PKI) for servers managed by Chef.

Instead of having to manage and secure a CA, chef\_vault\_pki lets you generate a CA cert and key which is then stored and secured using chef-vault. Authorised clients can then obtain the CA cert and key, and automatically generate and sign their certificates.

# Requirements

Depends on [chef-vault](http://community.opscode.com/cookbooks/chef-vault) and [sensu\_spec](http://community.opscode.com/cookbooks/sensu_spec) cookbooks.

# Usage

## Creating a CA

Install the [chef-vault-pki](https://github.com/zeroXten/chef-vault-pki) command on your workstation.

Run this in the cookbook:

    $ bundle install

Or install the gem yourself:

    $ gem install chef-vault-pki

Running chef-vault-pki will generate a CA certificate and key, and will output the PEMs as JSON by default. We pass this directly to chef-vault to create an encrypted data bag.

    $ chef-vault-pki | knife vault create chef_vault_pki chef_vault_pki_ca -J /dev/stdin --search 'role:base' --admins admin-user

We can see chef-vault created the data bag as required.

    $ ls data_bags/chef_vault_pki/
    chef_vault_pki_ca.json    chef_vault_pki_ca_keys.json

See the chef-vault documentation for more information on managing data bags encrypted with chef-vault.

## Using chef\_vault\_pki in a recipe

chef\_vault\_pki provides an LWRP that can be used your cookbooks. To use it, add this to your cookbook's metadata.rb

    depends 'chef_vault_pki'

Then install with `berks install`.

Basic usage will use the defaults set in attributes (see below):

    chef_vault_pki node.name

Note that the name automatically has spaces converted to underscores (\_).

You might need make things a little more specifc:

    chef_vault_pki "sensu_#{node.name}"

Or even override the default attributes:

    chef_vault_pki "sensu_#{node.name}" do
      ca 'sensu_ca'
      path '/opt/chef_vault_pki'
      owner 'sensu'
      group 'sensu'
      public_mode 0644
      private_mode 0600
    end

This final example will create three files in `/opt/chef_vault_pki`:

* `sensu_NODENAME.crt` (uses public\_mode)
* `sensu_NODENAME.key` (uses private\_mode)
* `sensu_ca.crt` (uses public\_mode)

These files can then be used by applications requiring a TLS PKI.

You can get the certificates of other nodes using a search. E.g. for the above sensu\_ca client we might have:

    certs = search(:node, "name:*").first['chef_vault_pki']['certs']['sensu_ca']

# Security

This approach to managing a PKI isn't suitable for many situations. The generated CA private key is basically treated as a shared key or password between all authorised (through chef-vault) clients.

It is assumes you that trust all clients and the workstation that created the CA. It also assumes you trust chef-vault.

Because it treats the CA key as a shared key, you cannot revoke a certificate in the traditonal sense. In the same way that a shared password compromise requires the password to be changed everywhere, so it is with chef\_vault\_pki. However, updating the CA key is as simple as re-creating the data bag using the `chef-vault-pki` and `chef-vault` commands as above. All nodes will automatically detect the CA has changed and will generate new certificates during their next run.

If you want to regenerate a certificate for a client, just delete the CA certificate file on the file system. This will make the client think the CA has changed and so will regenerate all the files.

# Attributes

See `attributes/default.rb` for defaults.

* `node['chef_vault_pki']['data_bag']` - name of the chef\_vault data bag
* `node['chef_vault_pki']['ca']` - name of the CA
* `node['chef_vault_pki']['expires']` - certificate expiry period (in days by default)
* `node['chef_vault_pki']['expires_factor']` - used to calculate the period (a day by default)
* `node['chef_vault_pki']['key_size']` - key size to use
* `node['chef_vault_pki']['path']` - where generated certs etc go (managed by Chef)
* `node['chef_vault_pki']['path_mode']` - permissions of the path
* `node['chef_vault_pki']['path_recursive']` - recursively create the path
* `node['chef_vault_pki']['owner']` - file and path owner
* `node['chef_vault_pki']['group']` - file and path group
* `node['chef_vault_pki']['public_mode']` - permissions of public files (e.g. certs)
* `node['chef_vault_pki']['private_mode']` - permissions of private files (e.g. keys)

Generated client certs are added to the node attributes:

* `node['chef_vault_pki']['certs'][CA_NAME][CERT_NAME] = CERT`

# Recipes

* `chef_vault_pki::test` - used by test-kitchen

# Author

fraser.scott@gmail.com
