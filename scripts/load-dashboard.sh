#!/bin/bash

# Esperar a que Grafana esté disponible
until curl -s http://localhost:3000/api/health > /dev/null 2>&1; do
  echo "Esperando a que Grafana esté disponible..."
  sleep 5
done

# Esperar un poco más para asegurar que Grafana esté completamente listo
sleep 10

# Preparar el JSON para la API (envolver el dashboard)
DASHBOARD_JSON=$(cat /opt/grafana-dashboards/dashboard.json | jq -c '{dashboard: ., overwrite: true, message: "Dashboard auto-provisionado"}')

# Cargar el dashboard via API
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d "$DASHBOARD_JSON" \
  http://localhost:3000/api/dashboards/db

echo "Dashboard cargado exitosamente"
