include_recipe 'apt'

include_recipe 'sensu_spec'
include_recipe 'chef_vault_pki::definitions'

chef_vault_pki 'chef_vault_test' do
  data_bag 'chef_vault_pki'
  ca 'chef_vault_pki_ca'
  expires 3655
  expires_factor 60 * 60 * 24
  key_size 2048
  path '/opt/chef_vault_pki'
  path_mode 0755
  path_recursive = false
  owner 'root'
  group 'root'
  public_mode 0640
  private_mode 0600
  bundle_ca false
end

cert = ::File.join(node['chef_vault_pki']['path'], "chef_vault_test.crt")
key = ::File.join(node['chef_vault_pki']['path'], "chef_vault_test.key")
ca_cert = ::File.join(node['chef_vault_pki']['path'], "chef_vault_pki_ca.crt")

describe 'chef_vault_pki' do

  describe 'cert' do
    it "must have readable file #{cert}"
  end

  describe 'key' do
    it "must have readable file #{key}"
  end

  describe 'ca' do
    it "must have readable file #{ca_cert}"
  end

  describe 'key pair' do
    it "must have valid key file '#{key}' for cert file '#{cert}'"
  end

  describe 'valid cert' do
    it "must have valid cert file '#{cert}' for ca cert file '#{ca_cert}'"
  end

  describe 'ca name' do
    it "must match subject 'subject= /CN=chef_vault_pki_ca' for cert file #{ca_cert}"
  end

end

# Two certs one CA
chef_vault_pki 'server_a' do
  ca 'twocerts_ca'
  ca_path '/opt/twocerts_ca'
  path '/opt/server_a'
end

chef_vault_pki 'server_b' do
  ca 'twocerts_ca'
  ca_path '/opt/twocerts_ca'
  path '/opt/server_b'
end

describe 'chef_vault_pki two certs' do
  %w[ server_a server_b twocerts_ca ].each do |f|
    describe "#{f} cert" do
      it "must have readable file '/opt/#{f}/#{f}.crt'"
    end

    describe "#{f} key" do
      it "must have readable file '/opt/#{f}/#{f}.key'"
    end

    describe "#{f} key pair" do
      it "must have valid key file '/opt/#{f}/#{f}.key' for cert file '/opt/#{f}/#{f}.crt'"
    end
  end

  describe 'ca name' do
    it "must match subject 'subject= /CN=twocerts_ca' for cert file '/opt/twocerts_ca/twocerts_ca.crt'"
  end

  
  %w[ server_a server_b ].each do |f|
    describe "#{f} valid cert" do
      it "must have valid cert file '/opt/#{f}/#{f}.crt' for ca cert file '/opt/twocerts_ca/twocerts_ca.crt'"
    end
  end

end
