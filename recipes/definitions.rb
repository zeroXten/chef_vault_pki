define /must have valid key file ['"]?(?<key_file>.+?)['"]? for cert file ['"]?(?<cert_file>.+?)['"]?/ do
  command 'check-cert-key-pair ":::key_file:::" ":::cert_file:::"'
  code <<-EOF
    #!/bin/bash
    key="$1"
    cert="$2"
    key_sig=$(openssl rsa -noout -modulus -in ${key} | openssl md5)
    cert_sig=$(openssl x509 -noout -modulus -in ${cert} | openssl md5)
    if [[ "$cert_sig" == "$key_sig" ]]; then
      echo "OK - Keys match for key ${key} and cert ${cert}"; exit 0
    else
      echo "CRITICAL - Keys don't match for key ${key} and cert ${cert}: ${key_sig} != ${cert_sig}"; exit 2
    fi
  EOF
end

define /must have valid cert file ['"]?(?<cert_file>.+?)['"]? for ca cert file ['"]?(?<ca_cert_file>.+?)['"]?/ do
  command 'check-valid-cert ":::cert_file:::" ":::ca_cert_file:::"'
  code <<-EOF
    #!/bin/bash
    cert="$1"
    ca_cert="$2"
    output=$(openssl verify -CAfile ${ca_cert} ${cert})
    echo "$output" | grep -q OK
    if [[ "$?" -eq "0" ]]; then
      echo "OK - Cert file ${cert} is valid for ca ${ca_cert}"; exit 0
    else
      echo "CRITICAL - Cert file ${cert} is not valid for ca ${ca_cert}: ${output}"; exit 2
    fi
  EOF
end

define /must match subject ['"]?(?<subject>.+?)['"]? for cert file ['"]?(?<cert_file>.+?)['"]?/ do
  command 'check-cert-subject ":::subject:::" ":::cert_file:::"'
  code <<-EOF
    #!/bin/bash
    subject="$1"
    cert="$2"
    output=$(openssl x509 -subject -noout -in ${cert})
    if [[ "$output" == "$subject" ]]; then
      echo "OK - Cert file ${cert} has subject '${subject}'"; exit 0
    else
      echo "CRITICAL - Cert file ${cert} subject '${subject}' does not match '${output}'"; exit 2
    fi
  EOF
end
