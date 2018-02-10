#
# Cookbook Name:: l2tp-ipsec
# Attributes:: default
#
# Copyright 2014-2016 Nephila Graphic, Li-Te Chen
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

default['l2tp-ipsec']['ipsec-package'] = 'openswan'

default['l2tp-ipsec']['public_interface'] = 'eth0'
default['l2tp-ipsec']['private_interface'] = 'eth0'

def filter_global_addresses(addresses)
  addresses.map do |idata|
    idata['addresses'].select do |_, info|
      info['family'] == 'inet' && info['scope'] == 'Global'
    end.keys
  end.flatten.first
end

# Performs a search through all interfaces, looking for Global addresses.
# It allows for multi-address interfaces.
public_ip = filter_global_addresses(
  node['network']['interfaces'].select do |iface, _|
    iface =~ /#{node['l2tp-ipsec']['public_interface']}(:[0-9]+)?/
  end.values
)

private_ip = filter_global_addresses(
  node['network']['interfaces'].select do |iface, _|
    iface =~ /#{node['l2tp-ipsec']['private_interface']}(:[0-9]+)?/
  end.values
)

default['l2tp-ipsec']['public_ip'] = public_ip
Chef::Log.debug "Using public IP #{public_ip} for l2tp-ipsec from public interface #{node['l2tp-ipsec']['public_interface']}"

default['l2tp-ipsec']['private_ip'] = private_ip
Chef::Log.debug "Using private IP #{private_ip} for l2tp-ipsec from private interface #{node['l2tp-ipsec']['private_interface']}"

default['l2tp-ipsec']['users'] = []

default['l2tp-ipsec']['ppp_link_network'] = '10.55.55.0/24'

default['l2tp-ipsec']['xl2tpd_path'] = '/etc/xl2tpd'
default['l2tp-ipsec']['ppp_path'] = '/etc/ppp'
default['l2tp-ipsec']['pppoptfile'] = File.join(node['l2tp-ipsec']['ppp_path'], 'options.xl2tpd')

default['l2tp-ipsec']['ipsec-conf']['config'] = {
  'version 2' => {},
  'config setup' => {
    'dumpdir' => '/var/run/pluto/',
    'nat_traversal' => 'yes',
    'virtual_private' => "%v4:!#{node['l2tp-ipsec']['ppp_link_network']},%v4:!#{node['l2tp-ipsec']['private_ip']}/32",
    'protostack' => 'netkey',
    'force_keepalive' => 'yes',
    'keep_alive' => '60',
    'listen' => node['l2tp-ipsec']['public_ip'],
  },
  'conn L2TP-PSK-noNAT' => {
    'authby' => 'secret',
    'pfs' => 'no',
    'auto' => 'add',
    'keyingtries' => '3',
    'rekey' => 'no',

    # https://lists.openswan.org/pipermail/users/2014-April/022947.html
    # specifies the phase 1 encryption scheme, the hashing algorithm, and the diffie-hellman group. The modp1024 is for Diffie-Hellman 2. Why 'modp' instead of dh? DH2 is a 1028 bit encryption algorithm that modulo's a prime number, e.g. modp1028. See RFC 5114 for details or the wiki page on diffie hellmann, if interested.
    'ike' => 'aes256-sha1,aes128-sha1,3des-sha1',
    'phase2alg' => 'aes256-sha1,aes128-sha1,3des-sha1',

    # Apple iOS doesn't send delete notify so we need dead peer detection to detect vanishing clients
    'dpddelay' => '30',
    'dpdtimeout' => '120',
    'dpdaction' => 'clear',

    # Set ikelifetime and keylife to same defaults windows has
    'ikelifetime' => '8h',
    'keylife' => '1h',
    'type' => 'transport',

    # Replace IP address with your local IP
    'left' => node['l2tp-ipsec']['public_ip'],

    # For updated Windows 2000/XP clients, to support old clients as well, use leftprotoport=17/%any
    'leftprotoport' => '17/1701',
    'right' => '%any',
    'rightprotoport' => '17/%any',

    # force all to be nat'ed. because of iOS
    # 'forceencaps' => 'yes',
  }
}

default['l2tp-ipsec']['ipsec-secrets']['config'] = {
  "#{node['l2tp-ipsec']['public_ip']} %any" => "PSK \"preshared_secret\""
}

default['l2tp-ipsec']['xl2tpd-conf']['config'] = {
  'global' => {
    'ipsec saref' => 'yes'
  },
  'lns default' => {
    'ip range' => '10.55.55.5-10.55.55.100',
    'local ip' => '10.55.55.4',
    'refuse chap' => 'yes',
    'refuse pap' => 'yes',
    'require authentication' => 'yes',
    'ppp debug' => 'yes',
    'pppoptfile' => node['l2tp-ipsec']['pppoptfile'],
    'length bit' => 'yes',
  }
}

default['l2tp-ipsec']['options-xl2tpd']['config'] = {
  'require-mschap-v2' => '',
  'ms-dns' => ['8.8.8.8', '8.8.4.4'],
  'asyncmap' => '0',
  'auth' => '',
  'crtscts' => '',
  'lock' => '',
  'hide-password' => '',
  'modem' => '',
  # 'debug' => '',
  'name' => 'l2tpd',
  'proxyarp' => '',
  'lcp-echo-interval' => '30',
  'lcp-echo-failure' => '4',
}
