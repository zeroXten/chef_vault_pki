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
  require 'digest/sha1'
  require 'chef-vault'
  require 'chef-vault-pki'

  opt = { 'name' => new_resource.name.gsub(' ', '_') }
  %w[ data_bag ca expires expires_factor key_size path path_mode path_recursive owner group ca_owner ca_group public_mode private_mode bundle_ca standalone ].each do |attr|
    opt[attr] = new_resource.send(attr) ? new_resource.send(attr) : node['chef_vault_pki'][attr]
  end

  %w[ path path_mode path_recursive ].each do |attr|
    ca_attr = "ca_#{attr}"
    if new_resource.send(ca_attr)
      opt[ca_attr] = new_resource.send(ca_attr)
    elsif not node['chef_vault_pki'][ca_attr].nil?
      opt[ca_attr] = node['chef_vault_pki'][ca_attr]
    else
      opt[ca_attr] = opt[attr]
    end
  end

  name = opt['name']

  r = directory opt['path'] do
    owner opt['owner']
    group opt['group']
    mode opt['path_mode']
    recursive opt['path_recursive']
    action :nothing
  end
  r.run_action(:create)

  r = directory opt['ca_path'] do
    owner (opt['ca_owner'] || opt['owner'])
    group (opt['ca_group'] || opt['group'])
    mode opt['ca_path_mode']
    recursive opt['ca_path_recursive']
    not_if { opt['path'] == opt['ca_path'] }
    action :nothing
  end
  r.run_action(:create)


  if opt['standalone']
    Chef::Log.debug "chef_vault_pki: In standalone mode"

    ca_cert_file = ::File.join(opt['ca_path'], "#{opt['ca']}.crt")
    ca_key_file = ::File.join(opt['ca_path'], "#{opt['ca']}.key")
    if ::File.exist?(ca_key_file)
      Chef::Log.debug "chef_vault_pki: CA Key file #{ca_key_file} exists, reading"
      ca_cert = OpenSSL::X509::Certificate.new ::File.open(ca_cert_file).read
      ca_key = OpenSSL::PKey::RSA.new ::File.open(ca_key_file).read
      ca = { 'cert' => ca_cert.to_pem, 'key' => ca_key.to_pem }
    else
      Chef::Log.debug "chef_vault_pki: No CA found, generating one"
      Chef::Log.debug opt.select {|k,v| %w[key_size expires expires_factor ca].include?(k) }.to_s
      c = ChefVaultPKI::CA.new(:key_size => opt['key_size'], :expires => opt['expires'], :expires_factor => opt['expires_factor'], :name => opt['ca'])
      c.generate!
      ca_cert = c.cert
      ca_key = c.key
      ca = { 'cert' => ca_cert.to_pem, 'key' => ca_key.to_pem }
    end
  else
    Chef::Log.debug "chef_vault_pki: In client mode, reading CA #{opt['ca']} from chef-vault data bag #{opt['data_bag']}"
    ca = ChefVault::Item.load(opt['data_bag'], opt['ca'])
    ca_key = OpenSSL::PKey::RSA.new ca['key']
    ca_cert = OpenSSL::X509::Certificate.new ca['cert']
  end

  r = ruby_block "ca_change_#{name}" do
    block do 
      if not node.run_state.has_key?("chef_vault_pki_#{name}")
        node.run_state["chef_vault_pki_#{name}"] = Mash.new
      end
      node.run_state["chef_vault_pki_#{name}"]['ca_new'] = true
      Chef::Log.debug "chef_vault_pki: CA has changed"
    end
    action :nothing
  end

  r = file ::File.join(opt['ca_path'], "#{opt['ca']}.key") do
    owner (opt['ca_owner'] || opt['owner'])
    group (opt['ca_group'] || opt['group'])
    mode opt['private_mode']
    content ca['key']
    only_if { opt['standalone'] }
  end

  r = file ::File.join(opt['ca_path'], "#{opt['ca']}.crt") do
    owner (opt['ca_owner'] || opt['owner'])
    group (opt['ca_group'] || opt['group'])
    mode opt['public_mode']
    content ca['cert']
    notifies :create, resources(:ruby_block => "ca_change_#{name}"), :immediately
  end

  r = file ::File.join(opt['path'], "#{name}.crt") do
    owner opt['owner']
    group opt['group']
    mode opt['public_mode']
    content lazy { opt['bundle_ca'] ? [node.run_state["chef_vault_pki_#{name}"]['cert'],ca_cert].join("") : node.run_state["chef_vault_pki_#{name}"]['cert'] }
    action :nothing
  end

  r = file ::File.join(opt['path'], "#{name}.key") do
    owner opt['owner']
    group opt['group']
    mode opt['private_mode']
    content lazy { node.run_state["chef_vault_pki_#{name}"]['key'] }
    action :nothing
  end  

  r = ruby_block 'create_new_cert' do
    block do

      ca_file = ::File.join(opt['ca_path'], "#{opt['ca']}.crt")
      Chef::Log.debug "chef_vault_pki: Getting fingerprint for #{ca_file}"
      ca_fingerprint = Digest::SHA1.hexdigest(OpenSSL::X509::Certificate.new(::File.open(ca_file).read).to_der)
      Chef::Log.debug "chef_vault_pki: Found fingerprint #{ca_fingerprint}"

      begin
        existing_fingerprint = node['chef_vault_pki']['certs'][opt['ca']]["chef_vault_pki_#{name}"]['ca_fingerprint']
      rescue
        existing_fingerprint = ""
      end

      Chef::Log.debug "chef_vault_pki: Existing CA fingerprint for #{opt['ca']} is #{existing_fingerprint}"

      begin
        ca_change = node.run_state["chef_vault_pki_#{name}"]['ca_new']
      rescue
        ca_change = false
      end
      Chef::Log.debug "chef_vault_pki: CA changed: #{ca_change}"

      if not ca_change and ca_fingerprint == existing_fingerprint
        Chef::Log.debug "chef_vault_pki: CA not changed and fingerprints matched. Done here."
        next
      end

      Chef::Log.debug "chef_vault_pki: Generating CSR for #{name}"
      key = OpenSSL::PKey::RSA.new opt['key_size']

      csr = OpenSSL::X509::Request.new
      csr.version = 0
      csr.subject = OpenSSL::X509::Name.parse "CN=#{name}"
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

      Chef::Log.debug "chef_vault_pki: Signing CSR with CA #{opt['ca']}"
      csr_cert.sign ca_key, OpenSSL::Digest::SHA1.new


      if not node.run_state.has_key?("chef_vault_pki_#{name}")
        node.run_state["chef_vault_pki_#{name}"] = Mash.new
      end
      node.run_state["chef_vault_pki_#{name}"]['cert'] = csr_cert.to_pem
      node.run_state["chef_vault_pki_#{name}"]['key'] = key.to_pem

      node.set['chef_vault_pki']['certs'][opt['ca']]["chef_vault_pki_#{name}"] = {
        'cert' => csr_cert.to_pem,
        'ca_fingerprint' => ca_fingerprint
      }
    end
  end

  r = ruby_block "trigger_new_cert" do
    block do
      Chef::Log.debug "chef_vault_pki: triggering new cert"
    end
    only_if { node.run_state.has_key?("chef_vault_pki_#{name}") }
    notifies :create, resources(:file => ::File.join(opt['path'], "#{name}.crt")), :immediately
    notifies :create, resources(:file => ::File.join(opt['path'], "#{name}.key")), :immediately
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

  r = file ::File.join(opt['path'], "#{opt['ca']}.key") do
    action :delete
    only_if { opt['standalone'] }
  end

  new_resource.updated_by_last_action(true) if r.updated_by_last_action?
end
