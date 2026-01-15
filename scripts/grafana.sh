#!/bin/bash

apt update && apt upgrade -y

apt-get install -y apt-transport-https wget
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee -a /etc/apt/sources.list.d/grafana.list

apt-get update
apt-get install -y grafana jq

# Crear directorio de provisioning para datasources
mkdir -p /etc/grafana/provisioning/datasources

# Crear archivo de configuración del datasource InfluxDB
cat > /etc/grafana/provisioning/datasources/influxdb.yaml <<'EOF'
apiVersion: 1

datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://${influxdb_private_ip}:8086
    database: metals_db
    uid: influxdb-metals
    isDefault: true
    jsonData:
      httpMode: GET
    editable: true
EOF

# Crear directorio para dashboards temporal
mkdir -p /opt/grafana-dashboards

# Crear directorio de provisioning para dashboards
mkdir -p /etc/grafana/provisioning/dashboards

# Configurar el provisioning de dashboards
cat > /etc/grafana/provisioning/dashboards/dashboards.yaml <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

# Crear directorio de dashboards de Grafana
mkdir -p /var/lib/grafana/dashboards

# Asegurar permisos correctos
chown -R grafana:grafana /etc/grafana/provisioning
chown -R grafana:grafana /var/lib/grafana/dashboards

systemctl enable grafana-server
systemctl start grafana-server

# Mover archivo del dashboard desde /opt a la ruta de Grafana
if [ -f /opt/grafana-dashboards/dashboard.json ]; then
    cp /opt/grafana-dashboards/dashboard.json /var/lib/grafana/dashboards/dashboard.json
    chown grafana:grafana /var/lib/grafana/dashboards/dashboard.json
    echo "Dashboard JSON copiado a /var/lib/grafana/dashboards/dashboard.json"
fi
