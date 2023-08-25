# Install and configure Grafana

This is particular project to learning shell script. This script install and configure:

- Grafana
- Prometheus
- Node Exporter

## Todo

- [x] Detect OS system
- [x] Detect architecture
- [x] Auto detect lasted version of Prometheus and downnload
- [x] Create system users to administrate Node Exporter and Grafana
- [x] Auto configure grafana.yml
- [x] Create all logs during install
- [x] Create installer using "whiptail"
- [ ] Auto install using curl without download script.
- [ ] Create Unistaller

(comand: sudo systemctl stop prometheus;sudo systemctl disable prometheus;sudo userdel prometheus;sudo rm -rf /var/lib/prometheus/;sudo rm -rf /tmp/prometheus*;sudo rm -rf /etc/prometheus*;sudo rm /usr/local/bin/prom\*;sudo rm /etc/systemd/system/prometheus.service;sudo systemctl stop node_exporter;sudo systemctl disable node_exporter;sudo rm /etc/systemd/system/node_exporter.service;sudo rm /usr/local/bin/node_exporter)

#

# Creation Diary

23/08/2023 - Project Started
24/08/2023 - Prometheus scripts worked
25/08/1992 - Project Finally.
