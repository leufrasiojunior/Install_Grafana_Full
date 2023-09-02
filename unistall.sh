#!/bin/bash

sudo systemctl stop prometheus
sudo systemctl disable prometheus
sudo userdel prometheus
sudo rm -rf /var/lib/prometheus/
sudo rm -rf /tmp/prometheus*
sudo rm -rf /etc/prometheus*
sudo rm /usr/local/bin/prom*
sudo rm /etc/systemd/system/prometheus.service
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter
sudo rm /etc/systemd/system/node_exporter.service
sudo rm /usr/local/bin/node_exporter
