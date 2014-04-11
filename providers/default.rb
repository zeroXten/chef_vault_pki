# RTFM
def whyrun_supported?
  true
end

use_inline_resources

action :create do
  r = chef_gem 'chef-vault' do
    action :nothing
  end
  r.run_action(:install)

  r = chef_gem 'chef-vault-pki' do
    action :nothing
  end
  r.run_action(:install)

  Gem.clear_paths

  require 'openssl'
  require 'chef-vault'
  require 'chef-vault-pki'

  opt = { 'name' => new_resource.name.gsub(' ', '_') }
  %w[ data_bag ca expires expires_factor key_size path path_mode path_recursive owner group public_mode private_mode bundle_ca standalone ].each do |attr|
    opt[attr] = new_resource.send(attr) ? new_resource.send(attr) : node['chef_vault_pki'][attr]
  end

  r = directory opt['path'] do
    owner opt['owner']
    group opt['group']
    mode opt['path_mode']
    recursive opt['path_recursive']
    action :nothing
  end
  r.run_action(:create)

  if opt['standalone']
    c = ChefVaultPKI::CA.new(opt.select {|k,v| %w[key_size expires expires_factor name].include?(k) })
    c.generate!
    ca_cert = c.cert
    ca_key = c.key
    ca = { 'cert' => ca_cert.to_pem, 'key' => ca_key.to_pem }
  else
    ca = ChefVault::Item.load(opt['data_bag'], opt['ca'])
    ca_key = OpenSSL::PKey::RSA.new ca['key']
    ca_cert = OpenSSL::X509::Certificate.new ca['cert']
  end

  r = file ::File.join(opt['path'], "#{opt['name']}.crt") do
    owner opt['owner']
    group opt['group']
    mode opt['public_mode']
    content lazy { opt['bundle_ca'] ? [ca_cert, node.run_state['chef_vault_pki']['cert']].join("\n") : node.run_state['chef_vault_pki']['cert'] }
    action :nothing
  end

  r = file ::File.join(opt['path'], "#{opt['name']}.key") do
    owner opt['owner']
    group opt['group']
    mode opt['private_mode']
    content lazy { node.run_state['chef_vault_pki']['key'] }
    action :nothing
  end  

  r = ruby_block 'create_new_cert' do
    block do

      key = OpenSSL::PKey::RSA.new opt['key_size']

      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.parse "CN=#{opt['name']}"
      csr.public_key = key.public_key
      csr.sign key, OpenSSL::Digest::SHA1.new

      csr_cert = OpenSSL::X509::Certificate.new
      csr_cert.serial = 0
      csr_cert.version = 2
      csr_cert.not_before = Time.now
      csr_cert.not_after = Time.now + opt['expires'] * opt['expires_factor']

      csr_cert.subject = csr.subject
      csr_cert.public_key = csr.public_key
      csr_cert.issuer = ca_cert.subject

      extension_factory = OpenSSL::X509::ExtensionFactory.new
      extension_factory.subject_certificate = csr_cert
      extension_factory.issuer_certificate = ca_cert
      extension_factory.create_extension 'basicConstraints', 'CA:FALSE'
      extension_factory.create_extension 'keyUsage', 'keyEncipherment,dataEncipherment,digitalSignature'
      extension_factory.create_extension 'subjectKeyIdentifier', 'hash'

      csr_cert.sign ca_key, OpenSSL::Digest::SHA1.new

      node.run_state['chef_vault_pki'] = { 'cert' => csr_cert.to_pem, 'key' => key.to_pem }

      node.set['chef_vault_pki']['certs'][opt['ca']][opt['name']] = csr_cert.to_pem
    end
    action :nothing
    notifies :create, resources(:file => ::File.join(opt['path'], "#{opt['name']}.crt")), :immediately
    notifies :create, resources(:file => ::File.join(opt['path'], "#{opt['name']}.key")), :immediately
  end

  r = file ::File.join(opt['path'], "#{opt['ca']}.crt") do
    owner opt['owner']
    group opt['group']
    mode opt['public_mode']
    content ca['cert']
    notifies :create, resources(:ruby_block => 'create_new_cert'), :immediately
  end

  new_resource.updated_by_last_action(true) if r.updated_by_last_action?
end

action :delete do
  opt = { 'name' => new_resource.name.gsub(' ', '_') }
  %w[ ca path ].each do |attr|
    opt[attr] = new_resource.send(attr) ? new_resource.send(attr) : node['chef_vault_pki'][attr]
  end

  r = file ::File.join(opt['path'], "#{opt['name']}.crt") do
    action :delete
  end
  new_resource.updated_by_last_action(true) if r.updated_by_last_action?

  r = file ::File.join(opt['path'], "#{opt['name']}.key") do
    action :delete
  end  
  new_resource.updated_by_last_action(true) if r.updated_by_last_action?

  r = file ::File.join(opt['path'], "#{opt['ca']}.crt") do
    action :delete
  end
  new_resource.updated_by_last_action(true) if r.updated_by_last_action?
end
