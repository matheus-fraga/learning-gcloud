# Defina as variáveis de ambiente para sua região e zona
export REGION=<sua_regiao>
export ZONE=<sua_zona>

# Tarefa 1: Crie várias instâncias de servidores web

# Crie a Instância VM 1
gcloud compute instances create web1 \
  --zone=$ZONE \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Servidor Web: web1</h3>" | tee /var/www/html/index.html'

# Crie a Instância VM 2
gcloud compute instances create web2 \
  --zone=$ZONE \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Servidor Web: web2</h3>" | tee /var/www/html/index.html'

# Crie a Instância VM 3
gcloud compute instances create web3 \
  --zone=$ZONE \
  --machine-type=e2-small \
  --tags=network-lb-tag \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>Servidor Web: web3</h3>" | tee /var/www/html/index.html'


# Crie uma regra de firewall para tráfego HTTP
gcloud compute firewall-rules create www-firewall-network-lb \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=network-lb-tag


# Tarefa 2: Configure o serviço de balanceamento de carga

# Crie um endereço IP externo estático
gcloud compute addresses create network-lb-ip-1 \
    --region=$REGION

# Crie um check de saúde HTTP
gcloud compute http-health-checks create basic-check

# Crie um pool de destino
gcloud compute target-pools create www-pool \
    --region=$REGION --http-health-check basic-check

# Adicione as instâncias ao pool de destino
gcloud compute target-pools add-instances www-pool \
    --instances=web1,web2,web3 --zone=$ZONE

# Crie uma regra de encaminhamento para o balanceador de carga
gcloud compute forwarding-rules create www-rule \
    --region=$REGION \
    --ports=80 \
    --address=network-lb-ip-1 \
    --target-pool=www-pool

# Obtenha o endereço IP da regra de encaminhamento
IPADDRESS=$(gcloud compute forwarding-rules describe www-rule --region=$REGION --format="json" | jq -r .IPAddress)


# Tarefa 3: Crie um balanceador de carga HTTP

# Crie um modelo de instância
gcloud compute instance-templates create lb-backend-template \
   --region=$REGION \
   --network=default \
   --subnet=default \
   --tags=allow-health-check,techvine \
   --machine-type=e2-medium \
   --image-family=debian-11 \
   --image-project=debian-cloud \
   --metadata=startup-script='#!/bin/bash
     apt-get update
     apt-get install apache2 -y
     a2ensite default-ssl
     a2enmod ssl
     vm_hostname="$(curl -H "Metadata-Flavor:Google" \
     http://169.254.169.254/computeMetadata/v1/instance/name)"
     echo "Página servida a partir de: $vm_hostname" | \
     tee /var/www/html/index.html
     systemctl restart apache2'

# Crie um grupo de instâncias gerenciado
gcloud compute instance-groups managed create lb-backend-group \
   --template=lb-backend-template --size=2 --zone=$ZONE

# Crie uma regra de firewall para os checks de saúde
gcloud compute firewall-rules create fw-allow-health-check \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:80

# Crie um endereço global IPv4
gcloud compute addresses create lb-ipv4-1 \
  --ip-version=IPV4 \
  --global

# Obtenha o endereço IP do endereço global
IPADDRESS=$(gcloud compute addresses describe lb-ipv4-1 \
  --format="get(address)" --global)

# Crie um check de saúde HTTP
gcloud compute health-checks create http http-basic-check \
  --port 80

# Crie um serviço de backend
gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global

# Adicione o grupo de instâncias gerenciado ao serviço de backend
gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone=$ZONE \
  --global

# Crie um mapa de URLs
gcloud compute url-maps create web-map-http \
  --default-service web-backend-service

# Crie um proxy HTTP de destino
gcloud compute target-http-proxies create http-lb-proxy \
  --url-map web-map-http

# Crie uma regra de encaminhamento para o balanceador de carga
gcloud compute forwarding-rules create http-content-rule \
  --address=$IPADDRESS \
  --global \
  --target-http-proxy=http-lb-proxy \
  --ports=80
