use_inline_resources

action :create do

  # Used to read the files encrypted in the vault
  r = chef_gem 'chef-vault' do
    action :nothing
  end
  r.run_action(:install)

  # Used to create the CA. Should probably also be used to create client certs.
  r = chef_gem 'chef-vault-pki' do
    action :nothing
  end
  r.run_action(:install)

  Gem.clear_paths

  require 'openssl'
  require 'digest/sha1'
  require 'chef-vault'
  require 'chef-vault-pki'

  # Attributes for the cert
  opt = { 'name' => new_resource.name.gsub(' ', '_') }
  %w[ data_bag ca expires expires_factor key_size path path_mode path_recursive owner group ca_owner ca_group public_mode private_mode bundle_ca standalone ].each do |attr|
    opt[attr] = new_resource.send(attr) ? new_resource.send(attr) : node['chef_vault_pki'][attr]
  end

  # Attributes for the CA
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

  # Standalone method doesn't try to get anything out of encrypted data bags, as they probably don't exist. Instead we'll generate stuff on the fly.
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

  # If the CA changes we will need to regenerate and sign the client certs. This allows us to quickly rotate out all client certificates if a box is compromised and the CA exposed.
  # This should only happen if the CA didn't exist or if it is changed.
  r = ruby_block "ca_change_#{name}" do
    block do
      # run_state is used to store temporary state. Create the scope if it doesn't exist. This is also used as a flag to trigger certificate file creation.
      if not node.run_state.has_key?("chef_vault_pki_#{name}")
        node.run_state["chef_vault_pki_#{name}"] = Mash.new
      end
      # This is a trigger to say the CA has changed, so record that fact.
      node.run_state["chef_vault_pki_#{name}"]['ca_new'] = true
      Chef::Log.debug "chef_vault_pki: CA has changed"
    end
    action :nothing
  end

  # Create/update the CA key
  r = file ::File.join(opt['ca_path'], "#{opt['ca']}.key") do
    owner (opt['ca_owner'] || opt['owner'])
    group (opt['ca_group'] || opt['group'])
    mode opt['private_mode']
    content ca['key']
    only_if { opt['standalone'] }
  end

  # Create/update the CA certificate. If it didn't exist or if it has changed, then call the ca_change trigger as we'll need to ensure we generate the new certificates.
  r = file ::File.join(opt['ca_path'], "#{opt['ca']}.crt") do
    owner (opt['ca_owner'] || opt['owner'])
    group (opt['ca_group'] || opt['group'])
    mode opt['public_mode']
    content ca['cert']
    notifies :create, resources(:ruby_block => "ca_change_#{name}"), :immediately
  end

  # Create the resource for the certificate file, but don't do anything yet because we'll only create the content if the CA changed.
  r = file ::File.join(opt['path'], "#{name}.crt") do
    owner opt['owner']
    group opt['group']
    mode opt['public_mode']
    content lazy { opt['bundle_ca'] ? [node.run_state["chef_vault_pki_#{name}"]['cert'],ca_cert].join("") : node.run_state["chef_vault_pki_#{name}"]['cert'] }
    action :nothing
  end

  # Create the resource for the private key, but don't do anything with it yet.
  r = file ::File.join(opt['path'], "#{name}.key") do
    owner opt['owner']
    group opt['group']
    mode opt['private_mode']
    content lazy { node.run_state["chef_vault_pki_#{name}"]['key'] }
    action :nothing
  end  

  # This block actually creates the X509 certificate if required
  r = ruby_block 'create_new_cert' do
    block do
 
      # We need to read the CA certificate and create a fingerprint for it....
      ca_file = ::File.join(opt['ca_path'], "#{opt['ca']}.crt")
      Chef::Log.debug "chef_vault_pki: Getting fingerprint for #{ca_file}"
      ca_fingerprint = Digest::SHA1.hexdigest(OpenSSL::X509::Certificate.new(::File.open(ca_file).read).to_der)
      Chef::Log.debug "chef_vault_pki: Found fingerprint #{ca_fingerprint}"

      # ... because we will compare it to the existing fingerprint for the CA ...
      begin
        existing_fingerprint = node['chef_vault_pki']['certs'][opt['ca']]["chef_vault_pki_#{name}"]['ca_fingerprint']
      rescue
        existing_fingerprint = ""
      end
      Chef::Log.debug "chef_vault_pki: Existing CA fingerprint for #{opt['ca']} is #{existing_fingerprint}"

      # ... and we will make a note as to whether the CA was created in this run ... #
      begin
        ca_change = node.run_state["chef_vault_pki_#{name}"]['ca_new']
      rescue
        ca_change = false
      end
      Chef::Log.debug "chef_vault_pki: CA changed: #{ca_change}"

      # ... Right, so.. If the CA is new then we'll need to create the client certificate anyway
      # even if the CA hasn't changed as such (ie. file and fingerprint match because they were created
      # earlier). If the CA isn't new and if the fingerprints didn't change, then we won't want to create
      # this client certificate.
      if not ca_change and ca_fingerprint == existing_fingerprint
        Chef::Log.debug "chef_vault_pki: CA not changed and fingerprints matched. Done here."
        next
      end

      # We got here either because the CA is new and we need to create all client certificates, or the fingerprint
      # of the CA changed and we need to rotate out all the certs
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

      # Make sure we have our temporary storage for the run. This is also used as a flag to trigger
      # file creation
      if not node.run_state.has_key?("chef_vault_pki_#{name}")
        node.run_state["chef_vault_pki_#{name}"] = Mash.new
      end

      # We create the cert and key, so make a note of them.
      node.run_state["chef_vault_pki_#{name}"]['cert'] = csr_cert.to_pem
      node.run_state["chef_vault_pki_#{name}"]['key'] = key.to_pem

      # Also create the public record of the cert and fingerprint of the CA used.
      node.set['chef_vault_pki']['certs'][opt['ca']]["chef_vault_pki_#{name}"] = {
        'cert' => csr_cert.to_pem,
        'ca_fingerprint' => ca_fingerprint
      }
    end
  end
 
  # This block triggers the creation of the cert and key files using the content stored in the run_state.
  # We only run if the run_state has the name for this resource, which means it either created a new CA
  # or a new certificate. In either case, we need to write the cert to the the file system.
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
