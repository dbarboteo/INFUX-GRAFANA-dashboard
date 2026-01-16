# InfluxDB + Grafana Dashboard en AWS

Proyecto de infraestructura como código (IaC) usando Terraform para desplegar automáticamente un sistema completo de monitoreo de precios de metales preciosos en AWS, utilizando InfluxDB como base de datos de series temporales y Grafana para visualización.

## 📋 Descripción

Este proyecto automatiza el despliegue de una arquitectura de dos instancias EC2 en AWS:

- **Instancia InfluxDB**: Servidor de base de datos de series temporales que almacena los precios de metales preciosos (Oro, Plata, Platino, Cobre) recopilados a través de una API externa.
- **Instancia Grafana**: Servidor de visualización con dashboards pre-configurados para monitorear los datos en tiempo real.

El sistema incluye un script Python (`mosquito.py`) que se ejecuta automáticamente como servicio systemd, recopilando datos cada 5 segundos desde la API de precios de metales.

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────┐
│                    AWS VPC                      │
│                                                 │
│  ┌──────────────────┐      ┌─────────────────┐  │
│  │  EC2 InfluxDB    │◄─────┤  EC2 Grafana    │  │
│  │  - InfluxDB 1.x  │      │  - Grafana      │  │
│  │  - mosquito.py   │      │  - Dashboard    │  │
│  │  - Port 8086     │      │  - Port 3000    │  │
│  │  (privado)       │      │  (público)      │  │
│  └──────────────────┘      └─────────────────┘  │
│         │                          │            │
│         │                    Elastic IP         │
│         │                          │            │
└─────────┼──────────────────────────┼────────────┘
          │                          │
          │                          ▼
          │                    Internet (HTTP:3000)
          │
          ▼
    API gold-api.com
```

### Componentes de Seguridad

- **Security Group InfluxDB**: 
  - SSH (puerto 22) desde cualquier IP
  - InfluxDB (puerto 8086) solo desde el Security Group de Grafana
  
- **Security Group Grafana**:
  - SSH (puerto 22) desde cualquier IP
  - HTTP (puerto 3000) desde cualquier IP
  
- **Elastic IP**: IP estática asignada a la instancia de Grafana para acceso consistente

## 🚀 Requisitos Previos

Antes de comenzar, asegúrate de tener instalado:

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configurado con credenciales válidas
- Cuenta de AWS con permisos para crear recursos (EC2, VPC, Security Groups, EIP)

## 📦 Estructura del Proyecto

```
INFUX-GRAFANA-dashboard/
├── main.tf                      # Configuración principal de Terraform
├── terraform.tfstate            # Estado de Terraform (generado)
├── terraform-key.pem            # Clave SSH privada (generada automáticamente)
├── README.md                    # Este archivo
└── scripts/
    ├── influxdb.sh             # Script de instalación de InfluxDB
    ├── grafana.sh              # Script de instalación de Grafana
    ├── mosquito.py             # Script Python para recopilación de datos
    ├── requirements.txt        # Dependencias Python
    ├── dashboard-fixed.json    # Configuración del dashboard de Grafana
    └── load-dashboard.sh       # Script para cargar el dashboard
```

## 🔧 Instalación y Despliegue

### 1. Clonar el Repositorio

```bash
git clone <url-del-repositorio>
cd INFUX-GRAFANA-dashboard
```

### 2. Configurar AWS CLI

Asegúrate de que tienes configuradas tus credenciales de AWS:

```bash
aws configure
```

### 3. Inicializar Terraform

```bash
terraform init
```

### 4. Revisar el Plan de Ejecución

```bash
terraform plan
```

### 5. Aplicar la Configuración

```bash
terraform apply
```

Escribe `yes` cuando se te solicite confirmar.

### 6. Obtener Información de Conexión

Una vez completado el despliegue, Terraform mostrará las siguientes salidas:

```
influxdb_public_ip      = "X.X.X.X"
influxdb_private_ip     = "10.0.X.X"
grafana_public_ip       = "Y.Y.Y.Y"
grafana_url             = "http://Y.Y.Y.Y:3000"
ssh_connection_influxdb = "ssh -i ./terraform-key.pem ubuntu@X.X.X.X"
ssh_connection_grafana  = "ssh -i ./terraform-key.pem ubuntu@Y.Y.Y.Y"
```

## 🌐 Acceso a Grafana

1. Abre tu navegador y accede a la URL proporcionada en `grafana_url`
2. Credenciales por defecto:
   - **Usuario**: `admin`
   - **Contraseña**: `admin`
3. Se te pedirá cambiar la contraseña en el primer inicio de sesión
4. El dashboard de metales preciosos se cargará automáticamente

## 🔌 Conexión SSH a las Instancias

### Conectar a InfluxDB

```bash
ssh -i ./terraform-key.pem ubuntu@<influxdb_public_ip>
```

### Conectar a Grafana

```bash
ssh -i ./terraform-key.pem ubuntu@<grafana_public_ip>
```

## 📊 Funcionamiento del Sistema

### Script de Recopilación de Datos (mosquito.py)

El script Python se ejecuta automáticamente como servicio systemd y:

1. Crea un entorno virtual Python
2. Instala las dependencias necesarias (`requests`, `influxdb`)
3. Consulta la API de precios cada 5 segundos para:
   - **XAU** (Oro)
   - **XAG** (Plata)
   - **XPT** (Platino)
   - **HG** (Cobre)
4. Almacena los datos en la base de datos `metals_db` en InfluxDB

### Gestión del Servicio mosquito.py

```bash
# Ver estado del servicio
sudo systemctl status mosquito.service

# Ver logs en tiempo real
sudo journalctl -u mosquito.service -f

# Reiniciar el servicio
sudo systemctl restart mosquito.service

# Detener el servicio
sudo systemctl stop mosquito.service
```

### Verificar InfluxDB

```bash
# Conectar a InfluxDB CLI
influx

# Dentro del CLI
USE metals_db
SHOW MEASUREMENTS
SELECT * FROM metals LIMIT 10
```

## 🛠️ Configuración Avanzada

### Modificar el Intervalo de Recopilación

Edita el archivo `scripts/mosquito.py` y cambia el valor en la línea:

```python
time.sleep(5)  # Cambiar a los segundos deseados
```

Luego ejecuta `terraform apply` para actualizar.

### Agregar Nuevos Metales

En `scripts/mosquito.py`, modifica el diccionario `metals`:

```python
metals = {
    "XAU": "Oro",
    "XAG": "Plata",
    "XPT": "Platino",
    "HG": "Cobre",
    "NUEVO_SIMBOLO": "Nuevo Metal"
}
```

### Cambiar Tipo de Instancia

En `main.tf`, modifica la línea:

```hcl
instance_type = "t2.micro"  # Cambiar a t2.small, t2.medium, etc.
```

## 🧹 Limpieza de Recursos

Para eliminar todos los recursos creados en AWS:

```bash
terraform destroy
```

Escribe `yes` cuando se te solicite confirmar.

> ⚠️ **Advertencia**: Esta acción eliminará todas las instancias, datos y configuraciones. Esta operación es irreversible.

## 📝 Variables de Entorno

El proyecto utiliza las siguientes variables internas (configuradas en `main.tf`):

- `INFLUX_HOST`: `localhost`
- `INFLUX_PORT`: `8086`
- `INFLUX_DB`: `metals_db`
- AWS Region: `us-east-1`



## 📈 Monitoreo y Logs

### Logs de InfluxDB

```bash
sudo journalctl -u influxdb.service -f
tail -f /var/log/influxdb-install.log
```

### Logs de Grafana

```bash
sudo journalctl -u grafana-server.service -f
tail -f /var/log/grafana/grafana.log
```

### Logs del Script de Recopilación

```bash
sudo journalctl -u mosquito.service -f
```


## 📄 Licencia

Este proyecto es de código abierto y está disponible bajo la licencia MIT.

## 👨‍💻 Autor

**Diego Barboteo**

## 🙏 Agradecimientos

- API de precios de metales: [gold-api.com](https://www.gold-api.com/)
- InfluxDB por InfluxData
- Grafana Labs
- Terraform by HashiCorp

---

**Nota**: Este proyecto fue diseñado para fines educativos y de demostración. Para uso en producción, considera implementar medidas adicionales de seguridad, alta disponibilidad y respaldo de datos.
