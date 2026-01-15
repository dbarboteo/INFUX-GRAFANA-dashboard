#!/bin/bash

# Configurar modo no-interactivo
export DEBIAN_FRONTEND=noninteractive

# Redirigir todo a log file
exec > /var/log/influxdb-install.log 2>&1

echo "=== InfluxDB Installation Started at $(date) ==="

apt update && apt upgrade -y
apt install -y wget gnupg2 python3 python3-pip python3-venv

wget -q https://repos.influxdata.com/influxdata-archive.key
mkdir -p /etc/apt/keyrings
gpg --show-keys --with-fingerprint --with-colons ./influxdata-archive.key 2>&1 | grep -q '^fpr:\+24C975CBA61A024EE1B631787C3D57159FC2F927:$' && cat influxdata-archive.key | gpg --dearmor | tee /etc/apt/keyrings/influxdata-archive.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' | tee /etc/apt/sources.list.d/influxdata.list

apt-get update && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" influxdb

# Eliminar la sección [http] existente y agregar una nueva limpia
cp /etc/influxdb/influxdb.conf /etc/influxdb/influxdb.conf.bak

# Eliminar toda la sección [http] existente (desde [http] hasta la siguiente sección o fin de archivo)
sed -i '/^\[http\]/,/^\[/{/^\[http\]/d; /^\[/!d}' /etc/influxdb/influxdb.conf
sed -i '/^\[http\]/d' /etc/influxdb/influxdb.conf

# Agregar la sección HTTP al final del archivo
cat >> /etc/influxdb/influxdb.conf << 'EOF'

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = false
  flux-enabled = false
EOF

service influxdb start
sleep 5

# Crear base de datos metals_db
influx -execute 'CREATE DATABASE metals_db'

service influxdb status

echo "=== Setting up Mosquito script ==="

# Crear directorio de trabajo
mkdir -p /opt/metals
cd /opt/metals

# Decodificar y guardar archivos
echo "${mosquito_py}" | base64 -d > mosquito.py
echo "${requirements_txt}" | base64 -d > requirements.txt

# Crear entorno virtual
python3 -m venv venv_metals

# Instalar dependencias
source venv_metals/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Crear servicio systemd
cat > /etc/systemd/system/mosquito.service << 'EOFSERVICE'
[Unit]
Description=Metals Price Collector
After=network.target influxdb.service
Requires=influxdb.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/metals
ExecStart=/opt/metals/venv_metals/bin/python3 /opt/metals/mosquito.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Recargar systemd y habilitar servicio
systemctl daemon-reload
systemctl enable mosquito.service
systemctl start mosquito.service

sleep 3
systemctl status mosquito.service

echo "=== InfluxDB Installation Completed at $(date) ==="
