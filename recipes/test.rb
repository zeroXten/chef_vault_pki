include_recipe 'apt'
include_recipe 'sensu_spec'

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

sensu_spec 'cert file' do
  command "check_cmd -c 'test -r #{cert}' -e 0"
end

sensu_spec 'key file' do
  command "check_cmd -c 'test -r #{key}' -e 0"
end

sensu_spec 'ca file' do
  command "check_cmd -c 'test -r #{ca_cert}' -e 0"
end

sensu_spec 'verify cert key' do
  command "check_cmd -c '(openssl x509 -noout -modulus -in #{cert} | openssl md5 ; openssl rsa -noout -modulus -in #{key} | openssl md5) | uniq | wc -l' -o 1"
end

sensu_spec 'verify cert' do
  command "check_cmd -c 'openssl verify -CAfile #{ca_cert} #{cert}' -o 'OK'"
end
