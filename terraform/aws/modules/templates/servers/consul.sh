#!/usr/bin/env bash
echo "==> Consul (server)"
echo "--> Fetching OSS binaries"
install_from_url "consul" "${consul_url}"


echo "--> Writing configuration"
sudo mkdir -p /mnt/consul
sudo mkdir -p /etc/consul.d
sudo tee /etc/consul.d/config.json > /dev/null <<EOF
{
  "datacenter": "${datacenter}",
  "primary_datacenter":  "${primary_datacenter}",
  "bootstrap_expect": ${server_number},
  "advertise_addr": "$(private_ip)",
  "advertise_addr_wan": "$(public_ip)",
  "bind_addr": "0.0.0.0",
  "client_addr": "0.0.0.0",
  "data_dir": "/mnt/consul",
  "leave_on_terminate": true,
  "node_name": "${node_name}",
  "retry_join": ["provider=aws tag_key=consul_join tag_value=${consul_join}"],
  "server": true,
  "ports": {
    "http": 8500,
    "https": 8501,
    "grpc": 8502
  },
  "connect":{
    "enabled": true
  },
  "ui": true,
  "enable_central_service_config":true,
  "autopilot": {
    "cleanup_dead_servers": true,
    "last_contact_threshold": "200ms",
    "max_trailing_logs": 250,
    "server_stabilization_time": "10s",
    "disable_upgrade_migration": false
  },
  "telemetry": {
    "disable_hostname": true,
    "prometheus_retention_time": "30s"
  }
}
EOF

echo "--> Writing profile"
sudo tee /etc/profile.d/consul.sh > /dev/null <<"EOF"
alias conslu="consul"
alias ocnsul="consul"
EOF
source /etc/profile.d/consul.sh

echo "--> Generating systemd configuration"
sudo tee /etc/systemd/system/consul.service > /dev/null <<"EOF"
[Unit]
Description=Consul
Documentation=https://www.consul.io/docs/
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
ExecStart=/usr/local/bin/consul agent -config-dir="/etc/consul.d"
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable consul
sudo systemctl restart consul

echo "--> Installing dnsmasq"
ssh-apt install dnsmasq
sudo tee /etc/dnsmasq.d/10-consul > /dev/null <<"EOF"
server=/consul/127.0.0.1#8600
no-poll
server=8.8.8.8
server=8.8.4.4
cache-size=0
EOF
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

echo "--> Waiting for all Consul servers"
while [ "$(consul members 2>&1 | grep "server" | grep "alive" | wc -l)" -lt "${server_number}" ]; do
  sleep 3
done

echo "--> Waiting for Consul leader"
while [ -z "$(curl -s http://127.0.0.1:8500/v1/status/leader)" ]; do
  sleep 3
done


echo "==> Consul is done!"
